#include <errno.h>
#include <stdio.h>
#include <semaphore.h>
#include <cstdint>

#include "json.hpp"

#include "CoreRequest.h"
#include "CoreIndication.h"
#include "GeneratedTypes.h"

using json = nlohmann::json;

#define CORE_ID 0
#define REGISTER_FILE_ID 0
#define L1I_ID REGISTER_FILE_ID + 1
#define L1D_ID L1I_ID + 1
#define L2_ID L1D_ID + 1
#define MAIN_MEM_ID L2_ID + 1
#define RF_SIZE 32
#define MAIN_MEM_SIZE 65536
#define L1_SIZE 128
#define L2_SIZE 256

#define READ false
#define WRITE true

//TO DO: add header files for connectal 

static CoreRequestProxy *coreRequestProxy = 0;
static sem_t sem_response;

static uint64_t receivedData[8] = {0};

class CoreIndication final : public CoreIndicationWrapper {
public:
    virtual void halted() override {
        sem_post(&sem_response);
    }
    virtual void canonicalized() override {
        sem_post(&sem_response);
    }
    virtual void restarted() override {
        sem_post(&sem_response);
    }

    virtual void response(const bsvvector_Luint32_t_L16 output) override {
        // copy the output to the receivedData buffer.
        memcpy(receivedData, output, 16 * sizeof(uint32_t));
        sem_post(&sem_response);
    }

    virtual void requestMMIO(const uint64_t data) override {
        if((data >> 32) & 0x1)
            fprintf(stderr, "%d", static_cast<int>(data & 0xFFFFFFFF));
        else
            fprintf(stderr, "%c", static_cast<int>((data & 0xFF)+'0'));
    }

    virtual void requestHalt(const int data) override {
        //TO DO when the fpga wants to halt
    }

    CoreIndication(unsigned int id) : CoreIndicationWrapper(id) {}
};

static void halt() {
    coreRequestProxy->halt();
    sem_wait(&sem_response);
}

static void canonicalize() {
    coreRequestProxy->canonicalize();
    sem_wait(&sem_response);
}

static void restart() {
    coreRequestProxy->restart();
    sem_wait(&sem_response);
}

static void request(bool readOrWrite, uint8_t id, const uint64_t addr, const bsvvector_Luint32_t_L16 data) {
    coreRequestProxy->request(readOrWrite, id, addr, data);
    sem_wait(&sem_response);
}

static json extractSpecificCache(uint8_t id, int log2SetCount, int log2WayCount) {
    json cache;

    int setCount = 1 << log2SetCount;
    int wayCount = 1 << log2WayCount;

    cache["set"] = setCount;
    cache["way"] = wayCount;    

    for(int set = 0; set < setCount; ++set) {
        json set_results;
        // fetch the LRU bits.
        uint64_t lru_addr = 0x0 | (set << 2);
        uint32_t fake_buffer[16] = {0};

        request(READ, id, lru_addr, fake_buffer);

        assert(wayCount < 64); // Currently, we only support 64 ways, which is already enough.
        uint64_t lru = receivedData[0];
        set_results["lru"] = lru;

        // Now, fetch each way.
        for (int way = 0; way < wayCount; ++way) {
            json way_result;
            // read the tag and metadata of the way.
            uint64_t tag_addr = 0x1 | (set << 2) | (way << (2 + log2SetCount));
            request(READ, id, tag_addr, fake_buffer);
            uint64_t tag_metadata = receivedData[0];

            uint64_t flag = tag_metadata & 0x3; // low 2-bit.
            if (flag == 0) {
                // not valid.
                way_result["valid"] = false;
                way_result["dirty"] = false;
            } else if (flag == 1) {
                // clean.
                way_result["valid"] = true;
                way_result["dirty"] = false;
            } else if (flag == 2) {
                // dirty.
                way_result["valid"] = true;
                way_result["dirty"] = true;
            } else {
                assert(false);
            }

            uint64_t tag = (tag_metadata >> 2);
            way_result["tag"] = tag;

            // read the data of the way.
            uint64_t data_addr = 0x2 | (set << 2) | (way << (2 + log2SetCount));
            request(READ, id, data_addr, fake_buffer);
            uint64_t data[8] = {0};
            // copy it to the local buffer.
            for (int i = 0; i < 8; ++i) {
                data[i] = receivedData[i];
            }
            // convert data into 8 64-bit integers.
            for (int i = 0; i < 8; ++i) {
                way_result["data"].emplace_back(data[i]);
            }

            set_results["lines"].emplace_back(way_result);
        }

        cache["data"].emplace_back(set_results);
    }

    return cache;

}

