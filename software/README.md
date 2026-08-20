# Software Stack

The user-space and kernel-space software for Ternary Edge-RV, organized by
domain.

## Current Operational Ownership

- **Gildo:** OS and Buildroot, NPU HAL, CPU classifier, MicroSD image and Linux boot.
- **Gustavo:** AI pipeline maintenance, weight export and `weights.h` contract, Golden Model regression and maintenance, kernel driver, RV32 cross-compilation, physical validation coordination, CPU-versus-NPU benchmarks, and Paper 1 results and discussion.
- **Arthur:** RTL, LiteX SoC, synthesis and bitstream.
- **Gilvan:** Historical QAT, ternary packing, C++ Golden Model v2 contribution, and fourth Paper 1 authorship only.

## Directories

| Directory | Description |
|-----------|-------------|
| `npu_hal/` | NPU Hardware Abstraction Layer (`libnpu_hal.a`) + classifier + weights loader |
| `npu_driver/` | Loadable Kernel Module (LKM) — character device, DMA, IRQ |
| `user_app/` | User-space inference & benchmark application |
| `os_buildroot/` | Buildroot external tree (kernel config, device tree, packages) |
| `include/` | Shared headers (e.g. `npu_ioctl.h`) |

## Software Stack

```
user_app (inference + benchmark)
    |
    v  (uses)
NPU HAL (npu_init -> npu_predict -> npu_deinit)
    |  |- npu_classifier (256->10 output layer)
    |  |- npu_weights    (weight loading)
    |
    v  (ioctl / mmap)
npu_driver (/dev/npu_ternaria, IRQ, DMA)
    |
    v  (Wishbone bus)
NPU v2 hardware (64-MAC design target, Layer Sequencer)
```

The 64-MAC array, zero-DSP goal, throughput and speedup are design intent or
pending synthesis and measurement. There is no proven FPGA end-to-end
inference or CPU-versus-NPU benchmark at present.

## Build Overview

Each component builds against the Buildroot host toolchain:

```bash
# Kernel module
cd software/npu_driver && make

# NPU HAL static library
cd software/npu_hal && make

# User application (links against libnpu_hal.a)
cd software/user_app && make
```

See each subdirectory's README for details.

## License

MIT — see the repository `LICENSE` file.
