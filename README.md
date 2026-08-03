# Ternary Edge-RV: Full-Stack Multiplierless Edge AI Accelerator

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Architecture: RISC-V](https://img.shields.io/badge/Architecture-RISC--V%20(RV32IMA)-blue.svg)]()
[![OS: Linux](https://img.shields.io/badge/OS-Embedded%20Linux-lightgrey.svg)]()
[![Status: Active](https://img.shields.io/badge/Status-Active%20Research-success.svg)]()
[![Paper 1](https://img.shields.io/badge/Paper-SBCCI%2FLASCAS%20Template-blueviolet.svg)](paper/paper1_template.tex)

**Ternary Edge-RV** is a complete hardware-software co-design project aimed at achieving extreme energy efficiency for Edge Artificial Intelligence. This repository contains the full stack—from custom silicon architecture to the AI application—demonstrating a multiplierless Ternary Neural Network (TNN) accelerator integrated into a Linux-capable RISC-V System-on-Chip (SoC).

This project is currently under active development for academic publication (Paper 1 — target: SBCCI/LASCAS). The paper template is available at [`paper/paper1_template.tex`](paper/paper1_template.tex). It aims to prove that inferencing heavily quantized models ($\in \{-1, 0, 1\}$) on custom hardware without DSPs significantly outperforms CPU-bound execution in both latency and power consumption.

---

## 🎯 Project Overview & Academic Contribution

Traditional AI inference relies heavily on power-hungry floating-point Multiply-Accumulate (MAC) operations. **Ternary Edge-RV** entirely eliminates the need for hardware multipliers. 

By leveraging **Quantization-Aware Training (QAT)** and the **Straight-Through Estimator (STE)**, we constrain neural network weights to ternary values (-1, 0, 1). This mathematical simplification allows our custom Neural Processing Unit (NPU) to perform convolutions and dense layer operations using only basic adders, subtractors, and multiplexers. 

However, deploying raw hardware in isolation is commercially unviable for IoT and Edge systems (e.g., nano-drones), which require networking and file system abstractions. Our research introduces a **Co-Design approach**: offloading the neural computation to the Ternary NPU while retaining a lightweight **LiteX-generated VexRiscv SoC** running an **Embedded Linux OS**. By utilizing a custom **Loadable Kernel Module (LKM)** with strict IRQ-driven Memory-Mapped I/O (MMIO), we eliminate CPU polling, allowing the system to sleep during inference. This proves that high-level OS abstraction can coexist with extreme hardware energy efficiency.

### Key Innovations
* **Multiplierless Hardware:** Zero DSP blocks utilized. Inference is achieved strictly through addition, subtraction, and zero-skipping (sparsity optimization).
* **NPU HAL Layer:** A Hardware Abstraction Layer that bridges the kernel driver and user application, encapsulating DMA buffer management, weight loading, and CPU-based output layer classification (256→10 FP32).
* **Custom Linux Kernel Driver:** Seamless User-Space to Kernel-Space bridging using custom `.ko` modules with high-resolution hardware interrupt (IRQ) synchronization, completely eliminating CPU polling overhead.
* **Full-Stack Benchmarking:** Integrated `<sys/time.h>` profiling to directly compare hardware-accelerated latency against software-only CPU execution on the same SoC.
* **Automated AI Pipeline:** A Python-based QAT pipeline that automatically packs 2-bit ternary weights into highly efficient 32-bit headers for execution in C.

---

## 🏗️ System Architecture

The project is divided into **five** interdependent layers, bridging the AI application down to the physical hardware:

```mermaid
graph TD
    subgraph UserSpace ["User Space"]
        A[user_app: Inference & Benchmark]
        B[NPU HAL: init, predict, deinit]
        A -->|calls| B
    end
    subgraph KernelSpace ["Kernel Space"]
        C[npu_driver: /dev/npu_ternaria]
        B -->|ioctl / mmap| C
        C -->|iowrite32| D[NPU Registers @ 0x40000000]
    end
    subgraph HardwareSpace ["Hardware Space"]
        D --> E[LiteX SoC: VexRiscv RV32IMA]
        D --> F[NPU v2: 64 MACs multiplierless + Wishbone DMA]
    end
    subgraph AIPipeline ["AI Pipeline (host)"]
        G[Python QAT Training] -->|weights.h| B
    end
```

### Why a HAL?

The NPU v2 is **purely ternary** — it only computes {+1, 0, -1} × INT8 multiplications. The final classification layer (256→10) requires FP32 weights and softmax, which must run on the CPU. The HAL encapsulates this complexity, presenting a clean `npu_init()` → `npu_predict()` → `npu_deinit()` interface to the application.

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
│   ├── npu_hal/            # NPU HAL: init, load_weights, predict, classifier, weights
│   └── user_app/           # User-space C application using the HAL API
├── ai_training/            # AI & Quantization Pipeline
│   ├── notebooks/          # QAT exploration and model training (Larq/Brevitas)
│   └── scripts/            # Automated extraction and weight packing (uint32_t)
└── paper/                  # LaTeX source code, benchmark graphs, and references
```

---

## 📊 Project Status (Active Development)

<!-- Status updated when Gildo completed Phase 3: HAL + Classifier + Buildroot packages -->

| Domain | Lead | Phase | Status | Completion |
|:-------|:-----|:------|:-------|:-----------|
| **Hardware (RTL/SoC)** | Arthur | 3.5/4 | F1✅ F2✅ F3✅ (NPU v2 done) | ![95%](https://img.shields.io/badge/95%25-brightgreen) |
| **OS + HAL (Buildroot + Classifier)** | Gildo | 3.5/4 | F1✅ F2✅ F3✅ (HAL/Classifier/packages) | ![95%](https://img.shields.io/badge/95%25-brightgreen) |
| **Kernel Driver** | Gustavo | 3.5/4 | F1✅ F2✅ F3✅ (v2 adapted) | ![95%](https://img.shields.io/badge/95%25-brightgreen) |
| **AI Pipeline** | Gilvan | 3.0/4 | F1✅ F2✅ F3✅ (weights + golden) | ![85%](https://img.shields.io/badge/85%25-green) |

### Arthur (Hardware) — NPU v2: 64 MACs + Wishbone Master DMA
- ✅ **Phase 1:** Official memory map defined (`0x40000000`, IRQ 10, Little-Endian). VexRiscv-RV32IMA base SoC.
- ✅ **Phase 2:** `ternary_mac.v` (multiplierless MAC: 0 DSPs). `npu_ternaria_top.v` v1 (Wishbone slave + FSM + IRQ).
- ✅ **Phase 3 — NPU v2 COMPLETE:**
  - ✅ 64 MAC array (`ternary_mac_array.v`) + 6-stage pipelined adder tree (`adder_tree_64.v`)
  - ✅ Wishbone Master DMA controller (`wishbone_master.v`) — burst reads, classic handshake
  - ✅ 12K-word weight BRAM + 1K activation buffer (`npu_v2_pkg.v`)
  - ✅ Hardware Layer Sequencer — FSM 10 estados, 3 layers (784→1024→512→256)
  - ✅ Verilog testbench (`tb_npu_v2.v`) — RAM simulada, testes registrador/IRQ/STATUS
  - ✅ STATUS register `zero_counter` at bits `[15:8]` — alinhado C++/RTL
  - ✅ Golden Model C++ v2 — 21/21 testes passando
  - ✅ SoC base updated: `base_soc.py` with NPU v2 wrapper, IRQ 10, Wishbone slave + master
  - ✅ Device Tree for real FPGA: `urrbana.dts`
- ⏳ FPGA confirmed by the professor (E2). Bitstream target for Phase 4.

### Gildo (OS + HAL) — Buildroot, Device Tree, NPU HAL, Classifier

**Scope expansion:** Gildo is now responsible for the NPU HAL and Classifier — the software layer that completes the NPU (the simpler the hardware, the more complex the software).

- ✅ **Phase 1:** Buildroot external tree. RV32IMA defconfig. QEMU boot.
- ✅ **Phase 2:** Toolchain via `make sdk`.
- ✅ **Phase 3 — Infrastructure:**
  - ✅ Official `.dts` (QEMU + FPGA) — `compatible = "ternaryedge,npu-ternaria"`, IRQ=10, RV32IMA
  - ✅ `CONFIG_HIGH_RES_TIMERS=y` — kernel config fragment (`configs/kernel-npu.cfg`)
  - ✅ FAT32/ext4 in RootFS — via `BR2_PACKAGE_DOSFSTOOLS`, `e2fspogs`, `CONFIG_FAT_FS`, `CONFIG_EXT4_FS`
  - ✅ Structured `Config.in`, `external.mk`, `external.desc`
  - ✅ **NPU HAL + Classifier + Buildroot Packages COMPLETE:**
    - ✅ `npu_hal.h` / `npu_hal.c` — API and implementation (init, load_weights, predict, batch, deinit)
    - ✅ `npu_classifier.c` — Output layer 256->10 CPU (FP32: score, argmax, softmax)
    - ✅ `npu_weights.c` — Weights loader from the QAT pipeline
    - ✅ `weights.h` stub + `npu_ioctl.h` fixed for user-space (`#ifdef __KERNEL__`)
    - ✅ Buildroot packages (npu-ternaria, npu-hal, user-app) + `Config.in`/`external.mk`/`defconfig`
    - ✅ `user_app.c` refactored: HAL API + `--cpu`, `--file`, `--batch` flags
  - ✅ `libnpu_hal.a` built and validated (native)

### Gustavo (Driver) — Adapted for NPU v2 ✅
- ✅ Platform driver with `dma_alloc_coherent`, `mmap`, `request_irq`, `wait_event_interruptible`.
- ✅ **NPU v2 adaptation COMPLETE (npu_driver.c v3.0):**
  - ✅ Offsets revised (10 registers, 0x00–0x24)
  - ✅ `iowrite32()` for WEIGHT_CFG + ACT_CFG + MAC_CFG + LAYER_CFG
  - ✅ IOCTL with struct `npu_ioctl_args` (5 configuration fields)
  - ✅ IOCTL header compartilhado: `software/include/npu_ioctl.h`

### Gilvan (AI) — Golden Model + weights.h ✅
- ✅ QAT pipeline (Larq + STE). 3 ternary layers. weights.h gerado.
- ✅ Golden Model C++ v2: 21/21 testes (64 MACs, DMA, Layer Sequencer)
- ✅ Output layer validada: Opção B (CPU fallback) adotada
- ✅ weights.h in a format compatible with the HAL (per-layer arrays + FP32 output)

> The `user_app.c` was transferred to Gildo, who refactored it to use the HAL.

### Known Gaps
| Gap | Owner | Priority |
|:----|:------|:---------|
| No physical FPGA yet | Arthur + Professor | **High** |
| Toolchain not built by all members | Team | **High** |

---

## 🚀 Getting Started (Simulation & Deployment)

*(Detailed phase-by-phase execution instructions are located in the respective subdirectories).*

### 1. Prerequisites
* **Hardware:** Vivado/Quartus toolchains, LiteX environment, Verilator (for simulation).
* **Software:** Buildroot, 32-bit RISC-V Cross-Compiler (`riscv32-buildroot-linux-gnu-gcc`), QEMU.
* **AI:** Python 3.10+, TensorFlow 2.17+, Larq 0.13+.

### 2. Quick Workflow
1. **Train Model:** Run the Python pipeline in `ai_training/` to generate `weights.h`.
2. **Build OS:** Compile the Buildroot environment in `software/os_buildroot/` to generate the RootFS and Toolchain.
3. **Build HAL + user_app:** Cross-compile the NPU HAL and user application.
4. **Compile Driver:** Cross-compile the LKM in `software/npu_driver/`.
5. **Hardware Synthesis:** Generate the bitstream using LiteX in `hardware/` and flash your target FPGA.
6. **Run Inference:** Boot Linux on the FPGA, load the driver (`insmod`), and execute the benchmark application.

### 3. Software Stack Architecture

```
user_app (inference + benchmark)
    │
    ▼  (uses)
NPU HAL (npu_init → npu_predict → npu_deinit)
    │  └─ npu_classifier (256→10 output layer)
    │  └─ npu_weights (weight loading)
    │
    ▼  (ioctl / mmap)
npu_driver (/dev/npu_ternaria, IRQ, DMA)
    │
    ▼  (Wishbone bus)
NPU v2 hardware (64 MACs, Layer Sequencer)
```

### 4. AI Pipeline (ai_training/)

The AI pipeline uses **Larq** for Quantization-Aware Training with the Straight-Through Estimator (STE), producing strictly ternary weights `{-1, 0, +1}`.

```bash
# Run the full pipeline (train -> validate -> pack -> export)
cd ai_training
python3 scripts/run_pipeline.py
```

The pipeline generates `weights.h` with the format expected by the NPU HAL:
- `quant_dense_weights[50176]` — Layer 0 (784→1024)
- `quant_dense_1_weights[32768]` — Layer 1 (1024→512)
- `quant_dense_2_weights[8192]` — Layer 2 (512→256)
- `output_weights[2560]` — Output layer FP32 (256×10)
- `output_biases[10]` — Output layer bias

---

## 👥 The Team

This research project is collaboratively developed by:

* **Arthur Oliveira Gomes** - *Hardware Architecture & RTL Design* (LiteX, Verilog, SoC Generation)
* **Gildo Alves de Lima Junior** - *OS Infrastructure & NPU HAL* (Buildroot, Device Tree, HAL, Classifier, Buildroot Packages)
* **Gustavo Alexandre dos Santos** - *Kernel Driver Development* (LKM, MMIO, Hardware Synchronization)
* **Gilvan Alves Pastor Junior** - *Artificial Intelligence & Golden Model* (QAT, C++ Simulation, Benchmark Data)

---

## 📝 Citation

If you find this repository useful for your research, please consider citing our upcoming paper. The Paper 1 LaTeX template with full author list and section outline is at [`paper/paper1_template.tex`](paper/paper1_template.tex).

```bibtex
@article{TernaryEdgeRV2026,
  title={Ternary Edge-RV: A Multiplierless Ternary Neural Network Accelerator for RISC-V Linux Systems},
  author={Arthur Oliveira Gomes and Gildo Alves de Lima Junior and Gustavo Alexandre dos Santos and Gilvan Alves Pastor Junior},
  journal={TBD (SBCCI/LASCAS)},
  year={2026}
}
```

## 📄 License

This project is licensed under the MIT License - see the `LICENSE` file for details.
