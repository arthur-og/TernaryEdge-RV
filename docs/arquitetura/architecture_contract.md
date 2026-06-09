# Architecture Contract: Ternary Edge-RV
**Última atualização:** 10/06/2026
**Versão:** 2.1 — Fase 3 completa: RTL v2 implementada, golden model validado (29/29 testes)

This document formalizes the architectural decisions and "Design by Contract" parameters that all team members must follow to ensure the successful integration of the Hardware (RTL), OS (Linux), Kernel Driver (LKM), and User Space (AI) components.

---

## 1. System Architecture Standard (32-Bit)
**Decision:** The entire stack will strictly use **RV32IMA** (32-bit RISC-V).
**Justification:** The project aims to demonstrate extreme energy efficiency and area reduction on FPGA. A 64-bit architecture consumes significantly more logic (LUTs/FFs) and memory bandwidth without offering tangible benefits for ternary quantized operations.

*   **Arthur (Hardware):** The LiteX VexRiscv core must be generated as a 32-bit CPU (variant `linux`).
*   **Gildo (OS):** The Buildroot configuration must use `BR2_RISCV_32=y` (see `ternaryedge_rv_defconfig`).
*   **Gustavo & Gilvan (Software):** The toolchain must compile specifically for 32-bit (`-march=rv32ima -mabi=ilp32`). The toolchain is built locally by each member from the Buildroot SDK (`make sdk`).

---

## 2. NPU Memory Map (Official — Version 2.0)

**Base Address:** `0x40000000`
**IRQ Number:** `10` (Connected to VexRiscv PLIC/CLINT)
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

### DMA Transaction Flow
1. CPU writes `DMA_SRC_ADDR`, `DMA_DST_ADDR`, `DMA_SIZE`, `WEIGHT_CFG`, `ACT_CFG`
2. CPU writes `NPU_CONTROL.start = 1`
3. NPU activates **Wishbone Master**: reads weight data from RAM via burst reads
4. NPU distributes weights across **64 parallel ternary_mac units**
5. Each MAC processes 1 weight from the unpacked 32-bit word (16 weights × 4 words = 64 MACs/cycle)
6. Upon finishing `DMA_SIZE` MACs, NPU writes result to `DMA_DST_ADDR` and sets `irq_out = 1`
7. CPU reads result and clears IRQ

---

## 3. Parallelism: 64 MAC Array

**Decision:** The NPU instantiates **64 ternary_mac units** operating in parallel.
**Justification:** A single MAC sequentially processing 802,816 operations (first layer) would take ~2.4M cycles = 48ms at 50 MHz. With 64 MACs, this drops to ~37.5K cycles = 0.75ms — a 64× speedup that guarantees the NPU outperforms the CPU on latency.

*   **Arthur:** Each `ternary_mac.v` receives one 2-bit weight from the unpacked 32-bit memory words. The 64 partial sums are combined via an adder tree.
*   **Memory:** 4 weight words are fetched per cycle (4 × 32-bit = 128 bits → 64 × 2-bit weights).
*   **Total weight storage:** `WEIGHT_MEM_SIZE = 16384` words (512 Kb) — fits layer 1 entirely (50,176 words × 32 bits). For larger layers, tiling is handled by the driver.

---

## 4. Synchronization Mechanism (IRQ vs. Polling)
**Decision:** The NPU will notify the CPU of completion via **Hardware Interrupts (IRQ)**.
**Justification:** Polling wastes CPU cycles and significantly increases power consumption, defeating the purpose of an energy-efficient edge accelerator.

*   **Arthur:** The RTL NPU (`npu_ternaria_top.v`) exposes an `irq_out` pin that goes high when inference finishes. The Wishbone Master autonomously writes results to `DMA_DST_ADDR` before asserting IRQ.
*   **Gildo:** The Device Tree (`.dts`) must map IRQ line `10` to the NPU's node using `interrupts = <0x0a>`.
*   **Gustavo:** The kernel driver (`npu_driver.c`) uses `devm_request_irq()` to handle the interrupt and puts the user process to sleep (`wait_event_interruptible`) until the NPU awakens it, keeping CPU usage close to zero during hardware inference.

