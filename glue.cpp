#include <errno.h>
#include <stdio.h>
#include <semaphore.h>
#include <cstdint>

#include "json.hpp"
#include <boost/multiprecision/cpp_int.hpp>

using json = nlohmann::json;
using namespace boost::multiprecision;

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

static uint512_t receivedData = 0;

class CoreIndication : public CoreIndicationWrapper {
public:
    virtual void halted() {
        sem_post(&sem_response);
    }
    virtual void canonicalized() {
        sem_post(&sem_response);
    }
    virtual void restarted() {
        sem_post(&sem_response);
    }

    virtual void response(uint512_t output) {
        receivedData = output;
        sem_post(&sem_response);
    }

    virtual void requestMMIO(uint64_t data){
        if((data >> 32) & 0x1)
            fprintf(stderr, "%d", data & 0xFFFFFFFF);
        else
            fprintf(stderr, "%c", (data & 0xFF)+'0');
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

static void request(bool readOrWrite, uint8_t id, uint64_t addr, uint512_t data) {
    coreRequestProxy->request(readOrWrite, id, addr, data);
    sem_wait(&sem_response);
}

static void exportSnapshot(std::ostream &s){
    json snapshot;

    halt();
    canonicalize();

    //PC
    request(READ, CORE_ID, 0, 0);
    snapshot["PC"] = (uint64_t)receivedData;

    //RF
    for(uint64_t i = 1; i < RF_SIZE; i++){
        request(READ, REGISTER_FILE_ID, (uint64_t) i, 0);
        snapshot["RegisterFile"].emplace_back((uint64_t)receivedData);
    }

    //MAIN MEMORY
    for(uint64_t i = 0; i < MAIN_MEM_SIZE; i++){
        request(READ, MAIN_MEM_ID, (uint64_t) i, 0);
        snapshot["MainMem"].emplace_back(receivedData);
    }

    restart();

    s << std::setw(4) << snapshot << std::endl;
}

static void importSnapshot(std::istream &s){
    json snapshot;

    s >> snapshot;

    halt();
    canonicalize();

    //PC
    request(WRITE, CORE_ID, 0, (uint512_t) ((uint64_t)snapshot["PC"]));

    //RF
    for(uint64_t i = 1; i < RF_SIZE; i++){
        request(WRITE, REGISTER_FILE_ID, (uint64_t) i, 0);
        snapshot["RegisterFile"].emplace_back((uint64_t)receivedData);
    }

    //MAIN MEMORY
    for(uint64_t i = 0; i < MAIN_MEM_SIZE; i++){
        request(WRITE, MAIN_MEM_ID, (uint64_t) i, 0);
        snapshot["MainMem"].emplace_back(receivedData);
    }

    // ...

    restart();
}



int main(int argc, const char **argv)
{
    long actualFrequency = 0;
    long requestedFrequency = 1e9 / MainClockPeriod;

    CoreIndication coreIndication(IfcNames_EchoIndicationH2S);
    coreRequestProxy = new CoreRequestProxy(IfcNames_EchoRequestS2H);

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
        snapshot["L1i"]["Tags"].emplace_back(receivedData);
    }

    // L1I DIRECT MAPPED CACHE FIELD = 1
    for(uint64_t address = 0; address < L1_SIZE; address++){
        request(READ, L1I_ID, 1 << 7 | address, 0);
        snapshot["L1i"]["State"].emplace_back(receivedData);
    }

    // L1I DIRECT MAPPED CACHE FIELD = 2
    for(uint64_t address = 0; address < L1_SIZE; address++){
        for(uint64_t slice = 0; slice < 8; slice++){
            request(READ, L1I_ID, slice << 9 | 2 << 7 | address, 0);
            snapshot["L1i"]["Data"][address].emplace_back(receivedData);
        }
    }

    // L1D DIRECT MAPPED CACHE FIELD = 0
    for(uint64_t address = 0; address < L1_SIZE; address++){
        request(READ, L1D_ID, 0 << 7 | address, 0);
        snapshot["L1d"]["Tags"].emplace_back(receivedData);
    }

    // L1D DIRECT MAPPED CACHE FIELD = 1
    for(uint64_t address = 0; address < L1_SIZE; address++){
        request(READ, L1D_ID, 1 << 7 | address, 0);
        snapshot["L1d"]["State"].emplace_back(receivedData);
    }

    // L1D DIRECT MAPPED CACHE FIELD = 2
    for(uint64_t address = 0; address < L1_SIZE; address++){
        for(uint64_t slice = 0; slice < 8; slice++){
            request(READ, L1D_ID, slice << 9 | 2 << 7 | address, 0);
            snapshot["L1d"]["Data"][address].emplace_back(receivedData);
        }
    }

    // L2 DIRECT MAPPED CACHE FIELD = 0
    for(uint64_t address = 0; address < L2_SIZE; address++){
        request(READ, L2_ID, 0 << 8 | address, 0);
        snapshot["L2"]["Tags"].emplace_back(receivedData);
    }

    // L2 DIRECT MAPPED CACHE FIELD = 1
    for(uint64_t address = 0; address < L2_SIZE; address++){
        request(READ, L2_ID, 1 << 8 | address, 0);
        snapshot["L2"]["State"].emplace_back(receivedData);
    }

    // L2 DIRECT MAPPED CACHE FIELD = 2
    for(uint64_t address = 0; address < L2_SIZE; address++){
        for(uint64_t slice = 0; slice < 8; slice++){
            request(READ, L2_ID, slice << 10 | 2 << 8 | address, 0);
            snapshot["L2"]["Data"][address].emplace_back(receivedData);
        }
    } */