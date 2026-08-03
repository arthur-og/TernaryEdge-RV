# Software Stack

The user-space and kernel-space software for Ternary Edge-RV, organized by
domain.

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
NPU v2 hardware (64 MACs, Layer Sequencer)
```

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