import RVUtil::*;
import BRAM::*;
import FIFO::*;
import FIFOF::*;
import SpecialFIFOs::*;
import DelayLine::*;
import MemTypes::*;

import SnapshotTypes::*;

interface MainMem;
    method Action put(MainMemReq req);
    method ActionValue#(MainMemResp) get();

    // INSTRUMENTATION 
    method Action halt;
    method Action restart;
    method Action halted;
    method Action restarted;

    method Action request(Bit#(1) operation, ComponentId id, ExchangeAddress addr, ExchangeData data);
    method ActionValue#(ExchangeData) response(ComponentId id);
endinterface

interface MainMemFast;
    method Action put(CacheReq req);
    method ActionValue#(Word) get();
endinterface

(* synthesize *)
module mkMainMemFast(MainMemFast);
    BRAM_Configure cfg = defaultValue();
    cfg.loadFormat = tagged Hex "mem.vmh";
    BRAM1PortBE#(Bit#(30), Word, 4) bram <- mkBRAM1ServerBE(cfg);
    DelayLine#(10, Word) dl <- mkDL(); // Delay by 20 cycles

    rule deq;
        let r <- bram.portA.response.get();
        dl.put(r);
    endrule    

    method Action put(CacheReq req);
        bram.portA.request.put(BRAMRequestBE{
                    writeen: req.word_byte,
                    responseOnWrite: False,
                    address: req.addr[31:2],
                    datain: req.data});
    endmethod

    method ActionValue#(Word) get();
        let r <- dl.get();
        return r;
    endmethod
endmodule

(* synthesize *)
module mkMainMem(MainMem);
    BRAM_Configure cfg = defaultValue();
    cfg.loadFormat = tagged Hex "memlines.vmh";
    BRAM1Port#(Bit#(20), MainMemResp) bram <- mkBRAM1Server(cfg); // 20-bit address, 1MB entry, 64-bit data

    DelayLine#(20, MainMemResp) dl <- mkDL(); // Delay by 20 cycles

    // INSTRUMENTATION
    Reg#(Bool) doHalt <- mkReg(True);

    FIFOF#(Bool) responseFIFO <- mkBypassFIFOF;

    rule deq if(!doHalt);
        let r <- bram.portA.response.get();
        dl.put(r);
    endrule    

    // rule waitResponse if(doHalt);
    //     let r <- bram.portA.response.get();
    //     responseFIFO.enq(r);
    // endrule 

    method Action put(MainMemReq req) if (!doHalt);
        bram.portA.request.put(BRAMRequest{
                    write: unpack(req.write),
                    responseOnWrite: True,
                    address: req.addr[19:0],
                    datain: req.data});
    endmethod

    method ActionValue#(MainMemResp) get() if (!doHalt);
        let r <- dl.get();
        return r;
    endmethod

    // INSTRUMENTATION 

    method Action halt if(!doHalt);
        doHalt <= True;
    endmethod

    method Action halted if(doHalt);
    endmethod

    method Action restart if(doHalt);
        doHalt <= False;
    endmethod

    method Action restarted if(!doHalt);
    endmethod      

    method Action request(Bit#(1) operation, ComponentId id, ExchangeAddress addr, ExchangeData data) if(doHalt);
        // $display("MainMem: Requesting display%d %d %d %d", operation, id, addr, data);
        // let address = addr[valueOf(LineAddrLength)-1:0];
        let address = addr[19:0];
        if(operation == 0) begin
            bram.portA.request.put(BRAMRequest{write: unpack(0), responseOnWrite: True, address: address, datain: data});
        end else begin
            bram.portA.request.put(BRAMRequest{write: unpack(1), responseOnWrite: True, address: address, datain: data});
        end
        responseFIFO.enq(?);
    endmethod

    method ActionValue#(ExchangeData) response(ComponentId id) if(doHalt);
        ExchangeData out = signExtend(1'b1);
        if(responseFIFO.notEmpty()) begin
            responseFIFO.deq();
            out <- bram.portA.response.get();
        end
        // $display("MainMemory: Response", out);
        return zeroExtend(out);
    endmethod
    
endmodule

