import BRAM::*;
import FIFO::*;
import FIFOF::*;
import SpecialFIFOs::*;
import MemTypes::*;
import Ehr::*;
import Vector :: * ;

interface Cache512;
    method Action putFromProc(MainMemReq e);
    method ActionValue#(MainMemResp) getToProc();
    method ActionValue#(MainMemReq) getToMem();
    method Action putFromMem(MainMemResp e);
endinterface

(* synthesize *)
module mkCache(Cache512);
    BRAM_Configure cfg = defaultValue;
    cfg.loadFormat = tagged Binary "zero512.vmh";  // zero out for you

    BRAM1Port#(Bit#(8), Bit#(512)) cacheData <- mkBRAM1Server(cfg);

    Vector#(256, Reg#(LineTag512)) cacheTags <- replicateM(mkReg(unpack(0)));
    Vector#(256, Reg#(LineState)) cacheStates <- replicateM(mkReg(Invalid));

    Reg#(ParsedAddress512) reqToAnswer <- mkRegU;

    FIFO#(MainMemResp) hitQ <- mkBypassFIFO;
    Reg#(MainMemReq) missReq <- mkRegU;
    Ehr#(2, ReqStatus) mshr <- mkEhr(Ready);

    FIFO#(MainMemReq) memReqQ <- mkFIFO;
    FIFO#(MainMemResp)  memRespQ <- mkFIFO;

    rule startMiss(mshr[1] == StartMiss);
        if(cacheStates[reqToAnswer.index] == Dirty) begin
            cacheData.portA.request.put(BRAMRequest{write : False, responseOnWrite : False, address : reqToAnswer.index, datain : ?});
            mshr[1] <= ReadingCacheMiss; 
        end else begin
            mshr[1] <= SendFillReq;  
        end                         
    endrule

    rule sendFillReq (mshr[1] == SendFillReq);
        if(missReq.write == 0) begin
            memReqQ.enq(MainMemReq{write : 0, addr : {reqToAnswer.tag, reqToAnswer.index}, data : ?});
            mshr[1] <= WaitFillResp;
        end else begin
            cacheData.portA.request.put(BRAMRequest{write : True, responseOnWrite : False, address : reqToAnswer.index, datain : missReq.data});
            cacheStates[reqToAnswer.index] <= Dirty;
            cacheTags[reqToAnswer.index] <= reqToAnswer.tag;
            mshr[1] <= Ready;
        end
    endrule

    rule waitFillResp(mshr[1] == WaitFillResp);
        let line = memRespQ.first(); memRespQ.deq(); 
        cacheTags[reqToAnswer.index] <= reqToAnswer.tag;
        cacheStates[reqToAnswer.index] <= Clean;
        cacheData.portA.request.put(BRAMRequest{write : True, responseOnWrite : False, address : reqToAnswer.index, datain : line});
        hitQ.enq(line);
        mshr[1] <= Ready;
    endrule

    rule processLoadRequest if (mshr[0] == ReadingCacheHit);
        let line <- cacheData.portA.response.get();
        hitQ.enq(line);
        mshr[0] <= Ready;
    endrule

    rule processStoreRequest if (mshr[0] == ReadingCacheMiss);
        let line <- cacheData.portA.response.get();
        memReqQ.enq(MainMemReq{write : 1, addr : {cacheTags[reqToAnswer.index], reqToAnswer.index}, data : line});
        mshr[0] <= SendFillReq;
    endrule

    method Action putFromProc(MainMemReq e) if(mshr[1] == Ready);
        ParsedAddress512 pa = parseAddress512(e.addr);
        reqToAnswer <= pa;
        if (cacheTags[pa.index] == pa.tag && cacheStates[pa.index] != Invalid) begin
            if(e.write == 0) begin
                cacheData.portA.request.put(BRAMRequest{write : False, responseOnWrite : False, address : pa.index, datain : ?});
                mshr[1] <= ReadingCacheHit;
            end else begin 
                cacheData.portA.request.put(BRAMRequest{write : True, responseOnWrite : False, address : pa.index, datain : e.data}); 
                cacheStates[pa.index] <= Dirty;
            end
        end else begin missReq <= e; mshr[1] <= StartMiss; end
    endmethod

    method ActionValue#(MainMemResp) getToProc();
        let x = hitQ.first(); hitQ.deq();
        return x;
    endmethod

    method ActionValue#(MainMemReq) getToMem();
        let x = memReqQ.first(); memReqQ.deq();
        return x;
    endmethod

    method Action putFromMem(MainMemResp e);
        memRespQ.enq(e);
    endmethod

endmodule
