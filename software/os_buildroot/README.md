# Buildroot OS for Ternary Edge-RV

Buildroot external tree for the Ternary Edge-RV RISC-V SoC.

## Build

```bash
git clone https://github.com/buildroot/buildroot.git
cd buildroot
git checkout 2026.02-882-g98a3912165
make BR2_EXTERNAL=/path/to/TernaryEdge-RV/software/os_buildroot/ ternaryedge_rv_defconfig
make
```

## Test with QEMU

```bash
cd output/images/
./start-qemu.sh
```

Login: `root` (no password).

## SDK / Toolchain

The relocatable toolchain (GCC, kernel headers, libc) was exported and is available on Google Drive.

**Link:** [Google Drive - Toolchain SDK](https://drive.google.com/drive/folders/1lB-13QRCYFjyBBKjwHeiPq-RVhJsn4wY?usp=sharing)

Usage:
```bash
tar xzf riscv32-buildroot-linux-gnu_sdk-buildroot.tar.gz
export CROSS_COMPILE=$(pwd)/sdk/bin/riscv32-buildroot-linux-gnu-
```

To regenerate:
```bash
make sdk
# Output: output/images/riscv32-buildroot-linux-gnu_sdk-buildroot.tar.gz
```
