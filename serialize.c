#include <stdint.h>
#include <stdlib.h>
#include <stdio.h>

void host2hardware(uint64_t input[8], uint32_t output[16]) {
    for (int index = 0; index < 8; ++index) {
        output[2*index] = (input[8 - index - 1] >> 32) & 0xFFFFFFFF;
        output[2*index + 1] = input[8- index - 1] & 0xFFFFFFFF;
    }
}

void hardware2host(uint32_t input[16], uint64_t output[8]) {
    for (int index = 0; index < 8; ++index) {
        output[8 - index - 1] = ((uint64_t)(input[2*index]) << 32) | (uint64_t)(input[2*index + 1]);
    }
}


int main() {
    // create an array with uint32_t as the hardware output. Using rand to fill it. 
    uint32_t hardware_output[16];
    for (int index = 0; index < 16; ++index) {
        hardware_output[index] = rand();
    }

    // convert the hardware output to host output.
    uint64_t host_output[8];
    hardware2host(hardware_output, host_output);

    // convert it back, and they should be the same.
    uint32_t hardware_output2[16];
    host2hardware(host_output, hardware_output2);

    for (int index = 0; index < 16; ++index) {
        if (hardware_output[index] != hardware_output2[index]) {
            return 1;
        }
    }

    // print the host output.
    for (int index = 0; index < 8; ++index) {
        printf("%016lx\n", host_output[index]);
    }

    return 0;
}