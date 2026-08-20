# Architecture Contract: Ternary Edge-RV
**Última atualização:** 20/08/2026
**Versão:** 2.5 (Current operational transition; 17/08/2026 hardware and Verilog records remain historical snapshots)

This document formalizes the architectural decisions and "Design by Contract" parameters that all team members must follow to ensure the successful integration of the Hardware (RTL), OS (Linux), Kernel Driver (LKM), HAL (NPU Abstraction), and User Space (AI) components.

---

## 1. System Architecture Standard (32-Bit) & Team Roles
**Decision:** The entire stack will strictly use **RV32IMA** (32-bit RISC-V).
**Justification:** The project aims to demonstrate extreme energy efficiency and area reduction on FPGA. A 64-bit architecture consumes significantly more logic (LUTs/FFs) and memory bandwidth without offering tangible benefits for ternary quantized operations.

### Team Roles & Operational Responsibilities (post-Gilvan transition)
*   **Arthur Oliveira Gomes (Hardware Architecture & RTL):** Hardware RTL, LiteX SoC VexRiscv generation, Verilog regression testbench, openXC7 synthesis (with flags `-nolutram -nowidelut`), Vivado synthesis, bitstream generation and FPGA resource report.
*   **Gildo Alves de Lima Junior (OS Infrastructure & HAL):** Buildroot OS configuration (`BR2_RISCV_32=y`), Device Tree (`urrbana.dts`), NPU HAL (`libnpu_hal.a`), Output Classifier (FP32 CPU), MicroSD card image preparation and physical Linux boot on Urbana.
*   **Gustavo Alexandre dos Santos (AI Pipeline, Weights, Golden Model, Kernel Driver & Validation):** Current AI pipeline maintenance, weight export and `weights.h` contract, C++ Golden Model regression and maintenance, kernel driver (`npu_driver.ko`), RV32 cross-compilation (`-march=rv32ima -mabi=ilp32`), physical validation coordination, CPU-versus-NPU benchmarks, and results and discussion for Paper 1.
*   **Gilvan Alves Pastor Junior (Historical AI & Golden Model):** Historical QAT pipeline (Larq/STE), ternary packing, and C++ Golden Model v2 retained and credited as the 4th author on Paper 1. Gilvan has no current operational ownership.

---

## 2. NPU Memory Map (Current Candidate, Validation Required)

**Base Address:** `0x80000000` (current LiteX NPU MMIO candidate, pending cross-layer validation)
**IRQ Number:** `10` (Connected to VexRiscv PLIC)
**Endianness:** Little-Endian (native RISC-V)
**Bus Interface:** Wishbone B4 (32-bit data, 32-bit address): Slave for CPU access + Master for DMA

> **Address conflict:** Older map snapshots list `0x40000000` as the NPU base. Current LiteX documentation uses `0x80000000`. Validate the generated LiteX map, RTL, Device Tree, driver, and HAL before treating either address as final. Do not silently use both values.

### Register Layout

| Offset | Register        | Width | R/W   | Description |
|:-------|:----------------|:------|:------|:------------|
| `0x00` | `NPU_STATUS`    | 32    | RO    | `[0]=busy`, `[1]=irq_pending`, `[15:8]=zero_count` |
| `0x04` | `NPU_CONTROL`   | 32    | WO    | `bit0=start`, `bit1=clear_irq` |
| `0x08` | `DMA_SRC_ADDR`  | 32    | R/W   | Physical address in RAM where NPU reads weights/activations |
| `0x0C` | `DMA_DST_ADDR`  | 32    | R/W   | Physical address where NPU writes final result |
| `0x10` | `DMA_SIZE`      | 32    | R/W   | Number of MAC operations to execute |
| `0x14` | `WEIGHT_CFG`    | 32    | R/W   | `[15:0]=bytes_per_weight_row`, `[31:16]=num_weight_rows` |
| `0x18` | `ACT_CFG`       | 32    | R/W   | `[15:0]=num_activations` |
| `0x1C` | `RESULT`        | 32    | RO    | Final accumulated result of the inference |
| `0x20` | `MAC_CFG`       | 32    | R/W   | `[5:0]=num_macs_per_cycle` (1-64, default: 64) |
| `0x24` | `LAYER_CFG`     | 32    | R/W   | `[3:0]=num_layers` (1-8, default: 3) |

### DMA Transaction Flow
1. Driver writes `DMA_SRC_ADDR`, `DMA_DST_ADDR`, `DMA_SIZE`, `WEIGHT_CFG`, `ACT_CFG`
2. Driver writes `NPU_CONTROL.start = 1`
3. NPU activates **Wishbone Master**: reads weight data from RAM via burst reads
4. NPU is intended to distribute weights across **64 parallel ternary_mac units**
5. The design target gives each MAC 1 weight from the unpacked 32-bit word (16 weights × 4 words = 64 intended MACs/cycle), subject to RTL and synthesis validation
6. Upon finishing all MACs, NPU writes result to `DMA_DST_ADDR` and sets `irq_out = 1`
7. CPU wakes, reads result, and clears IRQ

