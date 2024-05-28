#include <errno.h>
#include <stdint.h>
#include <stdio.h>
#include <cstdint>
#include <fstream>
#include <iostream>
#include <atomic>
#include <semaphore.h>

#include "json.hpp"
#include "CoreParameters.hpp"
#include "CoreRequest.h"
#include "CoreIndication.h"
#include "GeneratedTypes.h"


#define POS_MOD(a, b) ((a) % (b) + (b)) % (b)

using json = nlohmann::json;

std::atomic_uint64_t wait_for_hardware = {0};
std::atomic_uint64_t halt_flag = {0};
std::atomic_uint64_t quit_flag = {0};

static CoreRequestProxy *coreRequestProxy = 0;

static uint64_t receivedData[8] = {0};

class Buffer {
public:
    Buffer() : count(0), head(0) {
        data = new char[SIZE];
        sem_init(&can_read, 0, 0);
    }
    ~Buffer() {
        delete [] data;
    }
    void enq(char c) {
        if (count < SIZE) {
            count++;
            data[head + count] = c;
            sem_post(&can_read);
        } else {
            printf("Buffer full\n");
        }
    }
    char deq() {
        if (count > 0) {
            count--;
            head += POS_MOD(head, SIZE);
            return data[head + count];
        } else {
            sem_wait(&can_read);
            return deq();
        }
    }
    bool empty() {
        return count == 0;
    }
    unsigned int head;
    unsigned int count;
    char * data;

    sem_t can_read;

    static const int SIZE = 1024;
};

static Buffer * uart_buf;

class CoreIndication final : public CoreIndicationWrapper {
public:
    virtual void halted() override {
        assert(wait_for_hardware.load() == 1);
        wait_for_hardware.fetch_sub(1);
    }
    virtual void canonicalized() override {
        assert(wait_for_hardware.load() == 1);
        wait_for_hardware.fetch_sub(1);

    }
    virtual void restarted() override {
        assert(wait_for_hardware.load() == 1);
        wait_for_hardware.fetch_sub(1);
    }

    virtual void response(const bsvvector_Luint32_t_L16 output) override {
        for (int index = 0; index < 8; ++index) {
            receivedData[8 - index - 1] = (uint64_t(output[2*index]) << 32) | uint64_t(output[2*index + 1]);
        }

        assert(wait_for_hardware.load() == 1);
        wait_for_hardware.fetch_sub(1);
    }

    virtual void requestMMIO(const uint64_t data) override {
        if((data >> 32) & 0x1) {
            fprintf(stderr, "%d", static_cast<int>(data & 0xFFFFFFFF));
        } else {
            bool is_char = (data >> 8) == 0;
            if (is_char) {
                fprintf(stderr, "%c", static_cast<char>(data));
            } else {
                // extra data is here
                int extra_data = data >> 9;
                if (extra_data == 0) {
                    fprintf(stderr, " [0;32mPASS[0m");
                } else {
                    fprintf(stderr, " [0;31mFAIL[0m (%0d)", extra_data);
                }
                puts("");

                quit_flag.fetch_sub(1);
            }

            
        }
    }

    virtual void requestOutUART(const uint8_t data) override {
        putchar(data);
    }

    virtual void requestAvUART() override {
        coreRequestProxy->responseAvUART(!uart_buf->empty());
    }

    virtual void requestInUART() override {
        char c = uart_buf->deq();
        coreRequestProxy->responseInUART(c);
    }

    virtual void requestHalt() override {
        assert(halt_flag.load() == 1);
        halt_flag.fetch_sub(1);
    }

    CoreIndication(unsigned int id) : CoreIndicationWrapper(id) {}
};

static void halt() {
    assert(wait_for_hardware.load() == 0);
    wait_for_hardware.fetch_add(1);

    coreRequestProxy->halt();

    while(wait_for_hardware.load() != 0);
}

static void canonicalize() {
    assert(wait_for_hardware.load() == 0);
    wait_for_hardware.fetch_add(1);

    coreRequestProxy->canonicalize();

    while(wait_for_hardware.load() != 0);
}

static void restart() {
    assert(wait_for_hardware.load() == 0);
    wait_for_hardware.fetch_add(1);

    coreRequestProxy->restart();

    while(wait_for_hardware.load() != 0);
}

