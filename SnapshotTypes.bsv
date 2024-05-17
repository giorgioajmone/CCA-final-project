typedef enum {
    Read = 0,
    Write = 1
} SnapshotRequestType deriving (Eq, Bits, FShow);

typedef 4 ComponentsNum;
typedef Bit#(TLog#(ComponentsNum)) ComponentdId;

typedef Bit#(64) ExchageAddress;
typedef Bit#(512) ExchangeData;