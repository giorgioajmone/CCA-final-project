// SINGLE CORE ASSOIATED CACHE -- stores words

import BRAM::*;
import FIFO::*;
import FIFOF::*;
import SpecialFIFOs::*;
import MemTypes::*;
import Ehr::*;
import Vector :: * ;

// TODO: copy over from 3_a

interface Cache32;
    method Action putFromProc(CacheReq e);
    method ActionValue#(Word) getToProc();
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
module mkCache32(Cache32);
    BRAM_Configure cfg = defaultValue;
    cfg.loadFormat = tagged Binary "zero.vmh";

    BRAM1PortBE#(Bit#(7), LineData, 64) cacheData <- mkBRAM1ServerBE(cfg);

    Vector#(128, Reg#(LineTag)) cacheTags <- replicateM(mkReg(unpack(0)));
    Vector#(128, Reg#(LineState)) cacheStates <- replicateM(mkReg(Invalid));

    Reg#(ParsedAddress) reqToAnswer <- mkRegU;

    FIFO#(Word) hitQ <- mkBypassFIFO;
    Reg#(CacheReq) missReq <- mkRegU;
    Ehr#(2, ReqStatus) mshr <- mkEhr(Ready);

    FIFO#(MainMemReq) memReqQ <- mkFIFO;
    FIFO#(MainMemResp)  memRespQ <- mkFIFO;

    // INSTRUMENTATION

    Reg#(Bool) doHalt <- mkReg(True);
    FIFO#(Bit#(64)) responseFIFO <- mkBypassFIFO;
    FIFO#(Bit#(3)) sliceFIFO <- mkBypassFIFO;

    rule startMiss if(mshr[1] == StartMiss && !doHalt);
        if(cacheStates[reqToAnswer.index] == Dirty) begin
            cacheData.portA.request.put(BRAMRequestBE{writeen : 0, responseOnWrite : False, address : reqToAnswer.index, datain : ?});
            mshr[1] <= ReadingCacheMiss; 
        end else begin
            mshr[1] <= SendFillReq;  
        end                         
    endrule

    rule sendFillReq if(mshr[1] == SendFillReq && !doHalt);
        memReqQ.enq(MainMemReq{write : 0, addr : {reqToAnswer.tag, reqToAnswer.index}, data : ?});
        mshr[1] <= WaitFillResp;
    endrule

    rule waitFillResp if(mshr[1] == WaitFillResp && !doHalt);
        LineData line = unpack(memRespQ.first());
        cacheTags[reqToAnswer.index] <= reqToAnswer.tag;
        if (missReq.word_byte == 0) begin
            cacheStates[reqToAnswer.index] <= Clean;
            hitQ.enq(line[reqToAnswer.offset]);
        end else begin
            cacheStates[reqToAnswer.index] <= Dirty;
            line[reqToAnswer.offset] = updateWord(line[reqToAnswer.offset], missReq.data, missReq.word_byte);
        end
        memRespQ.deq(); 
        mshr[1] <= Ready;
        cacheData.portA.request.put(BRAMRequestBE{writeen : 64'hFFFFFFFFFFFFFFFF, responseOnWrite : False, address : reqToAnswer.index, datain : line});
    endrule

    rule processLoadRequest if(mshr[0] == ReadingCacheHit && !doHalt);
        let line <- cacheData.portA.response.get();
        hitQ.enq(line[reqToAnswer.offset]);
        mshr[0] <= Ready;
    endrule

    rule processStoreRequest if(mshr[0] == ReadingCacheMiss && !doHalt);
        let line <- cacheData.portA.response.get();
        memReqQ.enq(MainMemReq{write : 1, addr : {cacheTags[reqToAnswer.index], reqToAnswer.index}, data : pack(line)});
        mshr[0] <= SendFillReq;
    endrule

    method Action putFromProc(CacheReq e) if(mshr[1] == Ready && !doHalt);
        ParsedAddress pa = parseAddress(e.addr);
        reqToAnswer <= pa;
        if (cacheTags[pa.index] == pa.tag && cacheStates[pa.index] != Invalid) begin
            if(e.word_byte == 0) begin
                cacheData.portA.request.put(BRAMRequestBE{writeen : 0, responseOnWrite : False, address : pa.index, datain : ?});
                mshr[1] <= ReadingCacheHit;
            end else begin 
                cacheData.portA.request.put(BRAMRequestBE{writeen : writeWordOffset(pa, e.word_byte), responseOnWrite : False, address : pa.index, datain : inlineWord(pa, e.data)}); 
                cacheStates[pa.index] <= Dirty;
            end
        end else begin missReq <= e; mshr[1] <= StartMiss; end
    endmethod
        
    method ActionValue#(Word) getToProc() if(!doHalt);
        let x = hitQ.first(); hitQ.deq();
        return x;
    endmethod
        
    method ActionValue#(MainMemReq) getToMem() if(!doHalt);
        let x = memReqQ.first(); memReqQ.deq();
        return x;
    endmethod
        
    method Action putFromMem(MainMemResp e) if((!doHalt));
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
        let field = addr[8:7];
        let address = addr[6:0];
        let slice = addr[11:9];
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
                    cacheTags[address] <= data[valueOf(LineTag)-1:0];
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
