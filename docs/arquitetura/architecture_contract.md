# Architecture Contract: Ternary Edge-RV

This document formalizes the architectural decisions and "Design by Contract" parameters that all team members must follow to ensure the successful integration of the Hardware (RTL), OS (Linux), Kernel Driver (LKM), and User Space (AI) components.

## 1. System Architecture Standard (32-Bit)
**Decision:** The entire stack will strictly use **RV32IMA** (32-bit RISC-V).
**Justification:** The project aims to demonstrate extreme energy efficiency and area reduction on FPGA. A 64-bit architecture consumes significantly more logic (LUTs/FFs) and memory bandwidth without offering tangible benefits for ternary quantized operations.

*   **Arthur (Hardware):** The LiteX VexRiscv core must be generated as a 32-bit CPU.
*   **Gildo (OS):** The Buildroot configuration must use `RISCV_ARCH=rv32ima`.
*   **Gustavo & Gilvan (Software):** The toolchain must compile specifically for 32-bit (`-march=rv32ima -mabi=ilp32`). Do not use 64-bit cross-compilers.

## 2. Synchronization Mechanism (IRQ vs. Polling)
**Decision:** The NPU will notify the CPU of completion via **Hardware Interrupts (IRQ)**.
**Justification:** Polling wastes CPU cycles and significantly increases power consumption, defeating the purpose of an energy-efficient edge accelerator.

*   **Arthur:** The RTL NPU must expose an `irq_out` pin that goes high when inference finishes, connected to the LiteX interrupt controller.
*   **Gildo:** The Device Tree (`.dts`) must map this specific IRQ line to the NPU's node.
*   **Gustavo:** The kernel driver must use `request_irq()` to handle the interrupt and put the user process to sleep (`wait_event_interruptible`) until the NPU awakens it, keeping CPU usage close to zero during hardware inference.

## 3. Benchmarking Timing Segregation
**Decision:** Time profiling in C (`<sys/time.h>`) must be broken down into three distinct phases.
**Justification:** The Wishbone/AXI bus might introduce latency. We need to isolate the pure NPU inference speed from the Memory-Mapped I/O (MMIO) data copy overhead.

*   **Gilvan:** In `user_app.c`, measure and print the following separately:
    1.  `t_copy_to_npu`: Time taken to write weights/activations to the driver.
    2.  `t_inference`: Time waiting for the NPU (from write start to IRQ return).
    3.  `t_copy_from_npu`: Time taken to read the results back from the driver.

## 4. Endianness & Data Packing
**Decision:** Data must be formatted assuming **Little-Endian** ordering, matching the standard VexRiscv behavior.
**Justification:** 2-bit ternary weights ($\in \{-1, 0, 1\}$) are packed into 32-bit integers. If the AI Python script and the RTL NPU disagree on the byte/bit order, the math will be completely corrupted.

*   **Gilvan & Arthur:** Both must agree that `weights[0]` (the first weight) occupies the Least Significant Bits (LSB) or Most Significant Bits (MSB) of the 32-bit word, and this rule must be strictly coded in the Python unpacker and the Verilog unpacking logic.

## 5. Early Memory Map Draft (Mock)
To allow parallel development in Phase 1 and 2, the following addresses are assumed (to be updated by Arthur upon synthesis):

*   **Base Address:** `0x8000_0000` (Example)
*   **IRQ Number:** `TBD` (Will be assigned by LiteX)

| Offset | Register Name | R/W | Description |
| :--- | :--- | :--- | :--- |
| `0x00` | `REG_CTRL` | W | Control register (e.g., bit 0 = start, bit 1 = reset) |
| `0x04` | `REG_STATUS` | R | Status register (e.g., bit 0 = busy, bit 1 = done) |
| `0x08` | `REG_ADDR_IN` | W | Base address for input activations |
| `0x0C` | `REG_ADDR_W` | W | Base address for packed weights |
| `0x10` | `REG_ADDR_OUT` | W | Base address for output results |

*(Note: Arthur must update this document as the Verilog design solidifies).*
