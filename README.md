# Ternary Edge-RV: Full-Stack Multiplierless Edge AI Accelerator

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Architecture: RISC-V](https://img.shields.io/badge/Architecture-RISC--V%20(RV32IMA)-blue.svg)]()
[![OS: Linux](https://img.shields.io/badge/OS-Embedded%20Linux-lightgrey.svg)]()
[![Status: Active](https://img.shields.io/badge/Status-Active%20Research-success.svg)]()
[![Paper 1](https://img.shields.io/badge/Paper-SBCCI%2FLASCAS%20Template-blueviolet.svg)](paper/paper1_template.tex)
[![FPGA: RealDigital Urbana](https://img.shields.io/badge/FPGA-RealDigital%20Urbana%20(Spartan--7%20XC7S50)-blue.svg)](http://www.realdigital.org/)

**Ternary Edge-RV** is a hardware-software co-design project aimed at studying energy-efficient Edge Artificial Intelligence. This repository contains the proposed full stack, from custom RTL and SoC architecture to the AI application, for a multiplierless Ternary Neural Network (TNN) accelerator targeted for integration into a Linux-capable RISC-V System-on-Chip (SoC).

This project is working toward **Phase 4: Physical Deployment and Paper 1** (target: SBCCI/LASCAS). The paper template is available at [`paper/paper1_template.tex`](paper/paper1_template.tex). The research question is whether heavily quantized models ($\in \{-1, 0, 1\}$) on custom hardware can improve latency and energy use relative to CPU execution; that comparison remains subject to physical measurement.

> **Current status (14/08/2026):** The RealDigital Urbana board (AMD Spartan-7 XC7S50-CSGA324, 128 MB DDR3, MicroSD) has been received. Current evidence is limited to source-level RTL audit, documented interfaces and C++ v2 host-side tests with 21/21 checks passing. RTL runtime, FPGA synthesis and bitstream, Linux boot, physical inference and performance or power measurements are pending. The current transition plan is [`docs/planejamento/direcionamento_pos_gilvan.md`](docs/planejamento/direcionamento_pos_gilvan.md), pending Professor Ramon and team confirmation.

---

## 🎯 Project Overview & Academic Contribution

Traditional AI inference relies heavily on power-hungry floating-point Multiply-Accumulate (MAC) operations. **Ternary Edge-RV** is designed to avoid hardware multipliers for ternary operations; synthesis and runtime evidence are still pending.

By using **Quantization-Aware Training (QAT)** and the **Straight-Through Estimator (STE)**, we constrain neural network weights to ternary values (-1, 0, 1). This mathematical simplification is intended to let the custom Neural Processing Unit (NPU) perform dense-layer operations using basic adders, subtractors, and multiplexers.

However, deploying raw hardware in isolation is commercially unviable for IoT and Edge systems (e.g., nano-drones), which require networking and file system abstractions. Our research proposes a **Co-Design approach**: offloading neural computation to a Ternary NPU while retaining a lightweight **LiteX-generated VexRiscv SoC** targeted to run an **Embedded Linux OS**. The documented integration uses IRQ-driven Memory-Mapped I/O (MMIO) and is intended to avoid CPU polling, but CPU sleep, latency, power, and energy benefits await runtime, synthesis, and physical measurement.

### Key Innovations
* **Multiplierless Hardware:** The source-level design and host-side model use addition, subtraction, multiplexing, and zero-skipping for ternary operations. Physical DSP utilization awaits synthesis and a resource report.
* **NPU HAL Layer:** A documented but incomplete Hardware Abstraction Layer intended to bridge the kernel driver and user application. DMA buffer management, weight loading, and CPU-based output classification still require end-to-end HAL, weights, and data-contract validation.
* **Custom Linux Kernel Driver:** Source-level User-Space to Kernel-Space interfaces use custom `.ko` modules, MMIO, and an IRQ path. Physical interrupt behavior and any reduction in CPU polling remain unverified.
* **Benchmarking Plan:** `<sys/time.h>` profiling and CPU versus NPU comparison paths are documented, but latency, throughput, power, and energy results await a validated physical run.
* **Automated AI Pipeline:** A Python-based QAT pipeline packs 2-bit ternary weights into 32-bit headers. Compatibility with the complete HAL contract remains pending.

---

## 🏗️ System Architecture

The proposed project stack connects the AI application to the target hardware through the documented software, hardware, and host-side pipeline components below:

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
        D --> F[NPU v2: proposed multiplierless array + Wishbone DMA]
    end
    subgraph AIPipeline ["AI Pipeline (host)"]
        G[Python QAT Training] -->|planned weights.h contract| B
    end
```

### Why a HAL?

The planned NPU v2 is **purely ternary** and is intended to compute {+1, 0, -1} × INT8 operations. The final classification layer (256→10) is documented as requiring FP32 weights and softmax on the CPU. The HAL exposes the intended `npu_init()` → `npu_predict()` → `npu_deinit()` interface, but its end-to-end contract with the exported weights and data transforms remains incomplete.

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
└── paper/                  # LaTeX source code, planned benchmark artifacts, and references
```

---

## 📊 Current Status (14/08/2026)

The current evidence boundary and the provisional post-Gilvan organization are maintained in [`docs/planejamento/direcionamento_pos_gilvan.md`](docs/planejamento/direcionamento_pos_gilvan.md). The ownership below is a proposal pending Professor Ramon and team confirmation. Completion percentages are intentionally omitted because synthesis, runtime and physical evidence are still pending.

| Domain | Operational ownership proposed | Current evidence or pending gate |
|:-------|:-------------------------------|:---------------------------------|
| **Hardware (RTL/SoC)** | Arthur, provisional | Source-level audit and documented interfaces; Verilog runtime, synthesis and bitstream pending |
| **Linux, Buildroot, driver integration, HAL and user-space** | Gildo, provisional | Software interfaces documented; physical image, boot and end-to-end integration pending |
| **AI pipeline, weights, golden model and benchmark methodology/results** | Gustavo, provisional | C++ v2 host-side 21/21 checks; export and physical benchmark evidence pending |
| **Paper 1** | Four authors, with operational tasks provisional | Draft template retained; measured results and final scope pending |

### Arthur (Hardware) — NPU v2 source-level design: 64-MAC modules + Wishbone Master DMA
- ✅ **Phase 1:** Official memory map defined (`0x40000000`, IRQ 10, Little-Endian). VexRiscv-RV32IMA base SoC.
- ✅ **Phase 2:** `ternary_mac.v` (source-level multiplierless MAC; physical DSP utilization not measured). `npu_ternaria_top.v` v1 (Wishbone slave + FSM + IRQ).
- ✅ **Phase 3 — NPU v2 source-level components:**
  - ✅ 64-MAC array module (`ternary_mac_array.v`) + 6-stage pipelined adder tree (`adder_tree_64.v`); active top-level integration and parallel hardware operation remain unverified
  - ✅ Wishbone Master DMA controller (`wishbone_master.v`) source-level module; runtime and synthesis remain pending
  - ✅ 12K-word weight BRAM + 1K activation buffer declarations (`npu_v2_pkg.v`); physical resource use awaits synthesis
  - ✅ Hardware Layer Sequencer source-level FSM, with 3 documented layers (784→1024→512→256)
  - ✅ Verilog testbench (`tb_npu_v2.v`) available; runtime execution pending
  - ✅ STATUS register `zero_counter` at bits `[15:8]` documented and aligned with the C++ model
  - ✅ Golden Model C++ v2 — 21/21 host-side tests passing
- ✅ **SoC base source updated: `base_soc.py` with NPU v2 wrapper, IRQ 10, Wishbone slave + master** (targets `litex_boards.realdigital_urbana`); SoC runtime and physical IRQ behavior remain unverified
  - ✅ Device Tree source for target FPGA: `urrbana.dts` (RealDigital Urbana, Spartan-7 XC7S50-CSGA324, 128 MB DDR3 @ `0x80000000`)
- ✅ **Phase 4 (in progress):** RealDigital Urbana board received (Aug 2026). Pending: synthesis + timing closure and a resource report (LUTs, DSP count, FFs, BRAM) for Paper 1.

### Gildo (OS + HAL) — Buildroot, Device Tree, NPU HAL, Classifier

**Provisional scope proposal:** Gildo is proposed to lead the NPU HAL and Classifier, the software layer intended to complete the NPU integration (the simpler the hardware, the more complex the software). This ownership remains pending Professor Ramon and team confirmation.

- ✅ **Phase 1:** Buildroot external tree. RV32IMA defconfig. QEMU boot.
- ✅ **Phase 2:** Toolchain via `make sdk`.
- ✅ **Phase 3 — Infrastructure:**
  - ✅ Official `.dts` (QEMU + FPGA) — `compatible = "ternaryedge,npu-ternaria"`, IRQ=10, RV32IMA
  - ✅ `CONFIG_HIGH_RES_TIMERS=y` — kernel config fragment (`configs/kernel-npu.cfg`)
  - ✅ FAT32/ext4 in RootFS — via `BR2_PACKAGE_DOSFSTOOLS`, `CONFIG_FAT_FS`, `CONFIG_EXT4_FS`
  - ✅ Structured `Config.in`, `external.mk`, `external.desc`
  - ✅ **NPU HAL + Classifier + Buildroot Packages present at source level; end-to-end contract pending:**
    - ✅ `npu_hal.h` / `npu_hal.c` — API and implementation (init, load_weights, predict, batch, deinit)
    - ✅ `npu_classifier.c` — Output layer 256->10 CPU (FP32: score, argmax, softmax)
    - ✅ `npu_weights.c` — Weights loader from the QAT pipeline
    - ✅ `software/user_app/weights.h` contains the checked-in packed ternary arrays; output symbols required by the HAL remain missing
  - ✅ Buildroot packages (npu-ternaria, npu-hal, user-app) + `Config.in`/`external.mk`/`defconfig`
  - ✅ `user_app.c` refactored: HAL API + `--cpu`, `--file`, `--batch` flags
  - ✅ HAL library build path documented; current native diagnostics expose missing output symbols, so hardware integration and HAL/weights compatibility remain unvalidated
- ⏳ **Phase 4 (pending):** Generate final Buildroot image (kernel 6.18.7 + OpenSBI 1.6 + RootFS), partition SD card (FAT32 boot + ext4 rootfs), boot on Urbana, validate `dmesg`.

### Gustavo (Driver) — NPU v2 source-level adaptation; physical validation pending
- ✅ Platform driver with `dma_alloc_coherent`, `mmap`, `request_irq`, `wait_event_interruptible`.
- ✅ **NPU v2 source-level adaptation (`npu_driver.c` v3.0):**
  - ✅ Offsets revised (10 registers, 0x00–0x24)
  - ✅ `iowrite32()` for WEIGHT_CFG + ACT_CFG + MAC_CFG + LAYER_CFG
  - ✅ IOCTL with struct `npu_ioctl_args` (5 configuration fields)
  - ✅ IOCTL header compartilhado: `software/include/npu_ioctl.h`
- ⏳ **Phase 4 (pending):** `insmod` on the physical Urbana, IRQ/DMA validation via `dmesg`, end-to-end inference check on real hardware. Nota: revisão recomendada do cast de leitura do `npu_output` no `npu_hal.c` (ler 32 bits por neurônio, não 8 bits) antes de integrar com o NPU real.

### Gilvan (historical AI contribution) — Golden Model + weights.h
- ✅ Historical QAT pipeline (Larq + STE), ternary layers, and `weights.h` contribution retained in the project record.
- ✅ Golden Model C++ v2: 21/21 host-side tests (64-term loop, DMA, Layer Sequencer)
- ✅ Output layer direction documented as CPU fallback
- ⏳ The exported weights and HAL contract remain incomplete pending end-to-end validation.
- ⏳ **Phase 4 (pending):** Gustavo provisionally owns the benchmark protocol and results. Real MNIST inference on the Urbana, `.csv` measurements (CPU versus NPU), graphs, and Paper 1 experimental results await physical validation.

> The `user_app.c` was transferred to Gildo, who refactored it to use the HAL.

### Known Gaps
| Gap | Provisional owner | Priority | Status (Aug 2026) |
|:----|:------|:---------|:------------------|
| Physical FPGA synthesis & bitstream | Arthur, provisional | **High** | Board received (Urbana XC7S50); synthesis pending |
| Buildroot SD image + boot on FPGA | Gildo, provisional | **High** | Tree ready; image build + SD flash pending |
| Driver `insmod` on physical FPGA | Gustavo, provisional | **High** | Driver source present; physical validation pending |
| Real-hardware benchmark (CPU × NPU) | Gustavo, provisional | **High** | Protocol and collection pending validated FPGA boot and end-to-end integration |
| Paper 1 — all sections | Team | **High** | Skeleton + abstract done; awaiting real metrics from FPGA |
| Toolchain not built by all members | Team | Medium | Buildroot SDK is self-service; each member runs `make sdk` |

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
6. **Run Inference after physical validation:** Boot Linux on the FPGA, load the driver (`insmod`), and execute the benchmark application.

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
NPU v2 source-level design (64-MAC modules, Layer Sequencer)
```

### 4. AI Pipeline (ai_training/)

The AI pipeline uses **Larq** for Quantization-Aware Training with the Straight-Through Estimator (STE), producing strictly ternary weights `{-1, 0, +1}`.

```bash
# Run the full pipeline (train -> validate -> pack -> export)
cd ai_training
python3 scripts/run_pipeline.py
```

The pipeline is intended to generate `weights.h` for the NPU HAL, but the HAL/weights contract is incomplete and requires end-to-end validation:
- `quant_dense_weights[50176]` — Layer 0 (784→1024)
- `quant_dense_1_weights[32768]` — Layer 1 (1024→512)
- `quant_dense_2_weights[8192]` — Layer 2 (512→256)
- `output_weights[2560]` — Output layer FP32 expected by the current HAL, absent from the checked-in header and pending export validation
- `output_bias[10]` — Output layer bias expected by the current HAL, absent from the checked-in header and pending export validation

---

## 🔧 Target Hardware: RealDigital Urbana (Phase 4)

The project targets the **RealDigital Urbana** board, which satisfies all `requisitos_fpga.md` requirements:

| Component | Urbana Board | Project Requirement |
|:----------|:-------------|:--------------------|
| FPGA | AMD Spartan-7 **XC7S50-CSGA324** | Xilinx 7-series (Wishbone + LiteX) |
| Logic Cells | ~52K LUTs | ≥ 15K (VexRiscv Linux + NPU) |
| External RAM | 128 MB DDR3 (`0x80000000–0x87FFFFFF`) | ≥ 32 MB (Linux + RootFS) |
| Storage | MicroSD slot | Boot + RootFS (FAT32 + ext4) |
| Console | UART via FTDI micro-USB | Linux console @ 115200 baud |
| Programmer | FTDI over micro-USB | openFPGALoader / Vivado Hardware Manager |

### Hardware Synthesis (Arthur)

Two supported toolchains for the Spartan-7:

**Option A — Xilinx Vivado (WebPACK, Spartan-7 supported, free):**
```bash
cd hardware/litex_soc
source <vivado>/settings64.sh
python3 base_soc.py --build       # Synthesize → bitstream
python3 base_soc.py --load       # Load bitstream to SRAM (volatile)
python3 base_soc.py --flash      # Flash bitstream to SPI flash (persistent)
```

**Option B — Open-source toolchain (openXC7: yosys + nextpnr-xilinx + openFPGALoader):**
```bash
# Install (one-time)
nix profile install nixpkgs#yosys nixpkgs#nextpnr-xilinx nixpkgs#openfpgaloader
sudo snap install openxc7

# Build and flash
cd hardware/litex_soc
python3 base_soc.py --build --toolchain yosysnextpnr
openFPGALoader --board realdigital_urbana build/ternaryedge-urbana/bit.bin
```

### SD Card Preparation (Gildo)

Two partitions on the MicroSD card:
- **Partition 1 (FAT32, ~64 MB):** `boot.json` + `boot.scr` (U-Boot) + Linux kernel `Image` + `rv32.dtb` (LiteX-generated, based on `urrbana.dts`)
- **Partition 2 (ext4, rest):** Buildroot RootFS — including `/lib/modules/<ver>/npu_driver.ko`, `/usr/lib/libnpu_hal.a`, `/usr/bin/user_app`, `/root/mnist/*.raw` (test images)

### Planned FPGA Boot & Inference (Gildo + Gustavo, provisional)

```bash
# On Urbana UART console (via micro-USB FTDI @ 115200):
# 1. OpenSBI → U-Boot → Linux boot from mmcblk0p2

# 2. Load the NPU kernel module
insmod npu_driver.ko
dmesg | grep npu         # Expect "NPU v2 probe successful. /dev/npu_ternaria ready"

# 3. Run baseline CPU inference (3-layer ternary MLP in software, no NPU)
./user_app --cpu --file /root/mnist/sample_7.raw

# 4. Run proposed NPU-accelerated inference after the physical path is validated
./user_app --file /root/mnist/sample_7.raw
#  Output: predicted class, confidence, time_copy_us, time_npu_us, time_output_us, time_total_us

# 5. Batch benchmark after validation (100 images) → save CSV for Paper 1
./user_app --batch 100 --file /root/mnist/batch/  > benchmark_npu.csv
./user_app --cpu --batch 100 --file /root/mnist/batch/ > benchmark_cpu.csv
```

---

## 👥 The Team

This research project is collaboratively developed by:

* **Arthur Oliveira Gomes** - *Hardware Architecture & RTL Design* (LiteX, Verilog, SoC Generation)
* **Gildo Alves de Lima Junior** - *OS Infrastructure & NPU HAL* (Buildroot, Device Tree, HAL, Classifier, Buildroot Packages)
* **Gustavo Alexandre dos Santos** - *Kernel Driver Development* (LKM, MMIO, Hardware Synchronization)
* **Gilvan Alves Pastor Junior** - *Historical Artificial Intelligence & Golden Model contribution* (QAT, C++ Simulation, historical benchmark work)

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