---

## 3. Parallelism: 64 MAC Design Target

**Design intent:** The NPU targets **64 ternary_mac units** operating in parallel. The array and its integration remain subject to RTL execution and synthesis validation.
**Justification:** A single MAC sequentially processing 802,816 operations would require more cycles than the intended parallel design. The 64-MAC cycle reduction and any resulting latency or speedup are design estimates, not measured results.

*   **Arthur:** The design target gives each `ternary_mac.v` one 2-bit weight and combines 64 partial sums through an adder tree. Physical resource use is pending synthesis.
*   **Memory:** 4 weight words are fetched per cycle (4 x 32-bit = 128 bits -> 64 x 2-bit weights).
*   **Weight storage:** `WEIGHT_MEM_SIZE = 16384` words (512 Kb): fits largest layer (50,176 words). Larger layers handled by tiling.

---

## 4. Synchronization Mechanism (IRQ vs. Polling)
**Decision:** The NPU will notify the CPU of completion via **Hardware Interrupts (IRQ)**.
**Justification:** Polling wastes CPU cycles and significantly increases power consumption, defeating the purpose of an energy-efficient edge accelerator.

*   **Arthur:** The RTL design exposes an `irq_out` pin intended to go high when inference finishes; this behavior remains subject to RTL and physical validation.
*   **Gildo:** The Device Tree (`.dts`) must map IRQ line `10` to the NPU node. The HAL must wait for the driver's IRQ-based ioctl.
*   **Gustavo:** The kernel driver is intended to use `devm_request_irq()` + `wait_event_interruptible()`, with CPU usage and interrupt behavior pending physical validation.

---

## 5. Benchmarking Timing Segregation
**Decision:** Time profiling must be broken down into three distinct phases.
**Justification:** Need to isolate pure NPU compute from DMA setup and driver overhead.

*   **Gildo (HAL):** `npu_result_t` must capture:
  1. `time_copy_us`: Time to copy image → DMA buffer
  2. `time_npu_us`: Time waiting for the NPU IRQ (pure hardware compute)
  3. `time_output_us`: Time for CPU output layer (256→10)
  4. `time_total_us`: Wall clock from start to finish

---

## 6. Endianness & Data Packing
**Decision:** Little-Endian ordering, matching standard VexRiscv behavior.
**Justification:** 2-bit ternary weights ($\in \{-1, 0, 1\}$) are packed into 32-bit integers.

*   **Historical contribution by Gilvan, retained in the hardware record:** `weights[0]` occupies the LSBs of the 32-bit word. Encoding: `+1 = 0b01`, `0 = 0b00`, `-1 = 0b11`.
*   **Gildo (HAL):** The HAL reads weights from `weights.h` (pipeline output) and copies them verbatim to the DMA buffer: no byte-swapping needed.
*   **Gustavo:** Maintains the current export and `weights.h` contract against the HAL and driver.

---

## 7. Architecture Overview (v2: Full Stack)

```text
User Space
  ┌─────────────────────────────────┐
  │  user_app (Gildo)               │
  │   ┌───────────────────────┐     │
  │   │  NPU HAL (Gildo)      │     │  ← NOVA CAMADA
  │   │  npu_init()           │     │
  │   │  npu_load_weights()   │     │
  │   │  npu_predict()        │     │
  │   │  npu_deinit()         │     │
  │   └──────────┬────────────┘     │
  │              │                   │
  │              │ ioctl / mmap     │
  └──────────────┼───────────────────┘
                 │
Kernel Space     │
  ┌──────────────┼───────────────────┐
  │  npu_driver (Gustavo)           │
  │  /dev/npu_ternaria              │
  │  - iowrite32 to NPU regs       │
  │  - dma_alloc_coherent          │
  │  - wait_event_interruptible    │
  │  - IRQ handler → wake_up       │
  └──────────────┬───────────────────┘
                 │
                 │ Wishbone Bus
                 ▼
Hardware
  ┌─────────────────────────────────┐
  │  LiteX SoC (Arthur)             │
  │  VexRiscv RV32IMA               │
  │    │                            │
  │    ├── NPU v2 (Arthur)          │
  │    │   64 MAC design target     │
  │    │   Wishbone Master DMA      │
  │    │   Layer Sequencer (3 lyrs) │
  │    │   IRQ → PLIC               │
  │    │                            │
  │    ├── DDR3 (128 MB)           │
  │    │   @ address pending map validation │
  │    │                            │
  │    └── Peripherals (UART, SD,   │
  │        SPI flash, LEDs, etc.)   │
  └─────────────────────────────────┘
```

---

## 8. Data Flow per Layer

