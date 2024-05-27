#include <fstream>
#include <iostream>



void test1() {
    restart();

    while(halt_flag.load() == 1);

    halt();
    canonicalize();

    std::ofstream ofs("../snapshot/SecondSnapshot.json", std::ofstream::out);
    exportSnapshot(ofs);

    uint64_t fake_buffer[8] = {0};
    fake_buffer[0] = 1;

    request(WRITE, REGISTER_FILE_ID, 10, fake_buffer);

    restart();
}

void test2() {
    // read the JSON file (SecondSnapshotAgain.json)
    std::ifstream ifs("../snapshot/SecondSnapshot.json", std::ifstream::in);
    // import the snapshot to the server.
    importSnapshot(ifs);
    // Change the value of register 10 to 1.
    uint64_t fake_buffer[8] = {0};
    fake_buffer[0] = 1;
    request(WRITE, REGISTER_FILE_ID, 10, fake_buffer);
    // Restart the server.
    restart();
}

void test3() {
    std::ofstream ofs("../snapshot/ThirdSnapshot.json", std::ofstream::out);
    exportSnapshot(ofs);
    ofs.flush();
    ofs.close();

    std::ifstream ifs("../snapshot/ThirdSnapshot.json", std::ifstream::in);
    importSnapshot(ifs);

    restart();
}

void test4() {
    restart();

    while(halt_flag.load() == 1);

    halt();
    canonicalize();

    std::ofstream ofs("../snapshot/ForthSnapshot.json", std::ofstream::out);
    exportSnapshot(ofs);
    ofs.flush();
    ofs.close();

    // load the snapshot back immediately.
    std::ifstream ifs("../snapshot/ForthSnapshot.json", std::ifstream::in);
    importSnapshot(ifs);

    uint64_t fake_buffer[8] = {0};
    fake_buffer[0] = 1;

    request(WRITE, REGISTER_FILE_ID, 10, fake_buffer);

    restart();
}

void test5() {
    // read the JSON file (SecondSnapshotAgain.json)
    std::ifstream ifs("../snapshot/SecondSnapshot.json", std::ifstream::in);
    // import the snapshot to the server.
    importSnapshot(ifs);
    std::ofstream ofs("../snapshot/SecondSnapshotComparison.json", std::ofstream::out);
    exportSnapshot(ofs);
    ofs.flush();
    ofs.close();
    // Change the value of register 10 to 1.
    uint64_t fake_buffer[8] = {0};
    fake_buffer[0] = 1;
    request(WRITE, REGISTER_FILE_ID, 10, fake_buffer);
    // Restart the server.
    restart();
}

void test6() {
    restart();

    // fflush(stdin);
    getchar(); // remove the enter
    getchar();

    halt();
    canonicalize();

    std::ofstream ofs("../snapshot/SixthSnapshot.json", std::ofstream::out);
    exportSnapshot(ofs);
    ofs.flush();
    ofs.close();

    restart();
}

void test7() {
    // load the snapshot of SixthSnapshot.json and restart.
    std::ifstream ifs("../snapshot/SixthSnapshot.json", std::ifstream::in);
    importSnapshot(ifs);

    restart();
}