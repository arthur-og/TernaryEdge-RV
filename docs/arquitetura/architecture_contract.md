# Architecture Contract: Ternary Edge-RV
**Última atualização:** 08/06/2026

This document formalizes the architectural decisions and "Design by Contract" parameters that all team members must follow to ensure the successful integration of the Hardware (RTL), OS (Linux), Kernel Driver (LKM), and User Space (AI) components.

---

## 1. System Architecture Standard (32-Bit)
**Decision:** The entire stack will strictly use **RV32IMA** (32-bit RISC-V).
**Justification:** The project aims to demonstrate extreme energy efficiency and area reduction on FPGA. A 64-bit architecture consumes significantly more logic (LUTs/FFs) and memory bandwidth without offering tangible benefits for ternary quantized operations.

*   **Arthur (Hardware):** The LiteX VexRiscv core must be generated as a 32-bit CPU (variant `linux`).
*   **Gildo (OS):** The Buildroot configuration must use `BR2_RISCV_32=y` (see `ternaryedge_rv_defconfig`).
*   **Gustavo & Gilvan (Software):** The toolchain must compile specifically for 32-bit (`-march=rv32ima -mabi=ilp32`). Do not use 64-bit cross-compilers.

---

## 2. NPU Memory Map (Official — Phase 1 Final)

**Base Address:** `0x40000000`
**IRQ Number:** `10` (Connected to VexRiscv PLIC/CLINT)
**Endianness:** Little-Endian (native RISC-V)
**Bus Interface:** Wishbone B4 (32-bit data, 32-bit address)

| Offset | Register Name   | Width | R/W   | Description |
|:-------|:----------------|:------|:------|:------------|
| `0x00` | `NPU_STATUS`    | 32    | RO    | bit0 = busy, bit1 = irq_pending |
| `0x04` | `NPU_CONTROL`   | 32    | WO    | bit0 = start, bit1 = clear_irq |
| `0x08` | `DMA_SRC_ADDR`  | 32    | R/W   | Physical address of weights/input data in RAM |
| `0x0C` | `DMA_DST_ADDR`  | 32    | R/W   | Physical address where NPU writes results |
| `0x10` | `DATA_SIZE`     | 32    | R/W   | Number of bytes to process |

---

## 3. Synchronization Mechanism (IRQ vs. Polling)
**Decision:** The NPU will notify the CPU of completion via **Hardware Interrupts (IRQ)**.
**Justification:** Polling wastes CPU cycles and significantly increases power consumption, defeating the purpose of an energy-efficient edge accelerator.

*   **Arthur:** The RTL NPU (`npu_ternaria_top.v`) exposes an `irq_out` pin that goes high when inference finishes, connected to the LiteX interrupt controller.
*   **Gildo:** The Device Tree (`.dts`) must map IRQ line `10` to the NPU's node using `interrupts = <0x0a>`.
*   **Gustavo:** The kernel driver (`npu_driver.c`) uses `devm_request_irq()` to handle the interrupt and puts the user process to sleep (`wait_event_interruptible`) until the NPU awakens it, keeping CPU usage close to zero during hardware inference.

---

## 4. Benchmarking Timing Segregation
**Decision:** Time profiling in C (`gettimeofday()`) must be broken down into three distinct phases.
**Justification:** The Wishbone bus may introduce latency. We need to isolate the pure NPU inference speed from the Memory-Mapped I/O (MMIO) data copy overhead.

*   **Gilvan:** In `user_app.c`, measure and print the following separately:
    1.  `t_copy_to_npu`: Time taken to write weights/activations to the driver/DMA buffer.
    2.  `t_inference`: Time waiting for the NPU (from IOCTL start to IRQ return).
    3.  `t_copy_from_npu`: Time taken to read the results back from the driver.

---

## 5. Endianness & Data Packing
**Decision:** Data must be formatted assuming **Little-Endian** ordering, matching the standard VexRiscv behavior.
**Justification:** 2-bit ternary weights ($\in \{-1, 0, 1\}$) are packed into 32-bit integers. If the AI Python script and the RTL NPU disagree on the byte/bit order, the math will be completely corrupted.

*   **Gilvan & Arthur:** Both must agree that `weights[0]` (the first weight) occupies the Least Significant Bits (LSB) of the 32-bit word. This rule is strictly coded in `pack_weights.py` and the Verilog unpacking logic.
*   **Encoding:** `+1 = 0b01`, `0 = 0b00`, `-1 = 0b11` (complement of 2 representation).

---

## 6. Architecture Overview

```text
User Space (C Application)
  │
  │ open(/dev/npu_ternaria)
  │ mmap(DMA buffer) ← writes packed weights directly
  │ ioctl(START_INFERENCE, &size)
  │   └─ wait_event_interruptible() ── CPU SLEEPS ──
  │                                        │
Kernel Space (Driver)                       │
  │ NPU_IOCTL_START_INFERENCE:              │
  │   1. iowrite32(dma_paddr, SRC_ADDR)     │
  │   2. iowrite32(size, DATA_SIZE)         │
  │   3. iowrite32(0x01, CONTROL) // Start  │
  │   4. sleep until interrupt               │
  │                                        │
Hardware (NPU)                              │
  │ FSM: IDLE → BUSY → DONE                │
  │   while (delay_counter > 0) count down  │
  │   when done: irq_out = 1 ─────────────────┘
  │   CPU reads STATUS, clears IRQ
```

---

## 7. Current Known Gaps

| Gap | Impact | Owner | Priority |
|:----|:-------|:------|:---------|
| Output layer in FP32, not ternary | NPU (ternary_mac.v) cannot compute last layer | Gilvan test ternary output; else Arthur adds hybrid MAC | High |
| No Wishbone Master (DMA) | NPU cannot read RAM autonomously — CPU must feed data | Arthur (Phase 3) | High |
| Toolchain not exported | Cannot cross-compile driver (.ko) and app | Gildo | Critical |
| No physical FPGA yet | Cannot synthesize or run real hardware | Arthur + Professor | High |
