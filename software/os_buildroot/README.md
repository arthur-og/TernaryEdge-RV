# Buildroot OS for Ternary Edge-RV

This directory is a **Buildroot external tree** that produces a custom embedded
Linux system for the Ternary Edge-RV RISC-V SoC. It contains the kernel
configuration, root filesystem skeleton, and all patches needed to boot Linux
on the VexRiscv RV32IMA platform.

## Current Operational Ownership

Gildo owns the OS and Buildroot configuration, HAL and CPU classifier
integration, MicroSD image preparation and Linux boot. Gustavo owns the RV32
cross-compilation workflow, kernel driver build and physical validation
coordination, as well as the AI export and `weights.h` contract. Arthur owns
RTL, LiteX, synthesis and bitstream work. Gilvan's QAT, ternary-packing and
C++ Golden Model v2 work is historical credit only.

## Prerequisites

- Git, `make`, `gcc`, `g++`, and standard build tools.
- ~10 GB of free disk space (for the Buildroot source + build output).
- Internet connection (Buildroot downloads sources on the fly).

## Quick Start — Full Build

```bash
# 1. Clone Buildroot at the required commit
git clone https://github.com/buildroot/buildroot.git
cd buildroot
git checkout 2026.02-882-g98a3912165

# 2. Configure with the Ternary Edge-RV external tree
make BR2_EXTERNAL=/absolute/path/to/TernaryEdge-RV/software/os_buildroot/ \
    ternaryedge_rv_defconfig

# 3. Build everything (kernel, toolchain, rootfs)
#    This takes 45–90 minutes on a modern machine.
make
```

After the build completes:

| Artifact | Location | Description |
|----------|----------|-------------|
| Linux kernel image | `output/images/Image` | Bootable RISC-V kernel |
| RootFS (cpio) | `output/images/rootfs.cpio` | Initramfs-based root filesystem |
| Device Tree Blob | `output/images/` | Generated from the in-kernel DTS |
| QEMU start script | `output/images/start-qemu.sh` | Launches the system in QEMU |
| Cross-compiler | `output/host/bin/riscv32-buildroot-linux-gnu-*` | Toolchain for driver + user app |
| Kernel build tree | `output/build/linux-*/` | Needed for out-of-tree kernel modules |

## Testing the System in QEMU

```bash
cd output/images/
./start-qemu.sh
```

Login as `root` (no password). You should see a shell prompt from the
RISC-V Linux system running under emulation.

## Toolchain — Build Your Own

Every team member who needs to cross-compile code for the RISC-V target
builds their **own toolchain** from this external tree. No binary SDK needs
to be distributed — it all comes from Git.

There are two levels of build, depending on what you need:

### Option A: Toolchain only (user-space apps — ~30 min)

If you only need to compile C applications such as `user_app.c`:

```bash
cd buildroot
make BR2_EXTERNAL=/path/to/TernaryEdge-RV/software/os_buildroot/ \
    ternaryedge_rv_defconfig
make sdk
```

The compiler will be at:
```
output/host/bin/riscv32-buildroot-linux-gnu-gcc
```

Use it directly or set `CROSS_COMPILE`:

```bash
export CROSS_COMPILE=$(pwd)/output/host/bin/riscv32-buildroot-linux-gnu-
```

### Option B: Full build (kernel modules — ~60 min)

If you need to compile the kernel driver (`npu_driver.ko`), you also need the
kernel build tree produced by a complete `make`:

```bash
cd buildroot
make BR2_EXTERNAL=/path/to/TernaryEdge-RV/software/os_buildroot/ \
    ternaryedge_rv_defconfig
make                     # <- builds everything, including the kernel
```

After this, point `KDIR` at the kernel build output:

```bash
export KDIR=$(pwd)/output/build/linux-custom
```

or let the Makefiles in `software/npu_driver/` auto-detect it.

### Which option does each team member need?

| Person | Needs | Build command |
|--------|-------|---------------|
| **Gildo** | OS, Buildroot, HAL, classifier, MicroSD and boot | `make` |
| **Gustavo** | Driver, AI export, Golden Model regression and RV32 cross-compilation | `make` |
| **Arthur** | Hardware and QEMU firmware support | `make sdk` |
| **Gilvan** | No current build ownership; historical contributor and fourth Paper 1 author | N/A |

## Recommended Directory Layout

For the Makefiles' auto-detection to work, keep Buildroot as a sibling of the
project root:

```
your-workspace/
├── buildroot/                 # git clone of Buildroot
└── TernaryEdge-RV/            # this repository
    └── software/
        ├── npu_driver/        # make → auto-finds buildroot/../
        ├── user_app/          # make → auto-finds buildroot/../
        └── os_buildroot/      # external tree (used FROM buildroot)
```

If your layout differs, override `BUILDROOT_DIR` on every `make` invocation:

```bash
make BUILDROOT_DIR=/home/user/code/buildroot
```

## Customizing the Build

### Changing kernel options

```bash
make linux-menuconfig     # opens the kernel config editor
```

### Adding/removing packages

```bash
make menuconfig            # Buildroot package selection
```

### Rebuilding only the kernel

```bash
make linux-rebuild
```

### Cleaning

```bash
make clean                 # removes output/ — full rebuild needed afterward
```

## References

- [Buildroot Manual](https://buildroot.org/downloads/manual/manual.html)
- [VexRiscv RISC-V Core](https://github.com/SpinalHDL/VexRiscv)
- [LiteX SoC Generator](https://github.com/enjoy-digital/litex)
