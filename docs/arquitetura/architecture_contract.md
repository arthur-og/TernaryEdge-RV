# Architecture Contract: Ternary Edge-RV
**Última atualização:** 04/08/2026
**Versão:** 2.3 — FPGA Urrbana recebida, HAL implementada, Phase 4 in progress

This document formalizes the architectural decisions and "Design by Contract" parameters that all team members must follow to ensure the successful integration of the Hardware (RTL), OS (Linux), Kernel Driver (LKM), HAL (NPU Abstraction), and User Space (AI) components.

---

## 1. System Architecture Standard (32-Bit)
**Decision:** The entire stack will strictly use **RV32IMA** (32-bit RISC-V).
**Justification:** The project aims to demonstrate extreme energy efficiency and area reduction on FPGA. A 64-bit architecture consumes significantly more logic (LUTs/FFs) and memory bandwidth without offering tangible benefits for ternary quantized operations.

*   **Arthur (Hardware):** The LiteX VexRiscv core must be generated as a 32-bit CPU (variant `linux`).
*   **Gildo (OS + HAL):** The Buildroot configuration must use `BR2_RISCV_32=y`. The HAL must compile with `-march=rv32ima -mabi=ilp32`.
*   **Gustavo (Driver):** The kernel driver must be compiled for 32-bit RISC-V.
*   **Gilvan (AI):** The toolchain must compile specifically for 32-bit (`-march=rv32ima -mabi=ilp32`).

---

## 2. NPU Memory Map (Official — Version 2.0)

**Base Address:** `0x40000000`
**IRQ Number:** `10` (Connected to VexRiscv PLIC)
**Endianness:** Little-Endian (native RISC-V)
**Bus Interface:** Wishbone B4 (32-bit data, 32-bit address) — Slave for CPU access + Master for DMA

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
4. NPU distributes weights across **64 parallel ternary_mac units**
5. Each MAC processes 1 weight from the unpacked 32-bit word (16 weights × 4 words = 64 MACs/cycle)
6. Upon finishing all MACs, NPU writes result to `DMA_DST_ADDR` and sets `irq_out = 1`
7. CPU wakes, reads result, and clears IRQ

---

## 3. Parallelism: 64 MAC Array

**Decision:** The NPU instantiates **64 ternary_mac units** operating in parallel.
**Justification:** A single MAC sequentially processing 802,816 operations (first layer) would take ~2.4M cycles = 48ms at 50 MHz. With 64 MACs, this drops to ~37.5K cycles = 0.75ms — a 64× speedup.

*   **Arthur:** Each `ternary_mac.v` receives one 2-bit weight. The 64 partial sums are combined via an adder tree.
*   **Memory:** 4 weight words are fetched per cycle (4 × 32-bit = 128 bits → 64 × 2-bit weights).
*   **Weight storage:** `WEIGHT_MEM_SIZE = 16384` words (512 Kb) — fits largest layer (50,176 words). Larger layers handled by tiling.

---

## 4. Synchronization Mechanism (IRQ vs. Polling)
**Decision:** The NPU will notify the CPU of completion via **Hardware Interrupts (IRQ)**.
**Justification:** Polling wastes CPU cycles and significantly increases power consumption, defeating the purpose of an energy-efficient edge accelerator.

*   **Arthur:** The RTL NPU exposes an `irq_out` pin that goes high when inference finishes.
*   **Gildo:** The Device Tree (`.dts`) must map IRQ line `10` to the NPU node. The HAL must wait for the driver's IRQ-based ioctl.
*   **Gustavo:** The kernel driver uses `devm_request_irq()` + `wait_event_interruptible()`, keeping CPU usage near zero during inference.

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

*   **Gilvan & Arthur:** `weights[0]` (first weight) occupies LSBs of the 32-bit word. Encoding: `+1 = 0b01`, `0 = 0b00`, `-1 = 0b11`.
*   **Gildo (HAL):** The HAL reads weights from `weights.h` (pipeline output) and copies them verbatim to the DMA buffer — no byte-swapping needed.

---

## 7. Architecture Overview (v2 — Full Stack)

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
  │    │   64 MACs multiplierless   │
  │    │   Wishbone Master DMA      │
  │    │   Layer Sequencer (3 lyrs) │
  │    │   IRQ → PLIC               │
  │    │                            │
  │    ├── DDR3 (128 MB)            │
  │    │   @ 0x80000000             │
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
  3. 64 MACs compute in parallel: pseudo_prod[i] = act[i] × weight[i]
  4. Adder tree sums all 64 pseudo_prods into accumulator
  5. Controller iterates until DMA_SIZE MACs are complete
