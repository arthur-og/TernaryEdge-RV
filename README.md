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

However, deploying raw hardware in isolation is commercially unviable for IoT and Edge systems (e.g., nano-drones), which require networking and file system abstractions. Our research introduces a **Co-Design approach**: offloading the neural computation to the Ternary NPU while retaining a lightweight **LiteX-generated VexRiscv SoC** running an **Embedded Linux OS**. By utilizing a custom **Loadable Kernel Module (LKM)** with strict IRQ-driven Memory-Mapped I/O (MMIO), we eliminate CPU polling, allowing the system to sleep during inference. This proves that high-level OS abstraction can coexist with extreme hardware energy efficiency.

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
    subgraph UserSpace ["User Space (AI & Application)"]
        A[Python: QAT & Weight Extraction] -->|Generates weights.h| B(C App: user_app.c)
        B -->|POSIX read/write/ioctl| C
    end
    subgraph KernelSpace ["Kernel Space (OS & Driver)"]
        C[LKM: /dev/npu_ternaria] -->|copy_from_user| D{MMIO Translation: ioremap}
        D -->|Device Tree Mapping| E
    end
    subgraph HardwareSpace ["Hardware Space (FPGA/LiteX)"]
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

## 📊 Project Status (Active Development)

<!-- Status badges generated 2026-06-08 from git log analysis -->

