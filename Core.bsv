// PIPELINED SINGLE CORE PROCESSOR WITH 2 LEVEL CACHE
import RVUtil::*;
import BRAM::*;
import Pipelined::*;
import FIFO::*;
import MemTypes::*;
import CacheInterface::*;
import SnapshotTypes::*;

interface CoreInterface;
    method Action halt;
    method Action canonicalize;
    method Action restart;
    method Action halted;
    method Action restarted;
    method Action canonicalized;
    method Action request(Bit#(1) operation, ComponentId id, ExchangeAddress addr, ExchangeData data);
    method ActionValue#(ExchangeData) response(ComponentId id);
    method ActionValue#(Bit#(33)) getMMIO;
    method Action getHalt;

    //UART
    method ActionValue#(Bit#(8)) uart2hostOutGET;
    method ActionValue#(Bool) uart2hostAvGET;
    method ActionValue#(Bool) uart2hostInGET;
    method Action host2uartAvPUT(Bit#(8) available);
    method Action host2uartInPUT(Bit#(8) data);

endinterface

typedef enum {
    MMIOIdle,
    WaitingAvail,
    WaitingData
} MMIOState deriving (Bits, Eq, FShow);

(* synthesize *)
module mkCore(CoreInterface);

    CacheInterface cache <- mkCacheInterface();
    RVIfc rv_core <- mkPipelined();

    FIFO#(Mem) ireq <- mkFIFO;
    FIFO#(Mem) dreq <- mkFIFO;
    FIFO#(Mem) mmioreq <- mkFIFO;
    let debug = False;

    Reg#(Bool) doCanonicalize <- mkReg(False);
    FIFO#(Bit#(33)) mmio2host <- mkFIFO;
    FIFO#(Bool) haltFIFO <- mkFIFO;

    //UART
    Reg#(MMIOState) mmio_state <- mkReg(MMIOIdle);

    //Token FIFO
    FIFO#(Mem) reqAvFIFO <- mkFIFO;
    FIFO#(Mem) reqInFIFO <- mkFIFO;

    //Connectal
    FIFO#(Bit#(8)) host2uartAvFIFO <- mkFIFO;
    FIFO#(Bit#(8)) host2uartInFIFO <- mkFIFO;
    FIFO#(Bit#(8)) uart2hostOutFIFO <- mkFIFO;
    FIFO#(Bool) uart2hostInFIFO <- mkFIFO;
    FIFO#(Bool) uart2hostAvFIFO <- mkFIFO;


    rule requestI;
        let req <- rv_core.getIReq;
        if (debug) $display("Get IReq", fshow(req));
        ireq.enq(req);
        cache.sendReqInstr(CacheReq{word_byte: req.byte_en, addr: req.addr, data: req.data});
    endrule

    rule responseI;
        let x <- cache.getRespInstr();
        let req = ireq.first();
        ireq.deq();
        if (debug) $display("Get IResp ", fshow(req), fshow(x));
        req.data = x;
        rv_core.getIResp(req);
    endrule

    rule requestD;
        let req <- rv_core.getDReq;
        dreq.enq(req);
        if (debug) $display("Get DReq", fshow(req));
        cache.sendReqData(CacheReq{word_byte: req.byte_en, addr: req.addr, data: req.data});
    endrule

    rule responseD;
        let x <- cache.getRespData();
        let req = dreq.first();
        dreq.deq();
        if (debug) $display("Get DResp ", fshow(req), fshow(x));
        req.data = x;
        rv_core.getDResp(req);
    endrule
  
    rule requestMMIO if(mmio_state == MMIOIdle);
        let req <- rv_core.getMMIOReq;
        if (debug) $display("Get MMIOReq", fshow(req));
        if (req.byte_en == 'hf) begin
            if (req.addr == 'hf000_fff4) begin
                mmio2host.enq({1'b1,req.data});
            end
            mmioreq.enq(req);
        end
        if (req.addr ==  'hf000_fff0) begin
            uart2hostOutFIFO.enq(req.data[7:0]);
            mmioreq.enq(req);
        end else if (req.addr == 'hf000_fff8) begin
            Bit#(32) processed_data = (req.data << 1) | 32'b1;
            mmio2host.enq({1'b0, processed_data << 8});
            mmioreq.enq(req);
        end else if(req.addr == 'hf000_0000) begin
            if (req.byte_en == 'h0) begin
                mmio_state <= WaitingData;
                reqInFIFO.enq(req);
                uart2hostInFIFO.enq(?);
            end else begin
                uart2hostOutFIFO.enq(req.data[7:0]);
                mmioreq.enq(req);
            end
        end else if(req.addr == 'hf000_0005) begin
            uart2hostAvFIFO.enq(?);
            reqAvFIFO.enq(req);
            mmio_state <= WaitingAvail;
        end else if(req.addr == 'hf000_fffc && req.byte_en != 0) begin
            haltFIFO.enq(?);
            mmioreq.enq(req);
        end
    endrule

    rule uartAvailRespMMIO if (mmio_state == WaitingAvail);
        let req = reqAvFIFO.first();
        reqAvFIFO.deq();
        let avail = host2uartAvFIFO.first();
        host2uartAvFIFO.deq();

        let newReq = Mem {addr: req.addr, data: zeroExtend(avail), byte_en: req.byte_en};

        if (debug) $display("Avail Response: ", fshow(newReq));
        mmioreq.enq(newReq);
        mmio_state <= MMIOIdle;
    endrule

    rule uartDataRespMMIO if (mmio_state == WaitingData);
        let req = reqInFIFO.first();
        reqInFIFO.deq();
        let data = host2uartInFIFO.first();
        host2uartInFIFO.deq();

        let newReq = Mem {addr: req.addr, data: zeroExtend(data), byte_en: req.byte_en };

        if (debug) $display("Data Response: ", fshow(newReq));
        mmioreq.enq(newReq);
        mmio_state <= MMIOIdle;
    endrule

    rule responseMMIO;
        let req = mmioreq.first();
        mmioreq.deq();
        if (debug) $display("Put MMIOResp", fshow(req));
        rv_core.getMMIOResp(req);
    endrule

    // INSTRUMENTATION

    rule canonicalization if(doCanonicalize);
        rv_core.canonicalized();
        cache.halt();
        doCanonicalize <= False;
    endrule

    method Action restart;
        rv_core.restart();
        cache.restart();
    endmethod
    
    method Action canonicalize if(!doCanonicalize);
        rv_core.canonicalize();
        cache.restart();
        doCanonicalize <= True;
    endmethod
    
    method Action halt if(!doCanonicalize);
        rv_core.halt();
        cache.halt();
    endmethod

    method Action halted;
        rv_core.halted();
        cache.halted();
    endmethod

    method Action canonicalized;
        rv_core.canonicalized();
    endmethod

    method Action restarted;
        rv_core.restarted();
        cache.restarted();
    endmethod

    method Action request(Bit#(1) operation, ComponentId id, ExchangeAddress addr, ExchangeData data);
        case(id)
            0: rv_core.request(operation, 0, addr, data);   // pipeline
            1: cache.request(operation, 0, addr, data);     // l1i
            2: cache.request(operation, 1, addr, data);     // l1d
            3: cache.request(operation, 2, addr, data);     // l2
            4: cache.request(operation, 3, addr, data);     // DRAM
        endcase
        // $display("Core Request ", id, operation, addr, data);
    endmethod

    method ActionValue#(ExchangeData) response(ComponentId id);
        let data <- case(id)
            0: rv_core.response(0);         // pipeline
            1: cache.response(0);           // l1i
            2: cache.response(1);           // l1d
            3: cache.response(2);           // l2
            4: cache.response(3);           // DRAM
        endcase;
        // $display("Core Response ", id, data);
        return data;
    endmethod 

    method ActionValue#(Bit#(33)) getMMIO;
        mmio2host.deq();
        return mmio2host.first();
    endmethod

    method Action getHalt;
        haltFIFO.deq();
    endmethod

    method ActionValue#(Bit#(8)) uart2hostOutGET;
        uart2hostOutFIFO.deq();
        return uart2hostOutFIFO.first();
    endmethod

    method ActionValue#(Bool) uart2hostAvGET;
        uart2hostAvFIFO.deq();
        return uart2hostAvFIFO.first();
    endmethod
    
    method ActionValue#(Bool) uart2hostInGET;
        uart2hostInFIFO.deq();
        return uart2hostInFIFO.first();
    endmethod

    method Action host2uartAvPUT(Bit#(8) available);
        host2uartAvFIFO.enq(available);
    endmethod

    method Action host2uartInPUT(Bit#(8) data);
        host2uartInFIFO.enq(data);
    endmethod
endmodule
