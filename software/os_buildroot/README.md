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
