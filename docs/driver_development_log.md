# Driver Development Log - TernaryEdge-RV

## Phase 1: Environment and Setup Validation (Completed)
- **Goal**: Establish a functional cross-compilation pipeline and validate kernel module loading in a RISC-V QEMU environment.
- **Actions Taken**:
  - Adjusted QEMU memory to `4G` in `boot.sh` to prevent `FDT creation failed` overlaps.
  - Resolved Linux kernel header mismatches between the host cross-compiler and the specific QEMU Debian image (`6.18.5+deb14-riscv64`).
  - Implemented an SSH-based remote compilation and testing loop inside the virtualized environment.
  - Successfully loaded a "Hello World" LKM, validating architecture compatibility.

## Phase 2: NPU Driver Skeleton (In Progress)
- **Goal**: Implement the real MMIO/IRQ driver for the Ternary NPU, focusing on extreme energy efficiency (Zero CPU Polling).
- **Architecture Implemented (`software/npu_driver/npu_driver.c`)**:
  - **Character Device**: Automatically registers `/dev/npu_ternaria`.
  - **Memory-Mapped I/O (MMIO)**: Prepared `ioremap`, `iowrite32`, and `ioread32` hooks for AXI/Wishbone integration.
  - **IRQ Synchronization**: The core innovation. We implemented a `wait_queue` (`wait_event_interruptible`). User-space calls to `read()` will put the process to sleep until the hardware triggers `npu_irq_handler`, which clears the interrupt and wakes the thread (`wake_up_interruptible`).
  - **User-Space Bridge**: Safe memory translation via `copy_to_user` and `copy_from_user`.

## Next Requirements (Awaiting Hardware Definition)
To finalize the driver integration with the LiteX SoC, we need:
1. **Base Physical Address** of the NPU on the memory bus.
2. **Hardware IRQ Number** assigned to the NPU.
3. **Register Offsets** mapping (Status, Control, Weights Input, Activations Output).
