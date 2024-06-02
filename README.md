# Crossing the Line

This project contains a snapshotable in-order processor with configurable L1i, L1d, and L2 cache. 

This project is a course project of CS-629 at EPFL, and a joint effort of the following contributors:
- Giorgio Ajmone
- Shanqing Lin
- Ayan Chakraborty

## Quick Start

#### Environment Setup

First, you need to install Bluespec and Bluespec contribe libraries. You can find the installation instructions:
- [Bluespec](https://github.com/B-Lang-org/bsc)
- [Bluespec Contrib](https://github.com/B-Lang-org/bsc-contrib)

Then, you need to install the Connectal framework, which provides the interface between the Bluespec hardware the the host machine. You can find the installation instructions [here](https://github.com/search?q=Connectal&type=repositories). 

If you are using a newer version of GCC, you need to turn off the `strict` mode in the Connectal Makefile, so that it does not treat all compilation warning as errors. Modify line 279 in the `Makefile.connectal` under the Connectal root directory with the `--nonstrict` flag as follows:

```makefile
    $(CONNECTALFLAGS) $(BSVFILES) $(GENTOP) $(PRINTF_EXTRA) $(VERBOSE_SWITCH) --nonstrict
```

Connectal is refereneced in the `Makefile` in the root directory of this project. You are strongly recommeded to modify the `CONNECTALDIR` variable to point to the Connectal root directory.

#### Compile

The project follows the same convention as the Connectal framework. 

To compile the project inside the simulator (e.g., Bluesim), simply run the following command:

```bash
make build.bluesim
```

You can also compile the project for the FPGA. We only test our design under a very low frequency (20MHz). To do that, run the following command:

```bash
make -f Makefile.fpga build.<fpga_name>
```

#### Workload Preparation

Before running, you need to prepare the memory content of the processor, i.e., the workload. We reuse the workload from the course, and you can find the them in the `workload` directory. 
To compile all workloads, go to the `test` directory under the `workload` directory, and run the following command:

```bash
make
```

To pick one workload to generate its DRAM content, go to its parent directory, and run the following command:

```bash
./test.sh <workload_name>32
```

It will generate `mem.vmh` and `memlines.vmh` files in the same directory. They contain the code and the data sections of the workload.

#### Run

You need to copy the `mem.vmh` and `memlines.vmh` files to the project folder, so that they can be loaded by the generated binary. You are also required to copy the `zero*.vmh` files from the `workload` directory to the project folder. They are used to initialize the BRAM used by the caches:

```bash
    cp workloads/*.vmh .
```

To run the project, run the following command:

```bash
    ./"<bluesim or fpga_name>"/bin/ubuntu.exe
```

After the program is initialized, you should be able to see the prompt. Initially, the processor is halted. To run the workload you generated, simply type `r`.

#### Load and Save Snapshot

You can save the snapshot of the processor by typing `s` in the prompt, then the program will ask the path to put the snapshot json file. You can load the snapshot by typing `l`, then the program will ask the path to the snapshot json file. We provided some snapshot files in the `snapshots` directory for you to test.

## Motivation

## Design

