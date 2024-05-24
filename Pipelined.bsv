import FIFO::*;
import FIFOF::*;
import SpecialFIFOs::*;
import RegFile::*;
import RVUtil::*;
import Vector::*;
import KonataHelper::*;
import Printf::*;
import Ehr::*;
import register_file::*;
import SnapshotTypes::*;

typedef struct { Bit#(4) byte_en; Bit#(32) addr; Bit#(32) data; } Mem deriving (Eq, FShow, Bits);


interface RVIfc;
    method ActionValue#(Mem) getIReq();
    method Action getIResp(Mem a);
    method ActionValue#(Mem) getDReq();
    method Action getDResp(Mem a);
    method ActionValue#(Mem) getMMIOReq();
    method Action getMMIOResp(Mem a);
    // INSTRUMENTATION 
    method Action halt;
    method Action canonicalize;
    method Action restart;
    method Action halted;
    method Action restarted;
    method Action canonicalized;
    method Action request(Bit#(1) operation, ComponentId id, ExchangeAddress addr, ExchangeData data);
    method ActionValue#(ExchangeData) response(ComponentId id);
endinterface

typedef struct { Bool isUnsigned; Bit#(2) size; Bit#(2) offset; Bool mmio; } MemBusiness deriving (Eq, FShow, Bits);

function Bool isMMIO(Bit#(32) addr);
    Bool x = case (addr) 
        32'hf000fff0: True;
        32'hf000fff4: True;
        32'hf000fff8: True;
        32'hf000fffc: True;
        default: False;
    endcase;
    return x;
endfunction

function Bool isStall(Vector#(32, Ehr#(2, Bit#(1))) scoreboard, Bit#(5) rs1, Bit#(5) rs2);
    let ret = False;
    if (rs1 != 0 && rs2 != 0) ret = (scoreboard[rs1][1] == 1 || scoreboard[rs2][1] == 1);
    else if (rs1 != 0) ret = (scoreboard[rs1][1] == 1);
    else if (rs2 != 0) ret = (scoreboard[rs2][1] == 1);
    return ret;
endfunction

typedef struct { Bit#(32) pc;
                 Bit#(32) ppc;
                 Bit#(1) epoch; 
                 KonataId k_id; // <- This is a unique identifier per instructions, for logging purposes
             } F2D deriving (Eq, FShow, Bits);

typedef struct { 
    DecodedInst dinst;
    Bit#(32) pc;
    Bit#(32) ppc;
    Bit#(1) epoch;
    Bit#(32) rv1; 
    Bit#(32) rv2; 
    KonataId k_id; // <- This is a unique identifier per instructions, for logging purposes
    } D2E deriving (Eq, FShow, Bits);

typedef struct { 
    MemBusiness mem_business;
    Bit#(32) data;
    DecodedInst dinst;
    Bool squashed;
    KonataId k_id; // <- This is a unique identifier per instructions, for logging purposes
} E2W deriving (Eq, FShow, Bits);

// writeback < execute < fetch < decode
(* synthesize *)
module mkPipelined(RVIfc);
    // Interface with memory and devices
    FIFO#(Mem) toImem <- mkBypassFIFO;
    FIFO#(Mem) fromImem <- mkBypassFIFO;
    FIFO#(Mem) toDmem <- mkBypassFIFO;
    FIFO#(Mem) fromDmem <- mkBypassFIFO;
    FIFO#(Mem) toMMIO <- mkBypassFIFO;
    FIFO#(Mem) fromMMIO <- mkBypassFIFO;

    // Code to support Konata visualization
    String dumpFile = "output.log" ;
    let lfh <- mkReg(InvalidFile);
    Reg#(KonataId) fresh_id <- mkReg(0);
    Reg#(KonataId) commit_id <- mkReg(0);

    FIFO#(KonataId) retired <- mkFIFO;
    FIFO#(KonataId) squashed <- mkFIFO;

    // Pipeline registers
    FIFOF#(F2D) f2d <- mkFIFOF;
    FIFOF#(D2E) d2e <- mkFIFOF;
    FIFOF#(E2W) e2w <- mkFIFOF;

    Reg#(Bit#(32)) pc <- mkReg(0);
    RFIfc#(5, 32) rf <- mkForwardingRF;
    // RFIfc#(5, 1) scoreboard <- mkForwardingRF;
    Vector#(TExp#(5), Ehr#(2, Bit#(1))) scoreboard <- replicateM(mkEhr(0));
    Ehr#(2, Bit#(1)) epoch_fetch <- mkEhr(0);
    Ehr#(2, Bit#(1)) epoch_execute <- mkEhr(0);
    FIFOF#(Bit#(32)) misprediction <- mkBypassFIFOF;
    FIFOF#(Bit#(32)) exception <- mkBypassFIFOF;
    
    Bool debug = False;    
    Reg#(Bool) starting <- mkReg(True);

    // INSTRUMENTATION

    Reg#(Bool) doHalt <- mkReg(True); // change also
    Reg#(Bool) doCanonicalize <- mkReg(False);
    Reg#(Bool) isCanonicalized <- mkReg(True); // change also 
    FIFOF#(Bit#(32)) responseFIFO <- mkBypassFIFOF;

    rule do_tic_logging;
        if (starting) begin
            let f <- $fopen(dumpFile, "w") ;
            lfh <= f;
            $fwrite(f, "Kanata\t0004\nC=\t1\n");
            starting <= False;
        end
        konataTic(lfh);
    endrule
  
    rule fetch if (!starting && (!doHalt || (doCanonicalize && (exception.notEmpty || misprediction.notEmpty))) && !isCanonicalized);
        Bit#(32) pc_fetched = pc;
        Bit#(32) pc_predicted = pc + 4;
        Bit#(1) epoch = epoch_fetch[0];
        if (exception.notEmpty) begin
            pc_fetched = exception.first();
            pc_predicted = pc_fetched + 4;
            exception.deq();
            epoch_fetch[0] <= ~epoch_fetch[0];
            epoch = ~epoch_fetch[0];
            if (misprediction.notEmpty)
                misprediction.deq();
        end else if (misprediction.notEmpty) begin
            pc_fetched = misprediction.first();
            pc_predicted = pc_fetched + 4;
            misprediction.deq();
            epoch_fetch[0] <= ~epoch_fetch[0];
            epoch = ~epoch_fetch[0];
        end
        pc <= pc_predicted;
        let iid <- fetch1Konata(lfh, fresh_id, 0);
        labelKonataLeft(lfh, iid, $format("0x%x: ", pc_fetched));
        
        f2d.enq(F2D{ pc: pc_fetched, ppc: pc_predicted, epoch: epoch, k_id: iid});
        toImem.enq(Mem{ byte_en: 0, addr: pc_fetched, data: 0});

        if (debug) $display("[Fetch] ", $format("0x%x", pc_fetched));
    endrule

    rule decode if (!starting && (!doHalt || doCanonicalize) && !isCanonicalized);
        let f = f2d.first();
        let instr = fromImem.first();
        let dinst = decodeInst(instr.data);
        let current_id = f.k_id;
        decodeKonata(lfh, current_id);
        labelKonataLeft(lfh, current_id, $format("DASM(%x)", instr.data));
        if (f.epoch != epoch_fetch[1] || !dinst.legal) begin
            f2d.deq();
            fromImem.deq();
            d2e.enq(D2E{ dinst: dinst, pc: f.pc, ppc: f.ppc, epoch: f.epoch, rv1: 0, rv2: 0, k_id: f.k_id});
        end
        else begin
            let rs1_idx = dinst.valid_rs1 ? getInstFields(instr.data).rs1 : 0;
            let rs2_idx = dinst.valid_rs2 ? getInstFields(instr.data).rs2 : 0;
            if (!isStall(scoreboard, rs1_idx, rs2_idx)) begin
                let rs1 <- rf.read(rs1_idx);
                let rs2 <- rf.read(rs2_idx);
                if (dinst.valid_rd) scoreboard[getInstFields(instr.data).rd][1] <= 1;
                f2d.deq();
                fromImem.deq();
                d2e.enq(D2E{ dinst: dinst, pc: f.pc, ppc: f.ppc, epoch: f.epoch, rv1: rs1, rv2: rs2, k_id: f.k_id});
            end
        end
    endrule

    rule execute if (!starting && (!doHalt || doCanonicalize) && !isCanonicalized);
        let d = d2e.first();
        d2e.deq();
        let dInst = d.dinst;
        let current_id = d.k_id;
        let rv1 = d.rv1;
        let rv2 = d.rv2;
        let e_pc = d.pc;
        if (debug) $display("[Execute] ", fshow(dInst));
            executeKonata(lfh, current_id);
        if (d.epoch != epoch_execute[1]) begin
            squashed.enq(current_id);
            e2w.enq(E2W{ mem_business: MemBusiness{isUnsigned: unpack(0), size: unpack(0), offset: unpack(0), mmio: False}, data: unpack(0), dinst: dInst, squashed: True, k_id: current_id});
        end
        else begin
            let imm = getImmediate(dInst);
            Bool mmio = False;
            let data = execALU32(dInst.inst, rv1, rv2, imm, e_pc);
            let isUnsigned = 0;
            let funct3 = getInstFields(dInst.inst).funct3;
            let size = funct3[1:0];
            let addr = rv1 + imm;
            Bit#(2) offset = addr[1:0];
            if (isMemoryInst(dInst)) begin
                let shift_amount = {offset, 3'b0};
                let byte_en = 0;
                case (size) matches
                2'b00: byte_en = 4'b0001 << offset;
                2'b01: byte_en = 4'b0011 << offset;
                2'b10: byte_en = 4'b1111 << offset;
                endcase
                data = rv2 << shift_amount;
                addr = {addr[31:2], 2'b0};
                isUnsigned = funct3[2];
                let type_mem = (dInst.inst[5] == 1) ? byte_en : 0;
                let req = Mem {byte_en : type_mem,
                      addr : addr,
                      data : data};
                if (isMMIO(addr)) begin 
                    if (debug) $display("[Execute] MMIO", fshow(req));
                    toMMIO.enq(req);
                    labelKonataLeft(lfh,current_id, $format(" (MMIO)", fshow(req)));
                    mmio = True;
                end else begin 
                    labelKonataLeft(lfh,current_id, $format(" (MEM)", fshow(req)));
                    toDmem.enq(req);
                end
            end
            else if (isControlInst(dInst)) begin
                labelKonataLeft(lfh,current_id, $format(" (CTRL)"));
                data = e_pc + 4;
            end else begin 
                labelKonataLeft(lfh,current_id, $format(" (ALU)"));
            end
            let controlResult = execControl32(dInst.inst, rv1, rv2, imm, e_pc);
            let nextPc = controlResult.nextPC;
            let mem_business = MemBusiness { isUnsigned : unpack(isUnsigned), size : size, offset : offset, mmio: mmio};
            e2w.enq(E2W{ mem_business: mem_business, data: data, dinst: dInst, squashed: False, k_id: current_id});
            if (nextPc != d.ppc) begin
                misprediction.enq(nextPc);
                epoch_execute[1] <= ~epoch_execute[1];
            end
        end
    endrule

    rule writeback if (!starting && (!doHalt || doCanonicalize) && !isCanonicalized);
        let e = e2w.first;
        e2w.deq();
        let dInst = e.dinst;
        let current_id = e.k_id;
        let data = e.data;
        let mem_business = e.mem_business;
        let fields = getInstFields(dInst.inst);
        writebackKonata(lfh,current_id);
        if (e.squashed) begin
            if (debug) $display("[Writeback] Squashed", fshow(dInst));
            if (dInst.valid_rd) begin
                let rd_idx = fields.rd;
                if (rd_idx != 0) begin scoreboard[rd_idx][0] <= 0; end
            end
        end
        else begin
            retired.enq(current_id);
            if (isMemoryInst(dInst)) begin
                let resp = ?;
                if (mem_business.mmio) begin 
                    resp = fromMMIO.first();
                    fromMMIO.deq();
                end else begin 
                    resp = fromDmem.first();
                    fromDmem.deq();
                end
                let mem_data = resp.data;
                mem_data = mem_data >> {mem_business.offset ,3'b0};
                case ({pack(mem_business.isUnsigned), mem_business.size}) matches
                3'b000 : data = signExtend(mem_data[7:0]);
                3'b001 : data = signExtend(mem_data[15:0]);
                3'b100 : data = zeroExtend(mem_data[7:0]);
                3'b101 : data = zeroExtend(mem_data[15:0]);
                3'b010 : data = mem_data;
                endcase
            end

            if(debug) $display("[Writeback]", fshow(dInst), " ", fields.rd);
            if (!dInst.legal) begin
                if (debug) $display("[Writeback] Illegal Inst, Drop and fault: ", fshow(dInst));
                exception.enq(unpack(0));
                epoch_execute[0] <= ~epoch_execute[0];
            end
            if (dInst.valid_rd) begin
                let rd_idx = fields.rd;
                if (rd_idx != 0) begin scoreboard[rd_idx][0] <= 0; end
                rf.write(rd_idx, data);
            end
        end
	endrule

    rule waitCanonicalization if(doCanonicalize && !isCanonicalized && !f2d.notEmpty && !d2e.notEmpty && !e2w.notEmpty && !exception.notEmpty && !misprediction.notEmpty);
        isCanonicalized <= True;
        doCanonicalize <= False;
    endrule

	// ADMINISTRATION:

    rule administrative_konata_commit;
        retired.deq();
        let f = retired.first();
        commitKonata(lfh, f, commit_id);
	endrule
		
	rule administrative_konata_flush;
        squashed.deq();
        let f = squashed.first();
        squashKonata(lfh, f);
	endrule
		
    method ActionValue#(Mem) getIReq();
        toImem.deq();
        return toImem.first();
    endmethod

    method Action getIResp(Mem a);
        fromImem.enq(a);
    endmethod

    method ActionValue#(Mem) getDReq();
        toDmem.deq();
        return toDmem.first();
    endmethod

    method Action getDResp(Mem a);
        fromDmem.enq(a);
    endmethod

    method ActionValue#(Mem) getMMIOReq();
        toMMIO.deq();
        return toMMIO.first();
    endmethod

    method Action getMMIOResp(Mem a);
        fromMMIO.enq(a);
    endmethod

    // INSTRUMENTATION

    method Action halt if(!doHalt);
        doHalt <= True;
    endmethod

    method Action halted if(doHalt);
    endmethod

    method Action canonicalize if(!doCanonicalize && !isCanonicalized);
        doCanonicalize <= True;
        isCanonicalized <= False;
    endmethod

    method Action canonicalized if(isCanonicalized);
    endmethod    

    method Action restart if((doHalt && !doCanonicalize) || isCanonicalized);
        doHalt <= False;
        isCanonicalized <= False;
    endmethod

    method Action restarted if(!doHalt && !doCanonicalize && !isCanonicalized);
    endmethod    

    method Action request(Bit#(1) operation, ComponentId id, ExchangeAddress addr, ExchangeData data) if((doHalt && !doCanonicalize) || isCanonicalized);
        let address = addr[4:0];
        let writeData = data[31:0];
        if(operation == 0) begin
            case(address)
                5'b00000: begin
                    responseFIFO.enq(pc);
                    // $display("Pipeline [Request] PC");
                end
                default: begin 
                    let x <- rf.dbg_read(address);
                    responseFIFO.enq(x);
                end
            endcase
        end else begin
            case(address)
                5'b00000: pc <= writeData;
                default: rf.dbg_write(address, writeData);
            endcase
            responseFIFO.enq(writeData);
        end

        // $display("Pipeline [Request] ", operation, " ", id, " ", addr, " ", data);
    endmethod

    method ActionValue#(ExchangeData) response(ComponentId id) if((doHalt && !doCanonicalize) || isCanonicalized);
        let out = 0;
        if(responseFIFO.notEmpty()) begin
            out = responseFIFO.first();
            responseFIFO.deq();
        end
        // $display("Pipeline [Response] ", id, " ", out);
        return zeroExtend(out);
    endmethod

endmodule
