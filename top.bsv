/*
bits to represent all the components: 
type -> component_bits (log2 of nr components)
name -> id

bits to represent the indexable information:
type -> address_bits (log2 of max(addresses)) 
name -> address

0 processor
    0: rf + pc
1-3
    1 -> 0: L1i
    2 -> 1: L1d
    3 -> 2: L2


Requests: (from Host to Interface)
    - halt()
    - canonicalize()
    - restart()
    - request(id, addr)

Indications: (from Interface to Host)
    - halted() maybe, not necessary
    - ready()
    - response(data)


The system that is monitored needs to expose a method for each component of interest 

Requests: (from Interface to Core)
    - halt()
    - canonicalize()
    - restart()
    - request*(addr)

Indications: (from Core to Interface)
    - halted() maybe, not necessary
    - ready()
    - response*(data)

*/

import FIFO::*;
import FIFOF::*;
import SpecialFIFOs::*;

import Core::*;

interface F2GIfc;
    // INSTRUMENTATION 
    method Action halt;
    method Action canonicalize;
    method Action restart;
    method Action halted;
    method Action restarted;
    method Action canonicalized;

    method Action request(SnapshotRequestType operation, ComponentdId id, ExchageAddress addr, ExchangeData data);
    method ActionValue#(ExchangeData) response;
endinterface

(* synthesize *)
module mkInterface(F2GIfc);

    FIFOF#(NrComponents) inFlightRequest <- mkBypassFIFO;
    FIFOF#(NrComponents) inFlightResponse <- mkBypassFIFO;

    Core core <- mkCore;

    rule waitResponse;
        let component = inFlightRequest.first(); inFlightRequest.deq();
        let data <- core.response(component);
        inFlightResponse.enq(data);
    endrule 
    
    method Action restart if(!inFlightRequest.notEmpty);
        core.restart();
    endmethod
    
    method Action canonicalize;
        core.canonicalize();
    endmethod
    
    method Action halt;
        core.halt();
    endmethod

    method Action halted;
        core.halted();
    endmethod

    method Action canonicalized;
        core.canonicalized();
    endmethod

    method Action request(Bit#(1) operation, ComponentdId id, ExchageAddress addr, ExchangeData data);
        inFlightRequest.enq(id);
        core.request(operation, id, addr, data);
    endmethod

    method ActionValue#(Bit#(512)) response;
        inFlightResponse.deq();
        return inFlightResponse.first();
    endmethod 

endmodule