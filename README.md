# Ternary Edge-RV: Full-Stack Multiplierless Edge AI Accelerator

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Architecture: RISC-V](https://img.shields.io/badge/Architecture-RISC--V%20(RV32IMA)-blue.svg)]()
[![OS: Linux](https://img.shields.io/badge/OS-Embedded%20Linux-lightgrey.svg)]()
[![Status: Active](https://img.shields.io/badge/Status-Active%20Research-success.svg)]()

**Ternary Edge-RV** is a complete hardware-software co-design project aimed at achieving extreme energy efficiency for Edge Artificial Intelligence. This repository contains the full stack—from custom silicon architecture to the AI application—demonstrating a multiplierless Ternary Neural Network (TNN) accelerator integrated into a Linux-capable RISC-V System-on-Chip (SoC).

This project is currently under active development for academic publication. It aims to prove that inferencing heavily quantized models ($\in \{-1, 0, 1\}$) on custom hardware without DSPs significantly outperforms CPU-bound execution in both latency and power consumption.

---

## 🎯 Project Overview & Academic Contribution

Traditional AI inference relies heavily on power-hungry floating-point Multiply-Accumulate (MAC) operations. **Ternary Edge-RV** entirely eliminates the need for hardware multipliers. 

By leveraging **Quantization-Aware Training (QAT)** and the **Straight-Through Estimator (STE)**, we constrain neural network weights to ternary values (-1, 0, 1). This mathematical simplification allows our custom Neural Processing Unit (NPU) to perform convolutions and dense layer operations using only basic adders, subtractors, and multiplexers. 

The system is deployed on an FPGA using a **LiteX-generated VexRiscv SoC**, communicating with an **Embedded Linux OS** via a custom **Loadable Kernel Module (LKM)** using Memory-Mapped I/O (MMIO).

### Key Innovations
* **Multiplierless Hardware:** Zero DSP blocks utilized. Inference is achieved strictly through addition, subtraction, and zero-skipping (sparsity optimization).
* **Custom Linux Kernel Driver:** Seamless User-Space to Kernel-Space bridging using custom `.ko` modules with high-resolution hardware interrupt (IRQ) synchronization, completely eliminating CPU polling overhead.
* **Full-Stack Benchmarking:** Integrated `<sys/time.h>` profiling to directly compare hardware-accelerated latency against software-only CPU execution on the same SoC.
* **Automated AI Pipeline:** A Python-based QAT pipeline that automatically packs 2-bit ternary weights into highly efficient 32-bit headers for execution in C.

---

## 🏗️ System Architecture

The project is divided into four interdependent domains, bridging user applications down to the physical hardware:

```mermaid
graph TD
    subgraph User Space (AI & Application)
        A[Python: QAT & Weight Extraction] -->|Generates weights.h| B(C App: user_app.c)
        B -->|POSIX read/write/ioctl| C
    end
    subgraph Kernel Space (OS & Driver)
        C[LKM: /dev/npu_ternaria] -->|copy_from_user| D{MMIO Translation: ioremap}
        D -->|Device Tree Mapping| E
    end
    subgraph Hardware Space (FPGA/LiteX)
        E[Wishbone/AXI Bus] --> F[LiteX SoC: VexRiscv RV32IMA]
        E --> G[Ternary NPU: Multiplierless RTL]
    end
```

---

## 📂 Repository Structure

The repository is organized by domain to ensure a clear separation of concerns:

```text
TernaryEdge-RV/
├── docs/                   # Internal documentation, architecture specs, and planning
├── hardware/               # Hardware Engineering
│   ├── litex_soc/          # Python scripts for VexRiscv SoC generation via LiteX
│   └── npu_rtl/            # Verilog/VHDL source for the Ternary NPU and Testbenches
├── software/               # OS and Driver Stack
│   ├── os_buildroot/       # Buildroot configs, Patches, U-Boot, and Device Tree (.dts)
│   ├── npu_driver/         # LKM C source code, file_operations, and MMIO mapping
│   └── user_app/           # User-space C application for inference and benchmarking
├── ai_training/            # AI & Quantization Pipeline
│   ├── notebooks/          # QAT exploration and model training (Larq/Brevitas)
│   └── scripts/            # Automated extraction and weight packing (uint32_t)
└── paper/                  # LaTeX source code, benchmark graphs, and references
```

---

## 📊 Preliminary Results & Benchmarks

*(This section will be updated with final graphs and tables upon project completion.)*

| Execution Mode | Latency (ms) | Power Estimation (mW) | Accuracy (%) |
| :--- | :--- | :--- | :--- |
| **CPU Only (Software)** | TBD | TBD | TBD |
| **Ternary NPU (Hardware)** | TBD | TBD | TBD |

---

## 🚀 Getting Started (Simulation & Deployment)

*(Detailed phase-by-phase execution instructions are located in the respective subdirectories).*

### 1. Prerequisites
* **Hardware:** Vivado/Quartus toolchains, LiteX environment, Verilator (for simulation).
* **Software:** Buildroot, 32-bit RISC-V Cross-Compiler (`riscv32-buildroot-linux-gnu-gcc` or multilib equivalent targeting `rv32ima`), QEMU.
* **AI:** Python 3.10+, PyTorch, Larq / Brevitas.

### 2. Quick Workflow
1. **Train Model:** Run the Python pipeline in `ai_training/` to generate `weights.h`.
2. **Build OS:** Compile the Buildroot environment in `software/os_buildroot/` to generate the RootFS and Toolchain.
3. **Compile App & Driver:** Cross-compile the LKM in `software/npu_driver/` and the user application.
4. **Hardware Synthesis:** Generate the bitstream using LiteX in `hardware/` and flash your target FPGA.
5. **Run Inference:** Boot Linux on the FPGA, load the driver (`insmod`), and execute the benchmark application.

---

## 👥 The Team

This research project is collaboratively developed by:

* **Arthur** - *Hardware Architecture & RTL Design* (LiteX, Verilog, SoC Generation)
* **Gildo** - *OS Infrastructure* (Buildroot, Kernel Configuration, Device Tree)
* **Gustavo** - *Kernel Driver Development* (LKM, MMIO, Hardware Synchronization)
* **Gilvan** - *Artificial Intelligence & User Space* (QAT, C Application, Benchmarking)

---

## 📝 Citation

If you find this repository useful for your research, please consider citing our upcoming paper:

```bibtex
@article{TernaryEdgeRV2026,
  title={Ternary Edge-RV: A Full-Stack Multiplierless Edge AI Accelerator on RISC-V},
  author={[Team Names]},
  journal={TBD},
  year={2026}
}
```

## 📄 License

This project is licensed under the MIT License - see the `LICENSE` file for details.
