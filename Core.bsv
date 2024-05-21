// PIPELINED SINGLE CORE PROCESSOR WITH 2 LEVEL CACHE
import RVUtil::*;
import BRAM::*;
import Pipelined::*;
import FIFO::*;
import MemTypes::*;
import CacheInterface::*;
import SnapshotTypes::*;

interface CoreInterface;
    method Action halt;
    method Action canonicalize;
    method Action restart;
    method Action halted;
    method Action restarted;
    method Action canonicalized;
    method Action request(SnapshotRequestType operation, ComponentdId id, ExchageAddress addr, ExchangeData data);
    method ActionValue#(ExchangeData) response(ComponentdId id);
endinterface

(* synthesize *)
module mkCore(CoreInterface);

    CacheInterface cache <- mkCacheInterface();
    RVIfc rv_core <- mkPipelined();

    FIFO#(Mem) ireq <- mkFIFO;
    FIFO#(Mem) dreq <- mkFIFO;
    FIFO#(Mem) mmioreq <- mkFIFO;
    let debug = True;
    Reg#(Bit#(32)) cycle_count <- mkReg(0);

    rule tic;
	    cycle_count <= cycle_count + 1;
    endrule

    rule requestI;
        let req <- rv_core.getIReq;
        if (debug) $display("Get IReq", fshow(req));
        ireq.enq(req);
        cache.sendReqInstr(CacheReq{word_byte: req.byte_en, addr: req.addr, data: req.data});
    endrule

    rule responseI;
        let x <- cache.getRespInstr();
        let req = ireq.first();
        ireq.deq();
        if (debug) $display("Get IResp ", fshow(req), fshow(x));
        req.data = x;
        rv_core.getIResp(req);
    endrule

    rule requestD;
        let req <- rv_core.getDReq;
        dreq.enq(req);
        if (debug) $display("Get DReq", fshow(req));
        cache.sendReqData(CacheReq{word_byte: req.byte_en, addr: req.addr, data: req.data});
    endrule

    rule responseD;
        let x <- cache.getRespData();
        let req = dreq.first();
        dreq.deq();
        if (debug) $display("Get DResp ", fshow(req), fshow(x));
        req.data = x;
        rv_core.getDResp(req);
    endrule
  
    rule requestMMIO;
        let req <- rv_core.getMMIOReq;
        if (debug) $display("Get MMIOReq", fshow(req));
        if (req.byte_en == 'hf) begin
            if (req.addr == 'hf000_fff4) begin
                // Write integer to STDERR
                $fwrite(stderr, "%0d", req.data);
                $fflush(stderr);
            end
        end
        if (req.addr ==  'hf000_fff0) begin
            // Writing to STDERR
            $fwrite(stderr, "%c", req.data[7:0]);
            $fflush(stderr);
        end else begin
            if (req.addr == 'hf000_fff8) begin
                $display("RAN CYCLES", cycle_count);
                // Exiting Simulation
                if (req.data == 0) begin
                    $fdisplay(stderr, "  [0;32mPASS[0m");
                end else begin
                    $fdisplay(stderr, "  [0;31mFAIL[0m (%0d)", req.data);
                end
                $fflush(stderr);
                $finish;
            end
        end
        mmioreq.enq(req);
    endrule

    rule responseMMIO;
        let req = mmioreq.first();
        mmioreq.deq();
        if (debug) $display("Put MMIOResp", fshow(req));
        rv_core.getMMIOResp(req);
    endrule

    // INSTRUMENTATION

    Reg#(Bool) doCanonicalize <- mkReg(False);

    rule canonicalization if(doCanonicalize);
        rv_core.canonicalized();
        cache.canonicalize();
        doCanonicalize <= False;
    endrule

    method Action restart;
        rv_core.restart();
        cache.restart();
    endmethod
    
    method Action canonicalize if(!doCanonicalize);
        rv_core.canonicalize();
        doCanonicalize <= True;
    endmethod
    
    method Action halt;
        rv_core.halt();
        cache.halt();
    endmethod

    method Action halted;
        rv_core.halted();
        cache.halted();
    endmethod

    method Action canonicalized;
        cache.canonicalized();
    endmethod

    method Action restarted;
        rv_core.restarted();
        cache.restarted();
    endmethod

    method Action request(SnapshotRequestType operation, ComponentdId id, ExchageAddress addr, ExchangeData data);
        case(id)
            0: rv_core.request(operation, 0, addr, data);   // pipeline
            1: cache.request(operation, 0, addr, data);     // l1i
            2: cache.request(operation, 1, addr, data);     // l1d
            3: cache.request(operation, 2, addr, data);     // l2
            4: cache.request(operation, 3, addr, data);     // DRAM
        endcase
    endmethod

    method ActionValue#(ExchangeData) response(ComponentdId id);
        let data <- case(id)
            0: rv_core.response(0);         // pipeline
            1: cache.response(0);           // l1i
            2: cache.response(1);           // l1d
            3: cache.response(2);           // l2
            4: cache.response(3);           // DRAM
        endcase;
        return data;
    endmethod 
    
endmodule
