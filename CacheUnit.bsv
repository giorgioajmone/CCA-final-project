// Cache Unit

import BRAM::*;
import FIFO::*;
import FIFOF::*;
import SpecialFIFOs::*;
import MemTypes::*;
import Ehr::*;
import Vector :: * ;

interface CacheUnit#(numeric type dataBits, type cuStatus, numeric type addrBits, numeric type numWords, numeric type numLogLines);
    method Action req(CUCacheReq#(addrBits, dataBits) r);
    method ActionValue#(CacheUnitResp#(Bit#(dataBits), CUTag#(addrBits, numWords, numLogLines, 1), cuStatus, numWords)) res();
    method Action update(TaggedLine#(Bit#(dataBits), CUTag#(addrBits, numWords, numLogLines, 1), cuStatus, numWords) newLine, Bit#(numLogLines) lineNum);

    method Action halt;
    method Action restart;

    method Action halted;
    method Action restarted;

    // Althogh I really want to reuse the above methods, they are not designed to back up cache lines in the width of dataBits. Instead, they are for the requests. 
    // So I have to add a new method to back up the cache lines.
    method Action tagAndStatusReq(Bool is_write, Bit#(numLogLines) which_line, Tuple2#(CUTag#(addrBits, numWords, numLogLines, 1), cuStatus) tagAndStatus);
    method ActionValue#(Tuple2#(CUTag#(addrBits, numWords, numLogLines, 1), cuStatus)) tagAndStatusResp;

    method Action dataReq(Bool is_write, Bit#(numLogLines) which_line, Vector#(numWords, Bit#(dataBits)) data);
    method ActionValue#(Vector#(numWords, Bit#(dataBits))) dataResp; // the numWords confuses me. Why do I need it? I think it should be 1.
endinterface

module mkCacheUnit(CacheUnit#(dataBits, cuStatus, addrBits, numWords, numLogLines)) 
                provisos (
                    Bits#(cuStatus, cuStatusBits), 
                    Valid#(cuStatus), Dirty#(cuStatus),
                    Mul#(TDiv#(dataBits, TDiv#(dataBits, 8)), TDiv#(dataBits, 8), dataBits)
                    // Mul#(TDiv#(dataBits, 4), 4, dataBits)
                );
    BRAM_Configure cfg = defaultValue;
    cfg.memorySize = 0; // makes it largest possible, i.e. 2^numLogLines
    String filename = "zero" + integerToString(2**valueOf(numLogLines)) + ".vmh";
    cfg.loadFormat = tagged Binary filename;  // zero out for you

    BRAM2Port#(Bit#(numLogLines), CUTag#(addrBits, numWords, numLogLines, 1)) tagCache <- mkBRAM2Server(cfg);
    BRAM2Port#(Bit#(numLogLines), cuStatus) statusCache <- mkBRAM2Server(cfg);
    Vector#(numWords, BRAM2PortBE#(Bit#(numLogLines), Bit#(dataBits), TDiv#(dataBits, 8))) dataCache <- replicateM(mkBRAM2ServerBE(cfg));

    FIFO#(CUCacheReq#(addrBits, dataBits)) reqFIFO <- mkFIFO;


    // These requests are for aligning request.
    FIFOF#(Bool) tagAndStatusReqFIFO <- mkFIFOF;
    FIFOF#(Bool) dataReqFIFO <- mkFIFOF;

    Reg#(Bool) doHalt <- mkReg(True);

    method Action req(CUCacheReq#(addrBits, dataBits) r) if (!doHalt);
        ParsedAddress#(addrBits, numWords, numLogLines, 1) parsedAddress = parseAddr(r.addr);
        let index = parsedAddress.index;
        let offset = parsedAddress.offset;

        // Send read requests to all the BRAMs
        tagCache.portA.request.put(BRAMRequest{write: False, responseOnWrite: False, address: index, datain: ?});
        statusCache.portA.request.put(BRAMRequest{write: False, responseOnWrite: False, address: index, datain: ?});
        for (Integer i = 0; i < valueOf(numWords); i = i + 1)
            dataCache[i].portA.request.put(BRAMRequestBE{writeen: 0, responseOnWrite: False, address: index, datain: ?});
        reqFIFO.enq(r);
    endmethod

    method ActionValue#(CacheUnitResp#(Bit#(dataBits), CUTag#(addrBits, numWords, numLogLines, 1), cuStatus, numWords)) res() if (!doHalt);
        CacheUnitResp#(Bit#(dataBits), CUTag#(addrBits, numWords, numLogLines, 1), cuStatus, numWords) resp = ?;
        let req = reqFIFO.first;
        reqFIFO.deq;
        ParsedAddress#(addrBits, numWords, numLogLines, 1) parsedAddress = parseAddr(req.addr);
        let index = parsedAddress.index;
        let tag = parsedAddress.tag;
        let offset = parsedAddress.offset;

        let tagResp <- tagCache.portA.response.get;
        let statusResp <- statusCache.portA.response.get;
        Vector#(numWords, Bit#(dataBits)) dataResp;
        for (Integer i = 0; i < valueOf(numWords); i = i + 1)
            dataResp[i] <- dataCache[i].portA.response.get;

        if (isValid(statusResp) && tagResp == tag && req.writeEn == 0) begin
            // Load Hit
            resp.hitMiss = LDHIT;
            resp.ldData = dataResp[offset];
            // not needed debug info
            resp.missLine.words = dataResp;
            resp.missLine.tag = tagResp;
            resp.missLine.status = statusResp;
        end else if (isValid(statusResp) && tagResp == tag && req.writeEn != 0) begin
            // Store Hit
            let newStatus = makeDirty(statusResp);
            // update status to be dirty and update the data
            statusCache.portB.request.put(BRAMRequest{write: True, responseOnWrite: False, address: index, datain: newStatus});
            resp.missLine.words = dataResp;
            dataCache[offset].portB.request.put(BRAMRequestBE{writeen: req.writeEn, responseOnWrite: False, address: index, datain: req.data});
            resp.hitMiss = STHIT;
            // not needed debug info
            resp.missLine.words = dataResp;
            resp.missLine.tag = tagResp;
            resp.missLine.status = statusResp;
        end else begin
            // Miss
            resp.hitMiss = MISS;
            resp.missLine.words = dataResp;
            resp.missLine.tag = tagResp;
            resp.missLine.status = statusResp;
        end
        return resp;
    endmethod

    method Action update(TaggedLine#(Bit#(dataBits), CUTag#(addrBits, numWords, numLogLines, 1), cuStatus, numWords) newLine, Bit#(numLogLines) lineNum) if (!doHalt);
        // Send write requests to all the BRAMs without checking
        tagCache.portB.request.put(BRAMRequest{write: True, responseOnWrite: False, address: lineNum, datain: newLine.tag});
        statusCache.portB.request.put(BRAMRequest{write: True, responseOnWrite: False, address: lineNum, datain: newLine.status});
        for (Integer i = 0; i < valueOf(numWords); i = i + 1)
            dataCache[i].portB.request.put(BRAMRequestBE{writeen: ~0, responseOnWrite: False, address: lineNum, datain: newLine.words[i]});
    endmethod

    method Action halt;
        doHalt <= True;
    endmethod

    method Action restart if (doHalt);
        doHalt <= False;
    endmethod

    method Action halted if (doHalt);
    endmethod

    method Action restarted if (!doHalt);
    endmethod

    method Action tagAndStatusReq(Bool is_write, Bit#(numLogLines) which_line, Tuple2#(CUTag#(addrBits, numWords, numLogLines, 1), cuStatus) tagAndStatus) if (doHalt);
        tagCache.portA.request.put(BRAMRequest{write: is_write, responseOnWrite: True, address: which_line, datain: tpl_1(tagAndStatus)});
        statusCache.portA.request.put(BRAMRequest{write: is_write, responseOnWrite: True, address: which_line, datain: tpl_2(tagAndStatus)});
        tagAndStatusReqFIFO.enq(?);
    endmethod

    method ActionValue#(Tuple2#(CUTag#(addrBits, numWords, numLogLines, 1), cuStatus)) tagAndStatusResp if(doHalt);
        let return_value = ?;
        if (tagAndStatusReqFIFO.notEmpty) begin
            let tagResp <- tagCache.portA.response.get;
            let statusResp <- statusCache.portA.response.get;
            tagAndStatusReqFIFO.deq;
            return_value = tuple2(tagResp, statusResp);
        end
        return return_value;
    endmethod

    method Action dataReq(Bool is_write, Bit#(numLogLines) which_line, Vector#(numWords, Bit#(dataBits)) data) if(doHalt);
        $display("CacheUnit: dataReq");
        $display("CacheUnit: is_write = %0d, which_line = %0d, data = %0h", is_write, which_line, data);
        let write_mask = ?;
        if (is_write) write_mask = ~0; else write_mask = 0;

        for (Integer i = 0; i < valueOf(numWords); i = i + 1)
            dataCache[i].portA.request.put(BRAMRequestBE{writeen: write_mask, responseOnWrite: True, address: which_line, datain: data[i]});
        
        dataReqFIFO.enq(?);

    endmethod

    method ActionValue#(Vector#(numWords, Bit#(dataBits))) dataResp if (doHalt);
        $display("CacheUnit: dataResp");
        Vector#(numWords, Bit#(dataBits)) return_value = ?;
        for (Integer i = 0; i < valueOf(numWords); i = i + 1) return_value[i] = signExtend(1'b1);
        if (dataReqFIFO.notEmpty) begin
            Vector#(numWords, Bit#(dataBits)) resp = ?;
            for (Integer i = 0; i < valueOf(numWords); i = i + 1)
                resp[i] <- dataCache[i].portA.response.get;
            dataReqFIFO.deq;
            return_value = resp;
        end
        return return_value;
    endmethod
endmodule