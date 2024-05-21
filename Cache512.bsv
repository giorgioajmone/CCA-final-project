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


// Note that this interface *is* symmetric. 
interface Cache512;
    method Action putFromProc(MainMemReq e);
    method ActionValue#(MainMemResp) getToProc();
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
module mkCache512(Cache512);
    // addrcpuBits, datacpuBits, addrmemBits, datamemBits, numWords, numLogLines, numBanks, numWays, idx
    GenericCache#(26, 512, 26, 512, 1, 6, 1, 4, 3) cache <- mkGenericCache();

    method Action putFromProc(MainMemReq e);
        GenericCacheReq#(26, 512) req = GenericCacheReq{addr: e.addr, data: e.data, word_byte: e.write==0 ? 0 : ~0};
        cache.putFromProc(req);
    endmethod

    method ActionValue#(MainMemResp) getToProc();
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
