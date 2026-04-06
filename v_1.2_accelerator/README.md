# Hardware Accelerator Integration for Hornet Core (v1.2)

![Status](https://img.shields.io/badge/Status-Under%20Development-yellow)
![Hardware](https://img.shields.io/badge/Target-Nexys%20Video%20(Artix--7)-blue)
![ISA](https://img.shields.io/badge/ISA-RV32IMF-orange)

> ⚠️ **DEVELOPMENT STATUS: WORK IN PROGRESS** ⚠️  
> **This directory is currently under active development.** The source files (`src/` directory) and documentation are frequently being updated. Future commits will include the completed RTL sources, logs, a dedicated driver for the accelerator, and extended test suites. 

**Version 1.2 focuses on accelerating the C-based MLP inference engine by integrating a dedicated Hardware Accelerator onto the Wishbone bus.**

---

## 📖 Table of Contents
- [Hardware Accelerator Integration for Hornet Core (v1.2)](#hardware-accelerator-integration-for-hornet-core-v12)
  - [📖 Table of Contents](#-table-of-contents)
  - [🚀 About This Version](#-about-this-version)
  - [📂 Directory Structure](#-directory-structure)
  - [🚧 Planned Features \& Future Work](#-planned-features--future-work)
  - [🛠 Prerequisites \& Toolchain](#-prerequisites--toolchain)
  - [👥 Team](#-team)

---

## 🚀 About This Version
While `v_1.0_stable` proved the feasibility of running a C-based MLP inference on our custom RISC-V core, `v_1.2_accelerator` aims to offload heavy computational workloads (such as MAC operations) to a dedicated hardware accelerator. This directory contains the initial drivers, firmware tests, and weight extraction scripts required to interface the Hornet core with the new hardware block via the Wishbone interconnect.

---

## 📂 Directory Structure

Below is the current layout of the `v_1.2_accelerator` directory:

```text
.
├── drivers/                   # Peripheral and bus interface drivers
│   ├── gpio.c / .h            # General Purpose I/O drivers
│   ├── irq.c / .h             # Interrupt Request handling
│   └── uart.c / .h            # Universal Asynchronous Receiver-Transmitter
│
├── src/                       # Hardware RTL and Core Sources
│
├── test/                      # Firmware test suites for hardware validation
│   ├── Accelerator_while_test/# Tests the processor's polling/interaction with the accelerator
│   ├── Wishbone_Write_test/   # Validates Wishbone bus write transactions to the accelerator
│   ├── rom_generator/         # Utility to package compiled ELFs into memory initialization files
│   ├── crt0.s                 # C runtime startup code
│   └── linksc.ld              # Linker script for the RV32IMF architecture
│
└── weight_bias_extraction/    # Model data and initialization scripts
    ├── bias_init.mem          # Extracted biases for hardware memory initialization
    ├── weight_init.mem        # Extracted weights for hardware memory initialization
    ├── KDDTest+.csv           # NSL-KDD Testing dataset
    ├── KDDTrain+.csv          # NSL-KDD Training dataset
    └── MLP_No_Batch.ipynb     # Jupyter Notebook for model training and extraction
```

*(Note: The `src/` directory is currently empty in this tree but will be populated with the RTL sources in upcoming commits.)*

---

## 🚧 Planned Features & Future Work

Because this branch is an active construction zone, several components are slated for upcoming releases:

* **Accelerator Driver:** A dedicated C driver (e.g., `accelerator.c`/`.h`) will be added to the `drivers/` folder to manage data transfers, handshaking, and interrupt handling for the hardware accelerator.
* **Extended Test Suites:** New tests will be introduced to validate the accelerator and drivers.
* **Logging System Updates:** Enhanced UART logging mechanisms to profile execution time and compare clock cycles between software-only inference and hardware-accelerated inference.
* **RTL Source Integration:** The `src/` folder will be updated with the complete SystemVerilog/Verilog source tree for the accelerator and the modified Wishbone wrapper.

---

## 🛠 Prerequisites & Toolchain

The requirements remain largely identical to the `v_1.0_stable` branch, with an emphasis on testing tools for the newly generated `.mem` and `.bin` files.

* **RISC-V GCC:** `15.1.0` (rv32imf-unknown-elf) for compiling the tests in the `test/` directory.
* **Make:** Required to build the test binaries using the provided `Makefiles`.
* **Python/Jupyter:** Required to run `MLP_No_Batch.ipynb` for weight and bias extraction.

---

## 👥 Team

This sub-module is being developed as part of the overall Hornet core architecture at Istanbul Technical University (ITU).

* **Yusuf Tekin** ([tekiny20@itu.edu.tr](mailto:tekiny20@itu.edu.tr)) - *Software/Hardware Design of The Accelerator*