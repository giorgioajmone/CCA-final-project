/*

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
    method ActionValue#(Bit#(512)) response;
endinterface

typedef `NUM_COMPONENTS ComponentsNum;
typedef Bit#(TLog#(ComponentsNum)) nrComponents;

(* synthesize *)
module mkInterface#(F2GIfc);

    FIFO#(nrComponents) inFlightRequest <- mkBypassFIFO;
    FIFO#(nrComponents) inFlightResponse <- mkBypassFIFO;

    Core dut <- mkPipelined;
    
    method Action restart if(!inFlightRequest.notEmpty);
        dut.restart();
    endmethod
    
    method Action canonicalize;
        dut.canonicalize();
    endmethod
    
    method Action halt;
        dut.halt();
    endmethod

    method ActionValue#(void) halted;
        dut.halted();
    endmethod

    method ActionValue#(void) canonicalized;
        dut.canonicalized();
    endmethod

    FIFO#(nrComponents) inFlightRequest <- mkBypassFIFO;
    FIFO#(nrComponents) inFlightResponse <- mkBypassFIFO;

    rule waitResponse;
        let component = inFlightRequest.first(); inFlightRequest.deq();
        let data <- dut.components[component].response();
        inFlightResponse.enq(data);
    endrule 

    method Action request(Bit#(nrComponents) id, Bit#(Log2MaxSize) addr);
        inFlightRequest.enq(id);
        dut.components[id].request(addr);
    endmethod

    method ActionValue#(Bit#(512)) response;
        inFlightResponse.deq();
        return inFlightResponse.first();
    endmethod 

endmodule