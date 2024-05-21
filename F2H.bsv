/*
bits to represent all the components: 
type -> component_bits (log2 of nr components)
name -> id

bits to represent the indexable information:
type -> address_bits (log2 of max(addresses)) 
name -> address

0 processor
    0: rf + pc
1-4
    1 -> 0: L1i
    2 -> 1: L1d
    3 -> 2: L2
    4 -> 3: MainMem

*/

import FIFO::*;
import FIFOF::*;
import SpecialFIFOs::*;

import Core::*;
import SnapshotTypes::*;

interface CoreIndication;
    method Action halted;
    method Action restarted;
    method Action canonicalized;
    method Action response(ExchangeData data);
    method Action requestMMIO(Bit#(33) data);
endinterface

interface CoreRequest;
    method Action halt;
    method Action canonicalize;
    method Action restart;
    method Action request(SnapshotRequestType operation, ComponentdId id, ExchageAddress addr, ExchangeData data);
endinterface

interface Glue;
   interface CoreRequest request;
endinterface

(* synthesize *)
module mkF2H#(CoreIndication indication)(Glue);

    FIFOF#(ComponentdId) inFlight <- mkBypassFIFOF;

    Reg#(Bool) doHalt <- mkReg(False);
    Reg#(Bool) doCanonicalize <- mkReg(False);
    Reg#(Bool) doRestart <- mkReg(False);

    CoreInterface core <- mkCore;

    // INDICATION

    rule waitMMIO;
        let mmio <- core.getMMIO();
        indication.requestMMIO(mmio);
    endrule

    rule waitResponse;
        let component = inFlight.first(); inFlight.deq();
        let data <- core.response(component);
        indication.response(data);
    endrule 
    
    rule halted if(doHalt);
        core.halted();
        indication.halted();
        doHalt <= False;
    endrule

    rule canonicalized if(doCanonicalize);
        core.canonicalized();
        indication.canonicalized();
        doCanonicalize <= False;
    endrule

    rule restarted if(doRestart);
        core.restarted();
        indication.restarted();
        doRestart <= False;
    endrule

    // REQUEST

    interface CoreRequest request;

        method Action restart;
            core.restart();
            doRestart <= True;
        endmethod
        
        method Action canonicalize;
            core.canonicalize();
            doCanonicalize <= True;
        endmethod
        
        method Action halt;
            core.halt();
            doHalt <= True;
        endmethod

        method Action request(SnapshotRequestType operation, ComponentdId id, ExchageAddress addr, ExchangeData data);
            inFlight.enq(id);
            core.request(operation, id, addr, data);
        endmethod

    endinterface

endmodule