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
NPU v2 integrated source-level RTL (64 ternary PEs, Layer Sequencer)
```

The canonical RTL integrates 64 ternary PEs, a registered 64-to-1 tree, a scalar
INT32 accumulator, banked activations, a three-stage postprocessor, up to eight
software-programmed descriptors, and 17 MMIO offsets from `0x00` through
`0x40`. Its bounded single-beat Wishbone Classic DMA uses `CTI=000`,
`BTE=00`, downstream `ERR`, and a 256-cycle timeout. Focused
Icarus tests and the 16/32/64-PE matrix pass, including a production-sized
`784->1024->512->256` regression with nonuniform high-row weights: outputs
0..254 equal `65024`, while output 255 equals `-65024`. Verilator lint, generic
Yosys synthesis and `synth_matrix` pass, and
the report-gate unit tests pass 12/12.

The native HAL and user-app compilation status is host-only source and API
evidence, separate from the unverified RV32 cross-build and physical FPGA
behavior. Vivado resources and timing, bitstream, board and
Linux boot, physical IRQ/DMA, inference, latency, throughput, benchmarks,
power, and energy remain pending. The historical C++ v2 result of 21/21 is
secondary host evidence, not canonical RTL proof.

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
