typedef enum {
    Read,
    Write
} SnapshotRequestType deriving (Eq, Bits, FShow);

typedef 4 ComponentsNum;
typedef Bit#(TLog#(ComponentsNum)) NrComponents;
typedef 64 AddrSize;

typedef Bit#(64) ExchageAddress;
typedef Bit#(512) ExchangeData;