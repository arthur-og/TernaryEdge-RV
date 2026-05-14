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

## Phase 2: NPU Driver Architecture (Zero-Copy DMA & Platform Integration)
- **Goal**: Transition from a basic MMIO Char Device to a high-performance DMA-backed Platform Driver, ensuring zero CPU polling and maximum energy efficiency.
- **Actions Taken**:
  - **Header Sharing**: Created `software/include/npu_ioctl.h` to share `ioctl` commands and buffer constraints between the Kernel Space and User Space.
  - **Platform Driver Migration (`software/npu_driver/npu_driver.c`)**:
    - Replaced hardcoded initialization with `platform_driver` API. The driver now automatically loads and configures itself based on the `.dts` (Device Tree) node matching `compatible = "ternary,npu-dma"`.
    - Removed `copy_from_user`/`copy_to_user` bottlenecks.
  - **DMA Memory Allocation**: Implemented `dma_alloc_coherent()` inside the `probe` function to allocate a physically contiguous, uncached memory region (4MB default) for hardware access.
  - **Zero-Copy with `mmap`**: Implemented the `.mmap` file operation (`dma_mmap_coherent`). This allows the AI application to write weights directly into the DMA buffer mapped in user space, bypassing CPU memory copy overhead entirely.
  - **Hardware Synchronization**: Transferred the `wait_queue` logic to the `ioctl` interface (`NPU_IOCTL_START_INFERENCE`). User apps will sleep upon triggering the IOCTL and wake up automatically when the FPGA fires the IRQ.
  - **Dummy Application (`software/user_app/dummy_app.c`)**: Provided a clear C implementation for the AI team, demonstrating how to `mmap` the memory, pack weights, trigger inference, and benchmark hardware latency using `<sys/time.h>`.

## Next Steps (Hardware Team / FPGA)
- Define the exact MMIO register offsets for the DMA controller inside the FPGA (Source, Dest, Size, Ctrl).
- Export the correct `.dts` file mapping the physical base address and IRQ line under the `ternary,npu-dma` compatible string.
