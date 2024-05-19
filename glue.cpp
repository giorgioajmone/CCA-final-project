#include <errno.h>
#include <stdio.h>
#include <semaphore.h>
#include <cstdint>

#include "json.hpp"
#include <boost/multiprecision/cpp_int.hpp>

using json = nlohmann::json;
using namespace boost::multiprecision;

#define CORE_ID 0
#define MAIN_MEM_ID 4
#define RF_SIZE 32
#define MAIN_MEM_SIZE 65536

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
        request(READ, CORE_ID, (uint64_t) i, 0);
        snapshot["RegisterFile"].emplace_back((uint64_t)receivedData);
    }

    //MAIN MEMORY
    for(uint64_t i = 0; i < MAIN_MEM_SIZE; i++){
        request(READ, MAIN_MEM_ID, (uint64_t) i, 0);
        snapshot["MainMem"].emplace_back(receivedData);
    }

    // ...

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
        request(READ, CORE_ID, (uint64_t) i, 0);
        snapshot["RegisterFile"].emplace_back((uint64_t)receivedData);
    }

    //MAIN MEMORY
    for(uint64_t i = 0; i < MAIN_MEM_SIZE; i++){
        request(READ, MAIN_MEM_ID, (uint64_t) i, 0);
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