```

---

## 9. NPU HAL (Hardware Abstraction Layer) — New

**Rationale:** The NPU v2 is purely ternary (only {+1,0,-1} multiplications). It cannot compute the final classification layer (256→10) which requires FP32 weights and softmax. The HAL encapsulates:

1. **Device initialization** (`npu_init`): opens `/dev/npu_ternaria`, mmaps DMA buffer
2. **Weight loading** (`npu_load_weights`): copies ternary weights from `weights.h` to DMA
3. **Inference** (`npu_predict`): copies input image, triggers ioctl, reads NPU output
4. **Output layer** (internal): runs 256→10 FP32 classification on CPU via `classifier_run()`
5. **Batch inference** (`npu_predict_batch`): repeats predict for N images

### DMA Buffer Layout

| Offset | Size | Content |
|--------|------|---------|
| `0x000000` | 4 KB | Result area (NPU writes 256 × int32 here) |
| `0x001000` | 364 KB | Ternary weights (3 layers: 50,176 + 32,768 + 8,192 words) |
| `0x05C000` | 1 KB | Input activations (784 bytes + padding) |
| `0x05C400` | 10 KB | Output layer FP32 weights (2,560 floats) |
| `0x05F000` | ~3.8 MB | Free / expansion |

* **Gildo (HAL):** Owns the HAL design, implementation, and test.
* **Gustavo (Driver):** The HAL depends on the driver's ioctl interface — must remain stable.
* **Gilvan (AI):** The `weights.h` format must match what the HAL expects (per-layer arrays + output weights).

---

## 10. NPU Classifier (CPU Fallback)

**Decision:** The output layer (256→10) runs on the CPU, not the NPU.

**Justification:** The NPU v2 has no FP32 multiplier. Attempting a ternary output layer (Opção A) caused accuracy to drop below 90%. The adopted solution (Opção B) uses the NPU for 3 ternary layers and the CPU for the final FP32 classification.

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
* **Gilvan (AI):** Provides `output_weights[2560]` and `output_biases[10]` via the QAT pipeline.

---

## 11. Current Known Gaps

**Status (Aug 2026):** Phase 3 fully complete (software code-complete, validated by 29/29 golden model tests). RealDigital Urbana board received. The project is now in Phase 4 (physical deployment + Paper 1).

| Gap | Impact | Owner | Priority | Resolution Path |
|:----|:-------|:------|:---------|:----------------|
| **FPGA synthesis & bitstream** | Cannot run on real hardware | Arthur | **Critical** | `python3 base_soc.py --build` (Opção A: Vivado / Opção B: openXC7) |
| **Linux boot on FPGA** | Cannot test driver / HAL | Gildo | **High** | Buildroot image → SD card (FAT32+ext4) → boot via OpenSBI → U-Boot → kernel |
| **Driver `insmod` on physical hardware** | No `/dev/npu_ternaria` | Gustavo | **High** | Cross-compile `.ko` for RV32IMA, `insmod`, validate IRQ/DMA via `dmesg` |
| **Real benchmark (CPU × NPU latency)** | No data for Paper 1 §IV | Gilvan | **High** | `user_app --cpu` vs default; save CSV from FPGA |
| **Paper 1 sections** | No submission | Team | **High** | Each member writes their section after real metrics; skeleton in `paper/paper1_template.tex` |
| Possible HAL bug at `npu_hal.c:76` | Inference returns garbage | Gildo | Medium | Review 8-bit vs 32-bit cast of `npu_output[i]` against RTL `npu_ternaria_top_v2.v` |
| Possible HAL/RTL mismatch at `npu_hal.c:51` | Activations written to wrong DMA offset | Gildo + Arthur | Medium | Verify offset `0x5C000` matches `WEIGHT_CFG`/`ACT_CFG` semantics in `wishbone_master.v` |
| Toolchain not built by all members | Each member cannot build `.ko` locally | All | Low | Each member runs `make sdk` in `software/os_buildroot/` (documented in their README) |
| Notebook do Arthur (i5-5200U, 8 GB RAM) | Vivado swap-heavy, slow synthesis | Arthur | Low | Use openXC7 (Opção B) — ~600 MB total, RAM-friendly |
