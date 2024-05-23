CONNECTALDIR?=/home/xusine/EPFL/CS629/connectal
S2H_INTERFACES = CoreRequest:F2H.request
H2S_INTERFACES = F2H:CoreIndication

BSVFILES = F2H.bsv # Core.bsv DelayLine.bsv Ehr.bsv MainMem.bsv MemTypes.bsv Pipelined.bsv register_file.bsv RVUtil.bsv SnapshotTypes.bsv ./cache/Cache32.bsv ./cache/Cache32d.bsv ./cache/Cache512.bsv ./cache/CacheInterface.bsv ./cache/CacheUnit.bsv ./cache/GenericCache.bsv 
CPPFILES= glue.cpp

CONNECTALFLAGS += -D TRACE_PORTAL --bscflags="-p +:/home/xusine/EPFL/CS629/CCA-final-project/cache"

include $(CONNECTALDIR)/Makefile.connectal
