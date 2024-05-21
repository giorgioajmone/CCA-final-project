import Vector :: * ;

// Types used in L1 interface
typedef struct { Bit#(1) write; Bit#(26) addr; Bit#(512) data; } MainMemReq deriving (Eq, FShow, Bits, Bounded);
typedef struct { Bit#(4) word_byte; Bit#(32) addr; Bit#(32) data; } CacheReq deriving (Eq, FShow, Bits, Bounded);
typedef Bit#(512) MainMemResp;
typedef Bit#(32) Word;
typedef Vector#(16, Word) LineData;
typedef Vector#(8, Bit#(64)) SlicedData;

typedef enum {Ready, ReadingCacheHit, StartMiss, ReadingCacheMiss, SendFillReq, WaitFillResp} ReqStatus deriving (Bits, Eq); 

// (Curiosity Question: CacheReq address doesn't actually need to be 32 bits. Why?)

// Helper types for implementation (L1 cache):
typedef enum {
    Invalid,
    Clean,
    Dirty
} LineState deriving (Eq, Bits, FShow);

typedef Bit#(7) LineIndex;
typedef Bit#(4) WordOffset;
typedef Bit#(19) LineTag;

typedef struct {
    LineTag tag;
    LineIndex index;
    WordOffset offset;
} ParsedAddress deriving (Bits, Eq);

function ParsedAddress parseAddress(Bit#(32) addr);
    return ParsedAddress{tag : addr[31:13], index : addr[12:6], offset : addr[5:2]};
endfunction

function Bit#(64) writeWordOffset(ParsedAddress pa, Bit#(4) word_byte);
    Bit#(64) tmp0 = zeroExtend(word_byte); Bit#(64) tmp1 = zeroExtend(pa.offset)*4;
    return tmp0 << tmp1;
endfunction

function Bit#(64) writeSliceOffset(Bit#(3) offset);
    Bit#(64) tmp0 = zeroExtend(8'hFF); Bit#(64) tmp1 = zeroExtend(offset)*4;
    return tmp0 << tmp1;
endfunction

function LineData inlineWord(ParsedAddress pa, Bit#(32) data);
    LineData result = unpack(0); result[pa.offset] = data;
    return result;
endfunction

function Word updateWord(Word original, Word modified, Bit#(4) word_byte);
    Vector#(4, Bit#(8)) tmp0 = unpack(original); Vector#(4, Bit#(8)) tmp1 = unpack(modified);
    for(Integer i = 0; i < 4; i = i + 1) begin
        if(word_byte[i] == 1) begin
            tmp0[i] = tmp1[i];
        end
    end 
    return pack(tmp0);
endfunction

// Helper types for implementation (L2 cache):

typedef Bit#(8) LineIndex512;
typedef Bit#(18) LineTag512;

typedef struct {
    LineTag512 tag;
    LineIndex512 index;
} ParsedAddress512 deriving (Bits, Eq);

function ParsedAddress512 parseAddress512(Bit#(26) addr);
    return ParsedAddress512{tag : addr[25:8], index : addr[7:0]};
endfunction