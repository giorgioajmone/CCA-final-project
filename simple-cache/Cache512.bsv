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

    // INSTRUMENTATION 
    method Action halt;
    method Action restart;
    method Action halted;
    method Action restarted;

    method Action request(Bit#(1) operation, ComponentId id, ExchangeAddress addr, ExchangeData data);
    method ActionValue#(ExchangeData) response(ComponentId id);
endinterface

(* synthesize *)
module mkCache(Cache512);
    BRAM_Configure cfg = defaultValue;
    cfg.loadFormat = tagged Binary "zero512.vmh";  // zero out for you

    BRAM1PortBE#(Bit#(8), Bit#(512)) cacheData <- mkBRAM1ServerBE(cfg);

    Vector#(256, Reg#(LineTag512)) cacheTags <- replicateM(mkReg(unpack(0)));
    Vector#(256, Reg#(LineState)) cacheStates <- replicateM(mkReg(Invalid));

    Reg#(ParsedAddress512) reqToAnswer <- mkRegU;

    FIFO#(MainMemResp) hitQ <- mkBypassFIFO;
    Reg#(MainMemReq) missReq <- mkRegU;
    Ehr#(2, ReqStatus) mshr <- mkEhr(Ready);

    FIFO#(MainMemReq) memReqQ <- mkFIFO;
    FIFO#(MainMemResp)  memRespQ <- mkFIFO;

    // INSTRUMENTATION

    Reg#(Bool) doHalt <- mkReg(True);
    FIFO#(Bit#(64)) responseFIFO <- mkBypassFIFO;
    FIFO#(Bit#(3)) sliceFIFO <- mkBypassFIFO;

    rule startMiss(mshr[1] == StartMiss && !doHalt);
        if(cacheStates[reqToAnswer.index] == Dirty) begin
            cacheData.portA.request.put(BRAMRequest{write : 0, responseOnWrite : False, address : reqToAnswer.index, datain : ?});
            mshr[1] <= ReadingCacheMiss; 
        end else begin
            mshr[1] <= SendFillReq;  
        end                         
    endrule

    rule sendFillReq (mshr[1] == SendFillReq && !doHalt);
        if(missReq.write == 0) begin
            memReqQ.enq(MainMemReq{write : 0, addr : {reqToAnswer.tag, reqToAnswer.index}, data : ?});
            mshr[1] <= WaitFillResp;
        end else begin
            cacheData.portA.request.put(BRAMRequest{write : 64'hFFFFFFFFFFFFFFFF, responseOnWrite : False, address : reqToAnswer.index, datain : missReq.data});
            cacheStates[reqToAnswer.index] <= Dirty;
            cacheTags[reqToAnswer.index] <= reqToAnswer.tag;
            mshr[1] <= Ready;
        end
    endrule

    rule waitFillResp(mshr[1] == WaitFillResp && !doHalt);
        let line = memRespQ.first(); memRespQ.deq(); 
        cacheTags[reqToAnswer.index] <= reqToAnswer.tag;
        cacheStates[reqToAnswer.index] <= Clean;
        cacheData.portA.request.put(BRAMRequest{write : 64'hFFFFFFFFFFFFFFFF, responseOnWrite : False, address : reqToAnswer.index, datain : line});
        hitQ.enq(line);
        mshr[1] <= Ready;
    endrule

    rule processLoadRequest if (mshr[0] == ReadingCacheHit && !doHalt);
        let line <- cacheData.portA.response.get();
        hitQ.enq(line);
        mshr[0] <= Ready;
    endrule

    rule processStoreRequest if (mshr[0] == ReadingCacheMiss && !doHalt);
        let line <- cacheData.portA.response.get();
        memReqQ.enq(MainMemReq{write : 1, addr : {cacheTags[reqToAnswer.index], reqToAnswer.index}, data : line});
        mshr[0] <= SendFillReq;
    endrule

    method Action putFromProc(MainMemReq e) if(mshr[1] == Ready && !doHalt);
        ParsedAddress512 pa = parseAddress512(e.addr);
        reqToAnswer <= pa;
        if (cacheTags[pa.index] == pa.tag && cacheStates[pa.index] != Invalid) begin
            if(e.write == 0) begin
                cacheData.portA.request.put(BRAMRequest{write : False, responseOnWrite : False, address : pa.index, datain : ?});
                mshr[1] <= ReadingCacheHit;
            end else begin 
                cacheData.portA.request.put(BRAMRequest{write : 64'hFFFFFFFFFFFFFFFF, responseOnWrite : False, address : pa.index, datain : e.data}); 
                cacheStates[pa.index] <= Dirty;
            end
        end else begin missReq <= e; mshr[1] <= StartMiss; end
    endmethod

    method ActionValue#(MainMemResp) getToProc() if(!doHalt);
        let x = hitQ.first(); hitQ.deq();
        return x;
    endmethod

    method ActionValue#(MainMemReq) getToMem() if(!doHalt);
        let x = memReqQ.first(); memReqQ.deq();
        return x;
    endmethod

    method Action putFromMem(MainMemResp e) if(!doHalt);
        memRespQ.enq(e);
    endmethod

    rule waitCacheOp if(doHalt);
        let line <- cacheData.portA.response.get(); 
        let slice <- sliceFIFO.first();
        SlicedData slices = unpack(line);
        sliceFIFO.deq();
        responseFIFO.enq(slices[slice]);
    endrule

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
        let field = addr[9:8];
        let address = addr[7:0];
        let slice = addr[12:10];
        if(operation == 0) begin
            case(field)
                2'b00: responseFIFO.enq(zeroExtend(cacheTags[address]));
                2'b01: responseFIFO.enq(zeroExtend(cacheStates[address]));
                2'b10: begin 
                    cacheData.portA.request.put(BRAMRequestBE{writeen : 0, responseOnWrite : False, address : address, datain : ?});
                    sliceFIFO.enq(slice);
                end
            endcase
        end else begin
            case(field)
                2'b00: begin 
                    cacheTags[address] <= data[valueOf(LineTag512)-1:0];
                    responseFIFO.enq(data);
                end
                2'b01: begin 
                    cacheStates[address] <= data[valueOf(LineState)-1:0];
                    responseFIFO.enq(data);
                end
                2'b10: begin
                    cacheData.portA.request.put(BRAMRequestBE{writeen : writeSliceOffset(slice), responseOnWrite : True, address : address, datain : data});
                    sliceFIFO.enq(slice);
                end
            endcase
        end
    endmethod

    method ActionValue#(ExchangeData) response(ComponentId id) if(doHalt);
        let out = responseFIFO.first();
        responseFIFO.deq();
        return zeroExtend(out);
    endmethod

endmodule