static void deserializeCache(const json& cache, uint8_t id) {
    int setCount = cache["set"];
    int wayCount = cache["way"];

    int log2SetCount = 0;
    while ((1 << log2SetCount) < setCount) {
        ++log2SetCount;
    }

    int log2WayCount = 0;
    while ((1 << log2WayCount) < wayCount) {
        ++log2WayCount;
    }

    auto data = cache["data"];
    for (int set = 0; set < setCount; ++set) {
        auto set_results = data[set];
        uint64_t lru = set_results["lru"];

        // generate the address of updating LRU bits.
        uint64_t lru_addr = 0x0 | (set << 2);

        uint64_t write_buffer[8] = {0};
        write_buffer[0] = lru;
        request(WRITE, id, lru_addr, reinterpret_cast<uint32_t *>(write_buffer));  

        auto lines = set_results["lines"];
        for (int way = 0; way < wayCount; ++way) {
            auto way_result = lines[way];
            bool valid = way_result["valid"];
            bool dirty = way_result["dirty"];
            uint64_t tag = way_result["tag"];

            // generate the address of updating tag and metadata.
            uint64_t tag_addr = 0x1 | (set << 2) | (way << (2 + log2SetCount));
            uint64_t tag_metadata = (tag << 2);
            if (valid) {
                if (dirty) {
                    tag_metadata |= 0x2;
                } else {
                    tag_metadata |= 0x1;
                }
            } else {
                tag_metadata |= 0x0;
            }

            write_buffer[0] = tag_metadata;

            request(WRITE, id, tag_addr, reinterpret_cast<uint32_t *>(write_buffer));

            auto data = way_result["data"];
            for (const auto& value : data) {
                write_buffer[0] = value;
            }

            // generate the address of updating data.
            uint64_t data_addr = 0x2 | (set << 2) | (way << (2 + log2SetCount));
            request(WRITE, id, data_addr, reinterpret_cast<uint32_t *>(write_buffer));
            
        }
    }
}

static std::array<json, 3> exportCache() {
    json l1i;
    json l1d;
    json l2;

    // I assume the system is already halted and canonicalized.

    // L1I
    const int L1I_SET_COUNT_LOG2 = 6;
    const int L1I_WAY_LOG2 = 1;

    l1i = extractSpecificCache(L1I_ID, L1I_SET_COUNT_LOG2, L1I_WAY_LOG2);

    // L1D
    const int L1D_SET_COUNT_LOG2 = 6;
    const int L1D_WAY_LOG2 = 1;

    l1d = extractSpecificCache(L1D_ID, L1D_SET_COUNT_LOG2, L1D_WAY_LOG2);

    // L2
    const int L2_SET_COUNT_LOG2 = 8;
    const int L2_WAY_LOG2 = 2;

    l2 = extractSpecificCache(L2_ID, L2_SET_COUNT_LOG2, L2_WAY_LOG2);

    return {l1i, l1d, l2};
}

static void exportSnapshot(std::ostream &s){
    json snapshot;

    halt();
    canonicalize();

    uint32_t temporal_buffer[16] = {0}; 

    //PC
    request(READ, CORE_ID, 0, temporal_buffer);
    snapshot["PC"] = receivedData[0];

    //RF
    for(uint64_t i = 1; i < RF_SIZE; i++){
        request(READ, REGISTER_FILE_ID, i, temporal_buffer);
        snapshot["RegisterFile"].emplace_back(receivedData[0]);
    }

    //MAIN MEMORY
    for(uint64_t i = 0; i < MAIN_MEM_SIZE; i++){
        request(READ, MAIN_MEM_ID, i, temporal_buffer);
        for (int j = 0; j < 8; j++) {
            snapshot["MainMem"][i].emplace_back(receivedData[j]);
        }
    }

    //CACHE
    auto caches = exportCache();
    snapshot["L1i"] = caches[0];
    snapshot["L1d"] = caches[1];
    snapshot["L2"] = caches[2];


    restart();

    s << std::setw(4) << snapshot << std::endl;
}