---

## 5. Benchmarking Timing Segregation
**Decision:** Time profiling in C (`gettimeofday()`) must be broken down into three distinct phases.
**Justification:** The Wishbone bus and DMA setup may introduce latency. We need to isolate the pure NPU inference speed from the data transfer and driver overhead.

*   **Gilvan:** In `user_app.c`, measure and print the following separately:
    1.  `t_dma_setup`: Time to configure DMA addresses and initiate transfer.
    2.  `t_inference`: Time waiting for the NPU IRQ (pure hardware compute).
    3.  `t_readback`: Time to retrieve results from the DMA destination buffer.

---

## 6. Endianness & Data Packing
**Decision:** Data must be formatted assuming **Little-Endian** ordering, matching the standard VexRiscv behavior.
**Justification:** 2-bit ternary weights ($\in \{-1, 0, 1\}$) are packed into 32-bit integers. If the AI Python script and the RTL NPU disagree on the byte/bit order, the math will be completely corrupted.

*   **Gilvan & Arthur:** Both must agree that `weights[0]` (the first weight) occupies the Least Significant Bits (LSB) of the 32-bit word. This rule is strictly coded in `pack_weights.py` and the Verilog unpacking logic.
*   **Encoding:** `+1 = 0b01`, `0 = 0b00`, `-1 = 0b11` (complement of 2 representation).

---

## 7. Architecture Overview (v2 — DMA Flow)

```text
User Space (C Application)
  │
  │ open(/dev/npu_ternaria)
  │ mmap(DMA buffer) ← writes packed weights + activations
  │ ioctl(START_INFERENCE, &size)
  │   └─ wait_event_interruptible() ── CPU SLEEPS ──
  │                                        │
Kernel Space (Driver)                       │
  │ NPU_IOCTL_START_INFERENCE:              │
  │   1. iowrite32(dma_paddr, SRC_ADDR)    │
  │   2. iowrite32(size, DMA_SIZE)         │
  │   3. iowrite32(weights_cfg, WEIGHT_CFG)│
  │   4. iowrite32(acts_cfg, ACT_CFG)      │
  │   5. iowrite32(0x01, CONTROL) // Start │
  │   6. sleep until interrupt              │
  │                                        │
Hardware (NPU)                              │
  │ Wishbone Master:                        │
  │   → Reads weights from RAM (burst)     │
  │   → Reads activations from RAM (burst) │
  │ 64× ternary_mac in parallel            │
  │ FSM: IDLE → DMA_RD → COMPUTE → DONE   │
  │   when done: writes result to RAM      │
  │   irq_out = 1 ───────────────────────────┘
  │   CPU reads STATUS, clears IRQ
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

## 9. Current Known Gaps

| Gap | Impact | Owner | Priority |
|:----|:-------|:------|:---------|
| Output layer in FP32, not ternary | NPU (ternary_mac.v) cannot compute last layer | Gilvan: test ternary output (Opção A); fallback: CPU computes last layer (Opção B) | High |
| **FPGA física não recebida** | Cannot synthesize or run real hardware | Arthur + Professor | **Critical** — já conversado, liberação confirmada |
| Device Tree (.dts) para NPU v2 não criado | Driver precisa de DT node para probe | Gildo: criar node com `compatible` + IRQ=10 | High |
| Config.in / external.mk vazios | Buildroot external tree incompleta | Gildo: preencher com conteúdo mínimo | Medium |
| QEMU setup usa CPU rv64imafdch (projeto é RV32) | Ambiente de teste não reflete alvo real | Gildo/Gustavo: atualizar para RV32 ou documentar | Medium |
| weights.h versionado no Git (364 KB) | Polui histórico; deve ser regenerado no build | Gilvan: adicionar ao .gitignore + Makefile | Low |
