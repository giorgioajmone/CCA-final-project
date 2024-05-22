// SINGLE CORE ASSOIATED CACHE -- stores words

import BRAM::*;
import FIFO::*;
import FIFOF::*;
import SpecialFIFOs::*;
import MemTypes::*;
import Ehr::*;
import Vector::*;
import CacheUnit::*;
import GenericCache::*;

import SnapshotTypes::*;


// The types live in MemTypes.bsv

// Notice the asymmetry in this interface, as mentioned in lecture.
// The processor thinks in 32 bits, but the other side thinks in 512 bits.
interface Cache32d;
    method Action putFromProc(CacheReq e);
    method ActionValue#(Word) getToProc();
    method ActionValue#(MainMemReq) getToMem();
    method Action putFromMem(MainMemResp e);

    method Action halt;
    method Action restart;
    method Action halted;
    method Action restarted;

    method Action request(SnapshotRequestType operation, ComponentdId id, ExchageAddress addr, ExchangeData data);
    method ActionValue#(ExchangeData) response(ComponentdId id);
endinterface

(* synthesize *)
module mkCache32d(Cache32d);
    // addrcpuBits, datacpuBits, addrmemBits, datamemBits, numWords, numLogLines, numBanks, numWays, idx
    GenericCache#(30, 32, 26, 512, 16, 6, 1, 2, 2) cache <- mkGenericCache();

    method Action putFromProc(CacheReq e);
        GenericCacheReq#(30, 32) req = GenericCacheReq{addr: e.addr[31:2], data: e.data, word_byte: e.word_byte};
        cache.putFromProc(req);
    endmethod
        
    method ActionValue#(Word) getToProc();
        let resp <- cache.getToProc();
        return resp;
    endmethod
        
    method ActionValue#(MainMemReq) getToMem();
        let req <- cache.getToMem();
        return MainMemReq{write: req.word_byte==0 ? 0 : 1, addr: req.addr, data: req.data};
    endmethod
        
    method Action putFromMem(MainMemResp e);
        cache.putFromMem(e);
    endmethod

    method Action halt;
        cache.halt;
    endmethod

    method Action restart;
        cache.restart;
    endmethod

    method Action halted;
        cache.halted;
    endmethod

    method Action restarted;
        cache.restarted;
    endmethod

    method Action request(SnapshotRequestType operation, ComponentdId id, ExchageAddress addr, ExchangeData data);
        cache.request(operation, id, addr, data);
    endmethod

    method ActionValue#(ExchangeData) response(ComponentdId id);
        let data <- cache.response(id);
        return data;
    endmethod
endmodule