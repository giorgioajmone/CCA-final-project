import Assert::*;
import BRAM::*;
import FIFO::*;
import FIFOF::*;
import SpecialFIFOs::*;
import MemTypes::*;
import Ehr::*;
import Vector :: * ;
import CacheUnit :: * ;

import SnapshotTypes::*;

interface GenericCache#(numeric type addrcpuBits, numeric type datacpuBits, numeric type addrmemBits, numeric type datamemBits, numeric type numWords, numeric type numLogLines, numeric type numBanks, numeric type numWays, numeric type idx);
    method Action putFromProc(GenericCacheReq#(addrcpuBits, datacpuBits) e);
    method ActionValue#(Bit#(datacpuBits)) getToProc();
    method ActionValue#(GenericCacheReq#(addrmemBits, datamemBits)) getToMem();
    method Action putFromMem(Bit#(datamemBits) e);
    method Bit#(32) getMissCnt();

    method Action halt;
    method Action restart;
    method Action halted;
    method Action restarted;

    method Action request(Bit#(1) operation, ComponentId id, ExchangeAddress addr, ExchangeData data);
    method ActionValue#(ExchangeData) response(ComponentId id);
    
endinterface

module mkGenericCache(GenericCache#(addrcpuBits, datacpuBits, addrmemBits, datamemBits, numWords, numLogLines, numBanks, numWays, idx))
        provisos(
            Mul#(TDiv#(datacpuBits, TDiv#(datacpuBits, 8)), TDiv#(datacpuBits, 8), datacpuBits),
            Mul#(numWords, datacpuBits, datamemBits),
            Add#(addrcpuBits, TSub#(0, TLog#(numWords)), addrmemBits),
            Add#(a__, TSub#(numWays, 1), 512),
            Add#(b__, TAdd#(TSub#(TSub#(addrcpuBits, TLog#(numBanks)),TAdd#(TAdd#(TLog#(numWords), numLogLines), 0)), 2), 512),
            Add#(c__, datamemBits, 512),
            Add#(d__, 1, datacpuBits)
            // Alias#(CacheUnitResp#(Bit#(datacpuBits), CUTag#(addrcpuBits, numWords, numLogLines, numBanks), LineState, numWords), GenericCUResp),
            // Alias#(GenericParsedAddress, ParsedAddress#(addrcpuBits, numWords, numLogLines, numBanks))
        );
    Vector#(numWays, CacheUnit#(datacpuBits, LineState, TSub#(addrcpuBits, TLog#(numBanks)), numWords, numLogLines)) cache <- replicateM(mkCacheUnit());
    
    BRAM_Configure cfg = defaultValue;
    cfg.memorySize = 0; // makes it largest possible, i.e. 2^numLogLines
    String filename = "zero" + integerToString(2**valueOf(numLogLines)) + ".vmh";
    cfg.loadFormat = tagged Binary filename;  // zero out for you
    BRAM1Port#(Bit#(numLogLines), Bit#(TSub#(numWays, 1))) replacementMetadata <- mkBRAM1Server(cfg);
    
    Reg#(GenericMSHR#(addrcpuBits, datacpuBits, numWords, numLogLines, numBanks, numWays)) mshr <- mkReg(GenericMSHR {addr: ?, req: ?, wayToReplace: ?, state: READY});
    FIFOF#(Bit#(datacpuBits)) respondFifo <- mkBypassFIFOF();
    FIFO#(GenericCacheReq#(addrmemBits, datamemBits)) reqToMemFifo <- mkBypassFIFO();

    Reg#(Bit#(32)) clk <- mkReg(0);
    Reg#(Bit#(32)) missCnt <- mkReg(0);
    let verbose = False;

    Reg#(Bool) doHalt <- mkReg(True);

    function Bit#(TSub#(numWays, 1)) updateMetadata(Bit#(TSub#(numWays, 1)) old, Bit#(TLog#(numWays)) wayAccessed);
        // Pseudo LRU metadata update
        //  https://stackoverflow.com/questions/24409288/pseudo-least-recently-used-binary-tree
        Bit#(TSub#(numWays, 1)) newData = old;
        Integer metadataIdx = 0;
        for (Integer i = valueOf(TLog#(numWays)) - 1; i >= 0; i = i - 1) begin
            newData[metadataIdx] = ~wayAccessed[i];
            if (wayAccessed[i] == 0) begin
                // left child
                metadataIdx = metadataIdx * 2 + 1;
            end else begin
                // right child
                metadataIdx = metadataIdx * 2 + 2;
            end
        end
        return newData;
    endfunction: updateMetadata

    function Bit#(TLog#(numWays)) getReplacementWay(Bit#(TSub#(numWays, 1)) curMetadata);
        // Pseudo LRU replacement
        Integer metadataIdx = 0;
        Bit#(TLog#(numWays)) wayToReplace = 0;
        for (Integer i = valueOf(TLog#(numWays)) - 1; i >= 0; i = i - 1) begin
            wayToReplace[i] = curMetadata[metadataIdx];
            if (curMetadata[metadataIdx] == 0) begin
                // left child
                metadataIdx = metadataIdx * 2 + 1;
            end else begin
                // right child
                metadataIdx = metadataIdx * 2 + 2;
            end
        end
        return wayToReplace;
    endfunction: getReplacementWay

    rule clock;
        clk <= clk + 1;
    endrule

    rule startFill if (mshr.state == START_FILL && !doHalt);
        // Dirty writeback is done, now start the fill
        reqToMemFifo.enq(GenericCacheReq{addr: {mshr.addr.tag, mshr.addr.index, mshr.addr.bank}, data: ?, word_byte: 0});
        mshr.state <= WAITING_FOR_MEM;
        if (verbose)
            $display("[", valueOf(idx), "] Start fill ", clk);
    endrule

    rule getData if (mshr.state == WAITING_FOR_DATA && !doHalt);
        Vector#(numWays, CacheUnitResp#(Bit#(datacpuBits), CUTag#(addrcpuBits, numWords, numLogLines, numBanks), LineState, numWords)) resp = ?;
        for (Integer i = 0; i < valueOf(numWays); i = i + 1)
            resp[i] <- cache[i].res();
        let curMetadata <- replacementMetadata.portA.response.get;
        if (verbose)
            $display("[", valueOf(idx), "] Got data ", fshow(resp), " ", clk);
        CacheUnitHitMiss hitMiss = MISS;
        Bit#(TLog#(numWays)) way = ?;
        MSHRState nextState = WAITING_FOR_DATA;
        for (Integer i = 0; i < valueOf(numWays); i = i + 1) begin
            case (resp[i].hitMiss) matches
                LDHIT: begin
                    nextState = READY;
                    hitMiss = LDHIT;
                    way = fromInteger(i);
                    if (mshr.addr.index == 0)
                        if (verbose)
	                        $display("[", valueOf(idx), "] LDHit on way ", i, " ", clk);
                end
                STHIT: begin
                    hitMiss = STHIT;
                    nextState = READY;
                    way = fromInteger(i);
                    if (mshr.addr.index == 0)
                        if (verbose)
	                        $display("[", valueOf(idx), "] STHit on way ", i, " ", clk);
                end
                MISS: begin
                    if (nextState == WAITING_FOR_DATA && resp[i].missLine.status == Invalid) begin
                        // Not hit yet, but found an empty way
                        nextState = WAITING_FOR_MEM;
                        way = fromInteger(i);
                    end
                end
            endcase
        end
        if (hitMiss == LDHIT)
            respondFifo.enq(resp[way].ldData);
        else if (hitMiss == STHIT)
            respondFifo.enq(0);
        else if (hitMiss == MISS && nextState == WAITING_FOR_MEM) begin
            // miss and empty way
            reqToMemFifo.enq(GenericCacheReq{addr: {mshr.addr.tag, mshr.addr.index, mshr.addr.bank}, data: ?, word_byte: 0});
            if (mshr.addr.index == 0)
                if (verbose)
	                $display("[", valueOf(idx), "] Miss on way with empty ", way, " ", clk);
        end else if (hitMiss == MISS) begin
            // miss and no empty way choose a way to replace
            way = getReplacementWay(curMetadata);
            if (resp[way].missLine.status == Dirty) begin
                // write back
                reqToMemFifo.enq(GenericCacheReq{addr: {resp[way].missLine.tag, mshr.addr.index, mshr.addr.bank}, data: pack(resp[way].missLine.words), word_byte: ~unpack(0)});
                nextState = WAITING_FOR_DIRTY_RES;
            end else begin
                reqToMemFifo.enq(GenericCacheReq{addr: {mshr.addr.tag, mshr.addr.index, mshr.addr.bank}, data: ?, word_byte: 0});
                nextState = WAITING_FOR_MEM;
            end
            if (mshr.addr.index == 0)
               if (verbose)
	               $display("[", valueOf(idx), "] Miss on way evict ", way, " ", clk);
        end
        mshr <= GenericMSHR{addr: mshr.addr, req: mshr.req, wayToReplace: way, state: nextState};

        let newMetadata = updateMetadata(curMetadata, way);
        replacementMetadata.portA.request.put(BRAMRequest{write: True, responseOnWrite: False, address: mshr.addr.index, datain: newMetadata});
    endrule


    function Action requestLRU(Bit#(1) operation, Bit#(numLogLines) set, Bit#(TSub#(numWays, 1)) bits);
        action
            replacementMetadata.portA.request.put(BRAMRequest{write: operation == 1'b1, responseOnWrite: True, address: set, datain: bits});
        endaction
    endfunction: requestLRU

    function ActionValue#(ExchangeData) responseLRU();
        actionvalue
            Bit#(TSub#(numWays, 1)) res <- replacementMetadata.portA.response.get;
            return zeroExtend(res);
        endactionvalue
    endfunction: responseLRU

    FIFO#(Bit#(TLog#(numWays))) read_tag_token <- mkBypassFIFO();

    function Action requestTagAndStatus(Bit#(1) operation, Bit#(numLogLines) set, Bit#(TLog#(numWays)) way, ExchangeData data);
        action
            read_tag_token.enq(way);
            let upper_idx = valueOf(SizeOf#(Tuple2#(CUTag#(addrmemBits, numWords, numLogLines, 1), LineState)));
            let needed_data = data[upper_idx-1:0];
            cache[way].tagAndStatusReq(operation == 1'b1, set, unpack(needed_data));
        endaction
    endfunction: requestTagAndStatus

    function ActionValue#(ExchangeData) responseTagAndStatus();
        actionvalue
            let way = read_tag_token.first;
            read_tag_token.deq();
            let res <- cache[way].tagAndStatusResp();
            // now, we have to serialize the response
            ExchangeData exchangeData = zeroExtend(pack(res));
            return exchangeData;
        endactionvalue
    endfunction: responseTagAndStatus

    FIFO#(Bit#(TLog#(numWays))) read_data_token <- mkBypassFIFO();

    function Action requestData(Bit#(1) operation, Bit#(numLogLines) set, Bit#(TLog#(numWays)) way, ExchangeData data);
        action
            let upper_index = valueOf(SizeOf#(Vector#(numWords, Bit#(datacpuBits))));
            cache[way].dataReq(operation == 1, set, unpack(data[upper_index-1:0]));
            read_data_token.enq(way);
        endaction
    endfunction: requestData

    function ActionValue#(ExchangeData) responseData();
        actionvalue
            let way = read_data_token.first;
            read_data_token.deq();
            let res <- cache[way].dataResp(); 
            // now, we have to serialize the response. Maybe you don't need the zeroExtend here.
            ExchangeData exchangeData = zeroExtend(pack(res));
            return exchangeData;
        endactionvalue
    endfunction: responseData


    FIFOF#(Bit#(2)) request_fifo <- mkBypassFIFOF();

    // there are rules to detect the end of the canonicalization process

    method Action halt if (!doHalt);
        doHalt <= True;
        // halt all cache units.
        for (Integer i = 0; i < valueOf(numWays); i = i + 1)
            cache[i].halt;
    endmethod

    method Action restart if (doHalt);
        doHalt <= False;
        // restart all cache units.
        for (Integer i = 0; i < valueOf(numWays); i = i + 1)
            cache[i].restart;
    endmethod

    method Action halted if (doHalt);
        // all cache units are halted.
        for (Integer i = 0; i < valueOf(numWays); i = i + 1)
            cache[i].halted;
    endmethod

    method Action restarted if (!doHalt);
        // all cache units are restarted.
        for (Integer i = 0; i < valueOf(numWays); i = i + 1)
            cache[i].restarted;
    endmethod


    method Action request(Bit#(1) operation, ComponentId id, ExchangeAddress addr, ExchangeData data) if (doHalt);
        // the address is allocated in the following way:
        // low 2 bits: decide which information to extract:
        // - 00: LRU metadata
        // - 01: tag and status
        // - 10: data
        // - 11: Return nothing
        // The next bits are the set index.
        // The next bits are the way index.
        
        // I need to know where is the set index. 
        let set_index = addr[2+valueOf(numLogLines)-1:2]; // this is the set index
        let way_index_length = valueOf(TLog#(numWays));
        let way_index = addr[2+valueOf(numLogLines)+way_index_length-1:2+valueOf(numLogLines)]; // this is the way index
        case (addr[1:0])
            2'b00: begin
                requestLRU(operation, set_index, data[valueOf(TSub#(numWays, 1))-1:0]);
            end
            2'b01: begin
                requestTagAndStatus(operation, set_index, way_index, data);
            end
            2'b10: begin
                requestData(operation, set_index, way_index, data);
            end
            2'b11: begin
                dynamicAssert(False, "Invalid operation");
            end
        endcase
       
        $display("GenericCache : Metadata requested: ", addr[1:0]);
        request_fifo.enq(addr[1:0]); // TODO: deadlock here. Write operation should not call the 
    endmethod

    method ActionValue#(ExchangeData) response(ComponentId id) if (doHalt);
        ExchangeData res = ?;
        if (request_fifo.notEmpty) begin
            let operation = request_fifo.first;
            request_fifo.deq();
            case (operation)
                2'b00: begin
                    res <- responseLRU();
                end
                2'b01: begin
                    res <- responseTagAndStatus();
                end
                2'b10: begin
                    res <- responseData();
                end
                default: begin
                    dynamicAssert(False, "Invalid operation");
                    res = signExtend(1'b1);
                end
            endcase
        end
        return res;
    endmethod

    
    method Action putFromProc(GenericCacheReq#(addrcpuBits, datacpuBits) e) if (mshr.state == READY && !doHalt);
        ParsedAddress#(addrcpuBits, numWords, numLogLines, numBanks) addr = parseAddr(e.addr);
        let addrForBank = {addr.tag, addr.index, addr.offset};
        for (Integer i = 0; i < valueOf(numWays); i = i + 1)
            cache[i].req(CUCacheReq{addr: addrForBank, data: e.data, writeEn: e.word_byte});
        replacementMetadata.portA.request.put(BRAMRequest{write: False, responseOnWrite: False, address: addr.index, datain: ?});
        mshr <= GenericMSHR{addr: addr, req: e, wayToReplace: ?, state: WAITING_FOR_DATA};
        if (e.word_byte != 0) begin
            if (verbose)
	            $display("[", valueOf(idx), "] Store: ", fshow(addr), "word_byte: ", fshow(e.word_byte), " data: ", fshow(e.data), " ", clk);
        end else begin
            if (verbose)
	            $display("[", valueOf(idx), "] Load: ", fshow(addr), " ", clk);
        end
    endmethod
        
    method ActionValue#(Bit#(datacpuBits)) getToProc() if (!doHalt);
        let resp = respondFifo.first();
        respondFifo.deq();
        if (verbose)
	        $display("[", valueOf(idx), "] Responding with ", fshow(resp), " ", clk);
        return resp;
    endmethod
        
    method ActionValue#(GenericCacheReq#(addrmemBits, datamemBits)) getToMem() if (!doHalt);
        let req = reqToMemFifo.first();
        reqToMemFifo.deq();
        missCnt <= missCnt + 1;
        // if (verbose)
	    //     $display("[", valueOf(idx), "] Number of misses ", missCnt, " at clk ", clk);
        if (verbose)
	        $display("[", valueOf(idx), "] Requesting ", fshow(req), " ", clk);
        return req;
    endmethod
        
    method Action putFromMem(Bit#(datamemBits) e) if ((mshr.state == WAITING_FOR_MEM || mshr.state == WAITING_FOR_DIRTY_RES) && !doHalt);
        Vector#(numWords, Bit#(datacpuBits)) memline = unpack(e);
        let status = Clean;
        let nextState = READY;
        if (mshr.state == WAITING_FOR_DIRTY_RES) begin
            nextState = START_FILL;
            if (verbose)
                $display("[", valueOf(idx), "] Got dirty response ", fshow(memline[mshr.addr.offset]), " ", clk);
        end else begin
            if (mshr.req.word_byte != 0) begin
                // store
                if (verbose)
                    $display("[", valueOf(idx), "] Got store response ", fshow(memline[mshr.addr.offset]), " ", clk);
                Bit#(datacpuBits) finalMask = 0;
                for (Integer i = 0; i < valueOf(TDiv#(datacpuBits, 8)); i = i + 1) begin
                    if (mshr.req.word_byte[i] != 0) begin
                        finalMask = finalMask | ('hff << (fromInteger(i) * 8));
                    end
                end
                memline[mshr.addr.offset] = (mshr.req.data & finalMask) | (memline[mshr.addr.offset] & ~finalMask);
                status = Dirty;
                respondFifo.enq(0);
            end else begin
                if (verbose)
                    $display("[", valueOf(idx), "] Got load response ", fshow(memline[mshr.addr.offset]), " ", clk);
                respondFifo.enq(memline[mshr.addr.offset]);
            end
            cache[mshr.wayToReplace].update(TaggedLine{tag: mshr.addr.tag, status: status, words: memline}, mshr.addr.index);
        end
        mshr.state <= nextState;
    endmethod

    method Bit#(32) getMissCnt();
        return missCnt;
    endmethod
endmodule

typedef struct {
    ParsedAddress#(addrBits, numWords, numLogLines, numBanks) addr;
    GenericCacheReq#(addrBits, dataBits) req;
    MSHRState state;
    Bit#(TLog#(numWays)) wayToReplace;
} GenericMSHR#(numeric type addrBits, numeric type dataBits, numeric type numWords, numeric type numLogLines, numeric type numBanks, numeric type numWays) deriving (Bits, Eq);

typedef enum {
    READY,
    WAITING_FOR_DATA,
    WAITING_FOR_DIRTY_RES,
    START_FILL,
    WAITING_FOR_MEM
} MSHRState deriving (Bits, Eq, FShow);