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

interface coreIndication;
    method Action halted;
    method Action restarted;
    method Action canonicalized;
    method Action response(ExchangeData data);
endinterface

interface coreRequest;
    method Action halt;
    method Action canonicalize;
    method Action restart;
    method Action request(SnapshotRequestType operation, ComponentdId id, ExchageAddress addr, ExchangeData data);
endinterface

interface glue;
   interface coreRequest request;
endinterface

/* interface F2GIfc;
    // INSTRUMENTATION 
    method Action halt;
    method Action canonicalize;
    method Action restart;
    method Action halted;
    method Action restarted;
    method Action canonicalized;

    method Action request(SnapshotRequestType operation, ComponentdId id, ExchageAddress addr, ExchangeData data);
    method ActionValue#(ExchangeData) response;
endinterface */

(* synthesize *)
module mkInterface(coreIndication indication) (glue);

    FIFOF#(NrComponents) inFlight <- mkBypassFIFO;

    Reg#(Bool) doHalt <- mkReg(False);
    Reg#(Bool) doCanonicalize <- mkReg(False);
    Reg#(Bool) doRestart <- mkReg(False);

    Core core <- mkCore;

    // INDICATION

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
        indication.canonicalize();
        doCanonicalize <= False;
    endrule

    rule restarted if(doRestart);
        core.restarted();
        indication.restarted();
        doRestart <= False;
    endrule

    // REQUEST

    interface coreRequest request;

        method Action restart if(!inFlight.notEmpty);
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