static void request(bool readOrWrite, uint8_t id, const uint64_t addr, const uint64_t data[8]) {
    assert(wait_for_hardware.load() == 0);
    wait_for_hardware.fetch_add(1);

    uint32_t data_buffer[16] = {0};

    for (int index = 0; index < 8; ++index) {
        data_buffer[2*index] = (data[8 - index - 1] >> 32) & 0xFFFFFFFF;
        data_buffer[2*index + 1] = data[8- index - 1] & 0xFFFFFFFF;
    }

    coreRequestProxy->request(readOrWrite, id, addr, data_buffer);

    while(wait_for_hardware.load() != 0);
}

static json extractSpecificCache(uint8_t id, int log2SetCount, int log2WayCount) {
    json cache;

    int setCount = 1 << log2SetCount;
    int wayCount = 1 << log2WayCount;

    cache["set"] = setCount;
    cache["way"] = wayCount;    

    for(int set = 0; set < setCount; ++set) {
        json set_results;

        uint64_t lru_addr = 0x0 | (set << 2);
        uint64_t fake_buffer[8] = {0};

        request(READ, id, lru_addr, fake_buffer);

        assert(wayCount < 64); 
        uint64_t lru = receivedData[0];
        set_results["lru"] = lru;

        for (int way = 0; way < wayCount; ++way) {
            json way_result;
            uint64_t tag_addr = 0x1 | (set << 2) | (way << (2 + log2SetCount));
            request(READ, id, tag_addr, fake_buffer);
            uint64_t tag_metadata = receivedData[0];

            uint64_t flag = tag_metadata & 0x3;
            if (flag == 0) { // not valid
                way_result["valid"] = false;
                way_result["dirty"] = false;
            } else if (flag == 1) { // clean
                way_result["valid"] = true;
                way_result["dirty"] = false;
            } else if (flag == 2) { // dirty
                way_result["valid"] = true;
                way_result["dirty"] = true;
            } else {
                assert(false);
            }

            uint64_t tag = (tag_metadata >> 2);
            way_result["tag"] = tag;

            uint64_t data_addr = 0x2 | (set << 2) | (way << (2 + log2SetCount));
            request(READ, id, data_addr, fake_buffer);
            uint64_t data[8] = {0};
            for (int i = 0; i < 8; ++i) {
                data[i] = receivedData[i];
            }

            for (int i = 0; i < 8; ++i) {
                way_result["data"].emplace_back(data[i]);
            }

            set_results["lines"].emplace_back(way_result);
        }

        cache["data"].emplace_back(set_results);
    }

    return cache;

}

static void loadCache(const json& cache, uint8_t id) {
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

        uint64_t lru_addr = 0x0 | (set << 2);

        uint64_t write_buffer[8] = {0};
        write_buffer[0] = lru;
        request(WRITE, id, lru_addr, write_buffer);  

        auto lines = set_results["lines"];
        for (int way = 0; way < wayCount; ++way) {
            auto way_result = lines[way];
            bool valid = way_result["valid"];
            bool dirty = way_result["dirty"];
            uint64_t tag = way_result["tag"];

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
            request(WRITE, id, tag_addr, write_buffer);

            auto data = way_result["data"];
            for (int i = 0; i < 8; ++i) {
                write_buffer[i] = data[i];
            }

            uint64_t data_addr = 0x2 | (set << 2) | (way << (2 + log2SetCount));
            request(WRITE, id, data_addr, write_buffer);
            
        }
    }
}

static std::array<json, 3> saveCache() {
    json l1i;
    json l1d;
    json l2;

    l1i = extractSpecificCache(L1I_ID, L1I_SET_COUNT_LOG2, L1I_WAY_LOG2);
    l1d = extractSpecificCache(L1D_ID, L1D_SET_COUNT_LOG2, L1D_WAY_LOG2);
    l2 = extractSpecificCache(L2_ID, L2_SET_COUNT_LOG2, L2_WAY_LOG2);

    return {l1i, l1d, l2};
}