static void importSnapshot(std::istream &s){
    json snapshot;

    s >> snapshot;

    halt();
    canonicalize();

    uint64_t write_buffer[8] = {0};

    write_buffer[0] = snapshot["PC"];
    //PC
    request(WRITE, CORE_ID, 0, reinterpret_cast<uint32_t *>(write_buffer));

    //RF
    for(uint64_t i = 1; i < RF_SIZE; i++){
        write_buffer[0] = snapshot["RegisterFile"][i];
        request(WRITE, REGISTER_FILE_ID, i, reinterpret_cast<uint32_t *>(write_buffer));
    }

    //MAIN MEMORY
    for(uint64_t i = 0; i < MAIN_MEM_SIZE; i++){
        auto data = snapshot["MainMem"][i];
        for(int j = 0; j < 8; j++){
            write_buffer[j] = data[j];
        }
        request(WRITE, MAIN_MEM_ID, i, reinterpret_cast<uint32_t *>(write_buffer));
    }

    // import L1i, L1d, L2 cache
    deserializeCache(snapshot["L1i"], L1I_ID);
    deserializeCache(snapshot["L1d"], L1D_ID);
    deserializeCache(snapshot["L2"], L2_ID);

    restart();
}



int main(int argc, const char **argv)
{
    long actualFrequency = 0;
    long requestedFrequency = 1e9 / MainClockPeriod;

    CoreIndication coreIndication(IfcNames_CoreIndicationH2S);
    coreRequestProxy = new CoreRequestProxy(IfcNames_CoreRequestS2H);

    int status = setClockFrequency(0, requestedFrequency, &actualFrequency);
    fprintf(stderr, "Requested main clock frequency %5.2f, actual clock frequency %5.2f MHz status=%d errno=%d\n",
	    (double)requestedFrequency * 1.0e-6,
	    (double)actualFrequency * 1.0e-6,
	    status, (status != 0) ? errno : 0);

    return 0;
}

/* // L1I DIRECT MAPPED CACHE FIELD = 0
    for(uint64_t address = 0; address < L1_SIZE; address++){
        request(READ, L1I_ID, 0 << 7 | address, 0);
        snapshot["L1i"]["Tags"].emplace_back(static_cast<uint64_t>(receivedData));
    }

    // L1I DIRECT MAPPED CACHE FIELD = 1
    for(uint64_t address = 0; address < L1_SIZE; address++){
        request(READ, L1I_ID, 1 << 7 | address, 0);
        snapshot["L1i"]["State"].emplace_back(static_cast<uint64_t>(receivedData));
    }

    // L1I DIRECT MAPPED CACHE FIELD = 2
    for(uint64_t address = 0; address < L1_SIZE; address++){
        for(uint64_t slice = 0; slice < 8; slice++){
            request(READ, L1I_ID, slice << 9 | 2 << 7 | address, 0);
            snapshot["L1i"]["Data"][address].emplace_back(static_cast<uint64_t>(receivedData));
        }
    }

    // L1D DIRECT MAPPED CACHE FIELD = 0
    for(uint64_t address = 0; address < L1_SIZE; address++){
        request(READ, L1D_ID, 0 << 7 | address, 0);
        snapshot["L1d"]["Tags"].emplace_back(static_cast<uint64_t>(receivedData));
    }

    // L1D DIRECT MAPPED CACHE FIELD = 1
    for(uint64_t address = 0; address < L1_SIZE; address++){
        request(READ, L1D_ID, 1 << 7 | address, 0);
        snapshot["L1d"]["State"].emplace_back(static_cast<uint64_t>(receivedData));
    }

    // L1D DIRECT MAPPED CACHE FIELD = 2
    for(uint64_t address = 0; address < L1_SIZE; address++){
        for(uint64_t slice = 0; slice < 8; slice++){
            request(READ, L1D_ID, slice << 9 | 2 << 7 | address, 0);
            snapshot["L1d"]["Data"][address].emplace_back(static_cast<uint64_t>(receivedData));
        }
    }

    // L2 DIRECT MAPPED CACHE FIELD = 0
    for(uint64_t address = 0; address < L2_SIZE; address++){
        request(READ, L2_ID, 0 << 8 | address, 0);
        snapshot["L2"]["Tags"].emplace_back(static_cast<uint64_t>(receivedData));
    }

    // L2 DIRECT MAPPED CACHE FIELD = 1
    for(uint64_t address = 0; address < L2_SIZE; address++){
        request(READ, L2_ID, 1 << 8 | address, 0);
        snapshot["L2"]["State"].emplace_back(static_cast<uint64_t>(receivedData));
    }

    // L2 DIRECT MAPPED CACHE FIELD = 2
    for(uint64_t address = 0; address < L2_SIZE; address++){
        for(uint64_t slice = 0; slice < 8; slice++){
            request(READ, L2_ID, slice << 10 | 2 << 8 | address, 0);
            snapshot["L2"]["Data"][address].emplace_back(static_cast<uint64_t>(receivedData));
        }
    } */