typedef Bit#(3) ComponentId;

typedef Bit#(64) ExchangeAddress;
typedef Bit#(512) ExchangeData;

interface CoreIndication;
    method Action halted;
    method Action restarted;
    method Action canonicalized;
    method Action response(ExchangeData data);
    method Action requestMMIO(Bit#(33) data);
    method Action requestHalt(Bool data);
endinterface

interface CoreRequest;
    method Action halt;
    method Action canonicalize;
    method Action restart;
    method Action request(Bit#(1) operation, ComponentId id, ExchangeAddress addr, ExchangeData data);
endinterface

interface F2H;
   interface CoreRequest request;
endinterface