// SINGLE CORE CACHE INTERFACE WITH NO PPP
import Assert::*;
import MainMem::*;
import MemTypes::*;
import Cache32::*;
import Cache32d::*;
import Cache512::*;
import Vector::*;
import FIFOF::*;
import SpecialFIFOs::*;

import SnapshotTypes::*;

interface CacheInterface;
    method Action sendReqData(CacheReq req);
    method ActionValue#(Word) getRespData();
    method Action sendReqInstr(CacheReq req);
    method ActionValue#(Word) getRespInstr();

    // INSTRUMENTATION 
    method Action halt;
    method Action restart;
    method Action halted;
    method Action restarted;

    method Action request(Bit#(1) operation, ComponentId id, ExchangeAddress addr, ExchangeData data);
    method ActionValue#(ExchangeData) response(ComponentId id);

endinterface

typedef enum {
    INSTR,
    DATA
} CacheInterfaceRR deriving (Eq, FShow, Bits);

(* synthesize *)
module mkCacheInterface(CacheInterface);
    let verbose = False;
    MainMem mainMem <- mkMainMem(); 
    Cache512 cacheL2 <- mkCache512;
    Cache32 cacheI <- mkCache32;
    Cache32d cacheD <- mkCache32d;

    FIFOF#(MainMemReq) iToL2 <- mkBypassFIFOF;
    FIFOF#(MainMemReq) dToL2 <- mkBypassFIFOF;
    Reg#(CacheInterfaceRR) toL2RoundRobin <- mkReg(INSTR);

    Reg#(Bool) outstandingMiss <- mkReg(False);

    Reg#(Bool) doHalt <- mkReg(False);

    rule getFromMem if (!doHalt);
        let resp <- mainMem.get();
        if (verbose) $display("CacheInterface: Getting from Mem");
        cacheL2.putFromMem(resp);
    endrule
    
    rule sendToMem if (!doHalt);
        let req <- cacheL2.getToMem();
        if (verbose) $display("CacheInterface: Sending to Mem");
        mainMem.put(req);
    endrule
    
    rule getFromL2 if (outstandingMiss == True && !doHalt);
        let resp <- cacheL2.getToProc();
        if (verbose) $display("CacheInterface: Getting from L2");
        if (toL2RoundRobin == INSTR) begin
            cacheD.putFromMem(resp);
        end else begin
            cacheI.putFromMem(resp);
        end
        outstandingMiss <= False;
    endrule
    
    rule sendToL2 if (outstandingMiss == False && !doHalt);
        let req;
        if (toL2RoundRobin == INSTR && iToL2.notEmpty) begin
            req = iToL2.first;
            iToL2.deq;
            if (verbose) $display("CacheInterface: Sending from L1i to L2");
            cacheL2.putFromProc(req);
            toL2RoundRobin <= DATA;
            outstandingMiss <= True;
        end else if (toL2RoundRobin == DATA && dToL2.notEmpty) begin
            req = dToL2.first;
            dToL2.deq;
            if (verbose) $display("CacheInterface: Sending from L1d to L2");
            cacheL2.putFromProc(req);
            toL2RoundRobin <= INSTR;
            outstandingMiss <= True;
        end else if (toL2RoundRobin == INSTR && dToL2.notEmpty) begin
            req = dToL2.first;
            dToL2.deq;
            if (verbose) $display("CacheInterface: Sending from L1d to L2");
            cacheL2.putFromProc(req);
            toL2RoundRobin <= INSTR;
            outstandingMiss <= True;
        end else if (toL2RoundRobin == DATA && iToL2.notEmpty) begin
            req = iToL2.first;
            iToL2.deq;
            if (verbose) $display("CacheInterface: Sending from L1i to L2");
            cacheL2.putFromProc(req);
            toL2RoundRobin <= DATA;
            outstandingMiss <= True;
        end
    endrule 

    rule toL2Data if (!doHalt);
        let req <- cacheD.getToMem();
        dToL2.enq(req);
    endrule

    rule toL2Instr if (!doHalt);
        let req <- cacheI.getToMem();
        iToL2.enq(req);
    endrule

    method Action halt if (!doHalt);
        doHalt <= True;
        // I also need to halt all submodules
        cacheL2.halt;
        cacheI.halt;
        cacheD.halt;
        mainMem.halt;
    endmethod


    method Action restart if (doHalt);
        doHalt <= False;
        // I also need to restart all submodules
        cacheL2.restart;
        cacheI.restart;
        cacheD.restart;
        mainMem.restart;

    endmethod

    method Action halted if (doHalt);
        cacheL2.halted;
        cacheI.halted;
        cacheD.halted;
        mainMem.halted;
    endmethod

    method Action restarted if (!doHalt);
        cacheL2.restarted;
        cacheI.restarted;
        cacheD.restarted;
        mainMem.restarted;
    endmethod


    method Action request(Bit#(1) operation, ComponentId id, ExchangeAddress addr, ExchangeData data) if (doHalt);
        case (id)
            0: cacheI.request(operation, id, addr, data);
            1: cacheD.request(operation, id, addr, data);
            2: cacheL2.request(operation, id, addr, data);
            3: mainMem.request(operation, id, addr, data);
            default: dynamicAssert(False, "CacheInterface.request: Invalid component ID");
        endcase
    endmethod

    method ActionValue#(ExchangeData) response(ComponentId id);
        case (id)
            0: begin
                let data <- cacheI.response(id);
                return data;
            end
            1: begin
                let data <- cacheD.response(id);
                return data;
            end
            2: begin 
                let data <- cacheL2.response(id);
                return data;
            end
            3: begin 
                let data <- mainMem.response(id);
                return data;
            end
            default: begin 
                dynamicAssert(False, "CacheInterface.response: Invalid component ID");
                return signExtend(1'b1);
            end
        endcase
    endmethod

    method Action sendReqData(CacheReq req) if (!doHalt);
        cacheD.putFromProc(req);
    endmethod

    method ActionValue#(Word) getRespData() if(!doHalt);
        let resp <- cacheD.getToProc();
        return resp;
    endmethod


    method Action sendReqInstr(CacheReq req) if (!doHalt);
        cacheI.putFromProc(req);
    endmethod

    method ActionValue#(Word) getRespInstr() if(!doHalt);
        let resp <- cacheI.getToProc();
        return resp;
    endmethod
endmodule