| Domain | Lead | Phase | Status | Completion |
|:-------|:-----|:------|:-------|:-----------|
| **Hardware (RTL/SoC)** | Arthur | 2.5/4 | F1✅ F2✅ F3▶️ | ![60%](https://img.shields.io/badge/60%25-yellow) |
| **OS (Buildroot)** | Gildo | 2.25/4 | F1✅ F2✅ F3▶️ | ![55%](https://img.shields.io/badge/55%25-yellow) |
| **Kernel Driver** | Gustavo | 3.0/4 | F1✅ F2✅ F3✅ | ![90%](https://img.shields.io/badge/90%25-brightgreen) |
| **AI Pipeline** | Gilvan | 2.5/4 | F1✅ F2✅ F3▶️ | ![70%](https://img.shields.io/badge/70%25-yellowgreen) |

### Arthur (Hardware) — RTL Design & SoC Integration
- ✅ **Phase 1:** Official memory map defined (`0x40000000`, IRQ 10, Little-Endian). VexRiscv-RV32IMA base SoC. FPGA requirements documented.
- ✅ **Phase 2:** `ternary_mac.v` (multiplierless MAC: 0 DSPs). `npu_ternaria_top.v` (Wishbone slave + FSM + IRQ generator).
- ⏳ **Phase 3:** Pending: DMA controller (Wishbone master), layer sequencer, Verilator testbench.
- ⏳ **Blocked:** Physical FPGA (waiting for professor). See `hardware/litex_soc/requisitos_fpga.md`.

### Gildo (OS) — Buildroot & Device Tree
- ✅ **Phase 1:** Buildroot external tree created. RV32IMA defconfig (kernel 6.18, OpenSBI, QEMU).
- ✅ **Phase 2:** Toolchain exported (relocatable SDK on Google Drive). LKM and HIGH_RES_TIMERS enabled in kernel.
- ⏳ **Phase 3:** Official `.dts` with `0x40000000` + IRQ 10.
- ⏳ **Phase 4 (future):** FAT32/ext4 in RootFS. Flash image to SD Card.

### Gustavo (Driver) — Kernel Module (Zero-Copy DMA)
- 🚀 **Ahead of schedule:** Full platform driver with `dma_alloc_coherent`, `mmap`, `request_irq`, `wait_event_interruptible`.
- ✅ QEMU DT injection working. Tests performed without FPGA.
- ✅ `software/include/npu_ioctl.h` and `dummy_app.c` created.
- ✅ **RISC-V toolchain available** via Google Drive. `.ko` compilation unblocked.

### Gilvan (AI) — QAT & Weight Export
- ✅ **Phase 1-2:** Full QAT pipeline (Larq + STE). 3 ternary layers (784→1024→512→256). L1 sparsity active. Fake quant INT8 between layers.
- ✅ `weights.h` generated with 3 layers (91,136 uint32_t words = 364 KB).
- ⚠️ **Gap:** Output layer is FP32 (softmax), not ternary — current hardware does not support it.
- ⏳ **Pending:** Real `user_app.c` with complete forward pass and segregated time measurement.

### Known Gaps
| Gap | Owner | Priority |
|:----|:------|:---------|
| Output layer FP32 (non-ternary) vs hardware | Gilvan / Arthur | **High** |
| No physical FPGA for synthesis | Arthur | **High** |
| DMA master not implemented in RTL | Arthur | **High** |
| No Verilator testbench | Arthur | **Medium** |

---

## 🚀 Getting Started (Simulation & Deployment)

*(Detailed phase-by-phase execution instructions are located in the respective subdirectories).*

### 1. Prerequisites
* **Hardware:** Vivado/Quartus toolchains, LiteX environment, Verilator (for simulation).
* **Software:** Buildroot, 32-bit RISC-V Cross-Compiler (`riscv32-buildroot-linux-gnu-gcc` or multilib equivalent targeting `rv32ima`), QEMU.
* **AI:** Python 3.10+, TensorFlow 2.17+, Larq 0.13+.

### 2. Quick Workflow
1. **Train Model:** Run the Python pipeline in `ai_training/` to generate `weights.h`.
2. **Build OS:** Compile the Buildroot environment in `software/os_buildroot/` to generate the RootFS and Toolchain.
3. **Compile App & Driver:** Cross-compile the LKM in `software/npu_driver/` and the user application.
4. **Hardware Synthesis:** Generate the bitstream using LiteX in `hardware/` and flash your target FPGA.
5. **Run Inference:** Boot Linux on the FPGA, load the driver (`insmod`), and execute the benchmark application.

### 3. AI Pipeline (ai_training/)

The AI pipeline uses **Larq** for Quantization-Aware Training with the Straight-Through Estimator (STE), producing strictly ternary weights `{-1, 0, +1}` — no scaling factors, ensuring true multiplierless hardware.

```bash
# Run the full pipeline (train -> validate -> pack -> export)
cd ai_training
.venv/Scripts/python.exe scripts/run_pipeline.py

# Or skip training if you have a saved model
.venv/Scripts/python.exe scripts/run_pipeline.py --skip-train

# Adjust training hyperparameters
.venv/Scripts/python.exe scripts/run_pipeline.py --epochs 30 --lr 5e-4
```

| Script | Purpose |
|---|---|
| `train_qat_mnist.py` | Standalone QAT training with Larq `ste_tern` quantizer |
| `pack_weights.py` | Utility: pack 16 ternary weights into a single `uint32_t` |
| `generate_weights_h.py` | Generate C header `weights.h` from trained model |
| `run_pipeline.py` | **Unified pipeline**: train → validate → pack → export |
| `notebooks/qat_exploration.ipynb` | Interactive notebook for experimentation |

---

## 👥 The Team

This research project is collaboratively developed by:

* **Arthur Oliveira Gomes** - *Hardware Architecture & RTL Design* (LiteX, Verilog, SoC Generation)
* **Gildo Alves de Lima Junior** - *OS Infrastructure* (Buildroot, Kernel Configuration, Device Tree)
* **Gustavo Alexandre dos Santos** - *Kernel Driver Development* (LKM, MMIO, Hardware Synchronization)
* **Gilvan Alves Pastor Junior** - *Artificial Intelligence & User Space* (QAT, C Application, Benchmarking)

---

## 📝 Citation

If you find this repository useful for your research, please consider citing our upcoming paper:

```bibtex
@article{TernaryEdgeRV2026,
  title={Ternary Edge-RV: A Full-Stack Multiplierless Edge AI Accelerator on RISC-V},
  author={Arthur Oliveira Gomes and Gildo Alves de Lima Junior and Gustavo Alexandre dos Santos and Gilvan Alves Pastor Junior},
  journal={TBD},
  year={2026}
}
```

## 📄 License

This project is licensed under the MIT License - see the `LICENSE` file for details.
