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
import SpecialFIFOs::*;

interface F2GIfc;
    method Action halt;
    method Action canonicalize;
    method Action restart;
    method Action request(Bit#(nrComponents) id, Bit#(Log2MaxSize) addr);

    method ActionValue#(void) ready;
    method ActionValue#(Bit#(512)) response(Bit#(nrComponents) id);
endinterface

typedef `NUM_COMPONENTS ComponentsNum;
typedef Bit#(TLog#(ComponentsNum)) nrComponents;

(* synthesize *)
module mkInterface#(F2GIfc);

    FIFO#(nrComponents) inFlightRequest <- mkBypassFIFO;
    FIFO#(nrComponents) inFlightResponse <- mkBypassFIFO;

    Core core <- mkPipelined;
    
    method Action restart if(!inFlightRequest.notEmpty);
        core.restart();
    endmethod
    
    method Action canonicalize;
        core.canonicalize();
    endmethod
    
    method Action halt;
        core.halt();
    endmethod

    method ActionValue#(void) halted;
        core.halted();
    endmethod

    method ActionValue#(void) canonicalized;
        core.canonicalized();
    endmethod

    FIFO#(nrComponents) inFlightRequest <- mkBypassFIFO;
    FIFO#(nrComponents) inFlightResponse <- mkBypassFIFO;

    rule waitResponse;
        let component = inFlightRequest.first(); inFlightRequest.deq();
        let data <- core.response(component);
        inFlightResponse.enq(data);
    endrule 

    method Action request(Bit#(nrComponents) id, Bit#(Log2MaxSize) addr);
        inFlightRequest.enq(id);
        core.request(addr);
    endmethod

    method ActionValue#(Bit#(512)) response;
        inFlightResponse.deq();
        return inFlightResponse.first();
    endmethod 

endmodule