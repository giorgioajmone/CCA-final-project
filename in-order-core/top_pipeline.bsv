// PIPELINED SINGLE CORE PROCESSOR WITH 2 LEVEL CACHE
import RVUtil::*;
import BRAM::*;
import pipelined::*;
import FIFO::*;
import MemTypes::*;
import CacheInterface::*;

interface CacheInterface#(numeric type cache_idx, numeric type addr_bits, numeric type resp_bits);
    // INSTRUMENTATION 
    method Action halt;
    method Action canonicalize;
    method Action restart;
    method ActionValue#(void) halted;
    method ActionValue#(void) restarted;
    method ActionValue#(void) canonicalized;

    method Action request(Bit#(nrComponents) id, Bit#(Set+way+info) addr);
    method ActionValue#(Bit#(512)) response(Bit#(nrComponents) id);
endinterface


module mkCore(Empty);

    CacheInterface(3, 512) cache <- mkCacheInterface();
    RVIfc#(5, 32) rv_core <- mkpipelined;

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
        end else
            if (req.addr == 'hf000_fff8) begin
                $display("RAN CYCLES", cycle_count);

            // Exiting Simulation
                if (req.data == 0) begin
                        $fdisplay(stderr, "  [0;32mPASS[0m");
                end
                else
                    begin
                        $fdisplay(stderr, "  [0;31mFAIL[0m (%0d)", req.data);
                    end
                $fflush(stderr);
                $finish;
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

    method Action restart if(!inFlightRequest.notEmpty);
        core.restart();
        cache.restart();
    endmethod
    
    method Action canonicalize;
        core.canonicalize();
        cache.canonicalize();
    endmethod
    
    method Action halt;
        core.halt();
        cache.halt();
    endmethod

    method ActionValue#(void) halted;
        core.halted();
        cache.halted();
    endmethod

    method ActionValue#(void) canonicalized;
        core.canonicalized();
        cache.canonicalized();
    endmethod

    method Action request(Bit#(nrComponents) id, Bit#(Set+way+info) addr);
        case(id)
            0: core.request(0);
            1: cache.request(0);
            2: cache.request(1);
            3: cache.request(2);
        endcase
    endmethod

    method ActionValue#(Bit#(512)) response(Bit#(nrComponents) id);
        let data <- case(id)
            0: core.response(0);
            1: cache.response(0);
            2: cache.response(1);
            3: cache.response(2);
        endcase
        return data;
    endmethod 
    
endmodule