static void exportSnapshot(std::ostream &s){
    json snapshot;
    uint64_t temporal_buffer[8] = {0}; 

    request(READ, CORE_ID, 0, temporal_buffer);
    snapshot["PC"] = receivedData[0];
    
    for(uint64_t i = 1; i < RF_SIZE; i++){
        request(READ, REGISTER_FILE_ID, i, temporal_buffer);
        snapshot["RegisterFile"].emplace_back(receivedData[0]);
        printf("Snapshot Register Status: %lu/%lu \r", i, RF_SIZE);
    }
    puts("");

    for(uint64_t i = 0; i < MAIN_MEM_SIZE; i++){
        request(READ, MAIN_MEM_ID, i, temporal_buffer);
        for (int j = 0; j < 8; j++) {
            snapshot["MainMem"][i].emplace_back(receivedData[j]);
        }
        printf("Snapshot Memory Status: %lu/%lu \r", i, MAIN_MEM_SIZE);
    }
    puts("");

    auto caches = saveCache();
    snapshot["L1i"] = caches[0];
    snapshot["L1d"] = caches[1];
    snapshot["L2"] = caches[2];
    
    s << std::setw(4) << snapshot << std::endl;
}

static void importSnapshot(std::istream &s){
    json snapshot;
    uint64_t write_buffer[8] = {0};

    s >> snapshot;

    write_buffer[0] = snapshot["PC"];
    request(WRITE, CORE_ID, 0, write_buffer);

    for(uint64_t i = 1; i < RF_SIZE; i++){
        write_buffer[0] = snapshot["RegisterFile"][i-1];
        request(WRITE, REGISTER_FILE_ID, i, write_buffer);
        printf("Load Register Status: %lu/%lu \r", i, RF_SIZE);
    }

    puts("");

    for(uint64_t i = 0; i < MAIN_MEM_SIZE; i++){
        auto data = snapshot["MainMem"][i];
        for(int j = 0; j < 8; j++){
            write_buffer[j] = data[j];
        }
        request(WRITE, MAIN_MEM_ID, i, write_buffer);
        printf("Load Memory Status: %lu/%lu \r", i, MAIN_MEM_SIZE);
    }

    puts("");

    loadCache(snapshot["L1i"], L1I_ID);
    loadCache(snapshot["L1d"], L1D_ID);
    loadCache(snapshot["L2"], L2_ID);
}



int main(int argc, const char **argv)
{
    long actualFrequency = 0;
    long requestedFrequency = 1e9 / MainClockPeriod;

    CoreIndication coreIndication(IfcNames_CoreIndicationH2S);
    coreRequestProxy = new CoreRequestProxy(IfcNames_CoreRequestS2H);

    wait_for_hardware.store(0);
    halt_flag.store(1);
    quit_flag.store(1);

    uart_buf = new Buffer();


    int status = setClockFrequency(0, requestedFrequency, &actualFrequency);
    fprintf(stderr, "Requested main clock frequency %5.2f, actual clock frequency %5.2f MHz status=%d errno=%d\n",
	    (double)requestedFrequency * 1.0e-6,
	    (double)actualFrequency * 1.0e-6,
	    status, (status != 0) ? errno : 0);


    // s[ave], l[oad], h[alt], r[estart], c[anonicalize], q[uit]
    char userChar;
    std::string command;

    while (true) {
        std::cout << "Enter command (s[ave], l[oad], h[alt], r[estart], c[anonicalize], w[rite], q[uit]): " << std::endl;
        std::cin >> command;
        if (command == "w" || command == "write") {
            std::cout << "Please enter a character: ";
            std::cin >> userChar;
            uart_buf->enq(userChar);
        } else if (command == "s" || command == "save") {
            std::string filePath;
            std::cout << "Enter the file path to save: ";
            std::cin >> filePath;

            std::ofstream file(filePath);
            exportSnapshot(file);
            file.flush();
            file.close();
        } else if (command == "l" || command == "load") {
            std::string filePath;
            std::cout << "Enter the file path to load: ";
            std::cin >> filePath;

            std::ifstream file(filePath);
            importSnapshot(file);
            file.close();

        } else if (command == "h" || command == "halt") {
            halt();
        } else if (command == "r" || command == "restart") {
            restart();
        } else if (command == "c" || command == "canonicalize") {
            canonicalize();
        } else if (command == "q" || command == "quit") {
            break;
        } else {
            std::cout << "Unknown command. Please try again.\n";
        }
    }
    
    return 0;
}