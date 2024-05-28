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
import Vector::*;

import Core::*;
import SnapshotTypes::*;

interface CoreIndication;
    method Action halted;
    method Action restarted;
    method Action canonicalized;
    method Action response(Vector#(16,Bit#(32)) data);
    method Action requestMMIO(Bit#(33) data);
    method Action requestHalt;
    method Action requestOutUART(Bit#(8) data);
    method Action requestInUART;
    method Action requestAvUART;
endinterface

interface CoreRequest;
    method Action halt;
    method Action canonicalize;
    method Action restart;
    method Action request(Bit#(1) operation, Bit#(3) id, Bit#(32) addr, Vector#(16,Bit#(32)) data);
    method Action responseInUART(Bit#(8) data);
    method Action responseAvUART(Bit#(8) available);
endinterface

interface F2H;
   interface CoreRequest request;
endinterface

module mkF2H#(CoreIndication indication)(F2H);

    FIFOF#(ComponentId) inFlight <- mkBypassFIFOF;

    Reg#(Bool) isHalt <- mkReg(False);
    Reg#(Bool) doCanonicalize <- mkReg(False);
    Reg#(Bool) doRestart <- mkReg(False);

    CoreInterface core <- mkCore;

    // INDICATION

    rule waitMMIO;
        let mmio <- core.getMMIO();
        indication.requestMMIO(mmio);
    endrule

    rule waitOutUART;
        let uart <- core.uart2hostOutGET();
        indication.requestOutUART(uart);
    endrule

    rule waitAvUART;
        let uart <- core.uart2hostAvGET();
        indication.requestAvUART();
    endrule

    rule waitInUART;
        let uart <- core.uart2hostInGET();
        indication.requestInUART();
    endrule

    rule waitHaltRequest;
        core.getHalt();
        indication.requestHalt();
    endrule

    rule waitResponse;
        let component = inFlight.first(); 
        inFlight.deq();
        let data <- core.response(component);
        indication.response(unpack(data));
    endrule 
    
    rule halted if(isHalt);
        core.halted();
        indication.halted();
        isHalt <= False;
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
            isHalt <= True;
        endmethod

        method Action request(Bit#(1) operation, Bit#(3) id, Bit#(32) addr, Vector#(16,Bit#(32)) data);
            inFlight.enq(id);
            core.request(operation, id, addr, pack(data));
        endmethod

        method Action responseInUART(Bit#(8) data);
            core.host2uartInPUT(data);
        endmethod 

        method Action responseAvUART(Bit#(8) available); 
            core.host2uartAvPUT(available);
        endmethod
        
    endinterface

endmodule