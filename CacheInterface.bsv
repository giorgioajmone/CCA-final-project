// SINGLE CORE CACHE INTERFACE WITH NO PPP
import MainMem::*;
import MemTypes::*;
import Cache32::*;
import Cache512::*;
import FIFOF::*;
import FIFO::*;
import SpecialFIFOs::*;


interface CacheInterface;
    method Action sendReqData(CacheReq req);
    method ActionValue#(Word) getRespData();
    method Action sendReqInstr(CacheReq req);
    method ActionValue#(Word) getRespInstr();
endinterface


module mkCacheInterface(CacheInterface);
    let verbose = True;
    MainMem mainMem <- mkMainMem(); 
    Cache512 cacheL2 <- mkCache;
    Cache32 cacheI <- mkCache32;
    Cache32 cacheD <- mkCache32;

    FIFO#(Bit#(1)) requestOrder <- mkFIFO;

    FIFOF#(MainMemReq) reqL1I <- mkBypassFIFOF;
    FIFOF#(MainMemReq) reqL1D <- mkBypassFIFOF;

    rule connectL1ItoL2;
        let iReq <- cacheI.getToMem();
        reqL1I.enq(iReq);
    endrule

    rule connectL1DtoL2;
        let dReq <- cacheD.getToMem();
        reqL1D.enq(dReq);
    endrule

    rule arbiterCache;
        if(reqL1D.notEmpty) begin
            let req = reqL1D.first(); reqL1D.deq();
            cacheL2.putFromProc(req); 
            if(req.write == 0) requestOrder.enq(1);
        end else if (reqL1I.notEmpty) begin
            let req = reqL1I.first(); reqL1I.deq();
            cacheL2.putFromProc(req); 
            if(req.write == 0) requestOrder.enq(0);
        end
    endrule

    rule connectL2toL1I(requestOrder.first() == 0);
        let iResp <- cacheL2.getToProc();
        cacheI.putFromMem(iResp); requestOrder.deq();
    endrule

    rule connectL2toL1D(requestOrder.first() == 1);
        let dResp <- cacheL2.getToProc();
        cacheD.putFromMem(dResp); requestOrder.deq();
    endrule

    rule connectL2toMEM;
        let memReq <- cacheL2.getToMem();
        mainMem.put(memReq);
    endrule

    rule connectMEMtoL2;
        let memResp <- mainMem.get();
        cacheL2.putFromMem(memResp);
    endrule

    method Action sendReqData(CacheReq req);
        cacheD.putFromProc(req);
    endmethod

    method ActionValue#(Word) getRespData();
        let resp <- cacheD.getToProc();
        return resp;
    endmethod


    method Action sendReqInstr(CacheReq req);
        cacheI.putFromProc(req);
    endmethod

    method ActionValue#(Word) getRespInstr();
        let resp <- cacheI.getToProc();
        return resp;
    endmethod
endmodule