```
Weights in RAM:     [word0][word1]...[wordN]  ← packed 16 weights/word
Activations in RAM: [act0][act1]...[actM]     ← INT8 values

Each compute cycle:
  1. DMA reads 4 consecutive weight words (64 × 2-bit weights)
  2. DMA reads 64 consecutive activation bytes
  3. The intended 64-MAC design computes in parallel: pseudo_prod[i] = act[i] × weight[i]
  4. Adder tree sums all 64 pseudo_prods into accumulator
  5. Controller iterates until DMA_SIZE MACs are complete
```

---

## 9. NPU HAL (Hardware Abstraction Layer)

**Rationale:** The NPU v2 is purely ternary (only {+1,0,-1} multiplications). It cannot compute the final classification layer (256->10) which requires FP32 weights and softmax. The HAL encapsulates:

1. **Device initialization** (`npu_init`): opens `/dev/npu_ternaria`, mmaps DMA buffer
2. **Weight loading** (`npu_load_weights`): copies ternary weights from `weights.h` to DMA
3. **Inference** (`npu_predict`): copies input image, triggers ioctl, reads NPU output
4. **Output layer** (internal): runs 256->10 FP32 classification on CPU via `classifier_run()`
5. **Batch inference** (`npu_predict_batch`): repeats predict for N images

### DMA Buffer Layout

| Offset | Size | Content |
|--------|------|---------|
| `0x000000` | 4 KB | Result area (NPU writes 256 x int32 here) |
| `0x001000` | 364 KB | Ternary weights (3 layers: 50,176 + 32,768 + 8,192 words) |
| `0x05C000` | 1 KB | Input activations (784 bytes + padding) |
| `0x05C400` | 10 KB | Output layer FP32 weights (2,560 floats) |
| `0x05F000` | ~3.8 MB | Free / expansion |

* **Gildo (HAL):** Owns the HAL design, implementation, and test.
* **Gustavo (Driver):** The HAL depends on the driver's ioctl interface: must remain stable.
* **Gustavo (AI and weights):** Maintains the `weights.h` format expected by the HAL, including per-layer arrays and output weights.

---

## 10. NPU Classifier (CPU Fallback)

**Decision:** The output layer (256→10) runs on the CPU, not the NPU.

**Justification:** The NPU v2 has no FP32 multiplier. A historical host-side comparison of a ternary output layer (Opção A) reported accuracy below 90%. The adopted design (Opção B) targets 3 ternary layers in the NPU and CPU execution for the final FP32 classification.

```
NPU output: 256 × int32 (accumulated ternary products)
    │
    ▼
Classifier (CPU):
  for each class c (0..9):
    score[c] = bias[c] + Σ(i=0..255) npu_output[i] × output_weights[c][i]
  predicted = argmax(score)
  confidence = softmax(score)
```

* **Gildo (HAL):** Implements `classifier_run()` inside the HAL.
* **Gustavo:** Maintains the output-weight export and regression contract. Gilvan's historical QAT and packing contribution remains credited. Current FP32 symbols use fallback values and are not validated trained parameters.

---

## 11. Current Status & Known Gaps (17/08/2026)

**Historical snapshot (17/08/2026):** Earlier notes recorded the Urbana connection, FTDI detection, JTAG IDCODE 0x362f093, and a 4/4 Verilog result. The current shell cannot run the Verilog testbench, so that result is not current evidence. Current host evidence is C++ v1 8/8, C++ v2 21/21, Python 5/5, and IOCTL ABI pass. No FPGA end-to-end inference or CPU-versus-NPU benchmark is proven.

| Task / Gap | Impact | Active Owner | Priority | Status / Resolution Path |
|:-----------|:-------|:-------------|:---------|:-------------------------|
| **FPGA Synthesis & Bitstream** | Physical bitstream loading | Arthur | **Critical** | Urbana board detected via micro-USB (FTDI FT2232H). OpenXC7 synthesis flags updated to `-nolutram -nowidelut`. `python3 base_soc.py --build --toolchain openxc7` |
| **Linux Boot on FPGA** | Physical OS execution | Gildo | **High** | Buildroot image -> SD card (FAT32+ext4) -> boot via OpenSBI -> U-Boot -> kernel on Urbana |
| **Driver `insmod` on Physical Hardware** | `/dev/npu_ternaria` device node | Gustavo | **High** | Cross-compile `.ko` for RV32IMA, `insmod`, validate IRQ/DMA via `dmesg` |
| **Real Benchmark (CPU vs NPU latency)** | Paper 1 Section IV metrics | Gustavo | **High** | Gustavo coordinates physical validation with Arthur and Gildo; `user_app --cpu` versus default remains pending |
| **Paper 1 Sections & Submission** | SBCCI/LASCAS paper draft | Team (4 Authors) | **High** | Target completion date: 31/08/2026; template at `paper/paper1_template.tex` |
