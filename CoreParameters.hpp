#include <cstdint>

#define READ false
#define WRITE true

const uint8_t CORE_ID = 0;
const uint8_t REGISTER_FILE_ID = 0;
const uint8_t  L1I_ID = 1;
const uint8_t  L1D_ID = 2;
const uint8_t  L2_ID = 3;
const uint8_t  MAIN_MEM_ID = 4;
const uint64_t  RF_SIZE = 32;
const uint64_t  MAIN_MEM_SIZE = 1048576;
const int L1I_SET_COUNT_LOG2 = 6;
const int L1I_WAY_LOG2 = 1;
const int L1D_SET_COUNT_LOG2 = 6;
const int L1D_WAY_LOG2 = 1;
const int L2_SET_COUNT_LOG2 = 8;
const int L2_WAY_LOG2 = 2;