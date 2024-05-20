import RVUtil::*;
import BRAM::*;
import FIFO::*;
import SpecialFIFOs::*;
import DelayLine::*;
import MemTypes::*;

import SnapshotTypes::*;

interface MainMem;
    method Action put(MainMemReq req);
    method ActionValue#(MainMemResp) get();

    // INSTRUMENTATION 
    method Action halt;
    method Action canonicalize;
    method Action restart;
    method Action halted;
    method Action restarted;
    method Action canonicalized;

    method Action request(SnapshotRequestType operation, ComponentdId id, ExchageAddress addr, ExchangeData data);
    method ActionValue#(ExchangeData) response(ComponentdId id);
endinterface

interface MainMemFast;
    method Action put(CacheReq req);
    method ActionValue#(Word) get();
endinterface

module mkMainMemFast(MainMemFast);
    BRAM_Configure cfg = defaultValue();
    cfg.loadFormat = tagged Hex "mem.vmh";
    BRAM1PortBE#(Bit#(30), Word, 4) bram <- mkBRAM1ServerBE(cfg);
    DelayLine#(10, Word) dl <- mkDL(); // Delay by 20 cycles

    rule deq;
        let r <- bram.portA.response.get();
        dl.put(r);
    endrule    

    method Action put(CacheReq req);
        bram.portA.request.put(BRAMRequestBE{
                    writeen: req.word_byte,
                    responseOnWrite: False,
                    address: req.addr[31:2],
                    datain: req.data});
    endmethod

    method ActionValue#(Word) get();
        let r <- dl.get();
        return r;
    endmethod
endmodule

module mkMainMem(MainMem);
    BRAM_Configure cfg = defaultValue();
    cfg.loadFormat = tagged Hex "memlines.vmh";
    BRAM1Port#(LineAddr, MainMemResp) bram <- mkBRAM1Server(cfg);

    DelayLine#(20, MainMemResp) dl <- mkDL(); // Delay by 20 cycles

    // INSTRUMENTATION
    Reg#(Bool) doHalt <- mkReg(False);
    Reg#(Bool) doCanonicalize <- mkReg(False);
    FIFO#(ExchangeData) responseFIFO <- mkBypassFIFO;

    rule deq if(!doHalt && !doCanonicalize);
        let r <- bram.portA.response.get();
        dl.put(r);
    endrule    

    rule waitResponse if(doHalt || doCanonicalize);
        let r <- bram.portA.response.get();
        responseFIFO.enq(r);
    endrule 

    method Action put(MainMemReq req);
        bram.portA.request.put(BRAMRequest{
                    write: unpack(req.write),
                    responseOnWrite: True,
                    address: req.addr,
                    datain: req.data});
    endmethod

    method ActionValue#(MainMemResp) get();
        let r <- dl.get();
        return r;
    endmethod

    // INSTRUMENTATION 

    method Action halt;
        doHalt <= True;
    endmethod

    method Action halted if(doHalt);
    endmethod

    method Action restart;
        doHalt <= False;
        doCanonicalize <= False;
    endmethod

    method Action restarted if(!doHalt && !doCanonicalize);
    endmethod    

    method Action canonicalize;
        doCanonicalize <= True;
    endmethod

    method Action canonicalized if(doCanonicalize);
    endmethod    

    method Action request(SnapshotRequestType operation, ComponentdId id, ExchageAddress addr, ExchangeData data) if(doHalt || doCanonicalize);
        let address = addr[valueOf(LineAddrLength)-1:0];
        if(operation == Read) begin
            bram.portA.request.put(BRAMRequest{write: unpack(0), responseOnWrite: True, address: address, datain: data});
        end else begin
            bram.portA.request.put(BRAMRequest{write: unpack(1), responseOnWrite: True, address: address, datain: data});
        end
    endmethod

    method ActionValue#(ExchangeData) response(ComponentdId id) if(doHalt || doCanonicalize);
        responseFIFO.deq();
        return responseFIFO.first();
    endmethod
endmodule

