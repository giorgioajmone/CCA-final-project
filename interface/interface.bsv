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

import FIFOF::*;
import SpecialFIFOs::*;

interface Interface;
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
module mkInterface#(nrComponents components);

    FIFOF#(nrComponents) inFlightRequest <- mkBypassFIFOF;
    FIFOF#(nrComponents) inFlightResponse <- mkBypassFIFOF;
    
    method request(Bit#(nrComponents) id, Bit#(Log2MaxSize) addr);
        //decoder to request to right component, no check on address
        inFlight.enq(id);
        
    endmethod
    
    method restart;
        //restart all the components
    endmethod
    
    method canonicalize;
        //drain all the pipelines
    endmethod
    
    method halt;
        //stop all the rules 
    endmethod

    method ActionValue#(Bit#(512)) response (inFlight.notEmpty);
        inFlight.deq;
        for(Integer i = 0; i < components; i = i + 1) begin
            if(inFlight.first matches component?)
                //call method component+inflight.first
        end
        return case(inFlight.first())

        endcase
    endmethod 

endmodule