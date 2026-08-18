# Ternary Edge-RV: Build, Test and Flash Order

This project uses a repository-local Nix flake and the openXC7 toolchain. Docker
is intentionally not part of the hardware workflow: the FTDI programmer is
easier to access from the host through udev than through a USB-passthrough
container.

## 1. NixOS Host Requirements

Recommended host capacity:

- Nix with flakes enabled;
- x86_64 Linux;
- 16 GB RAM;
- at least 40 GB free disk space for Buildroot downloads, generated output,
  FPGA databases and AI artifacts;
- the RealDigital Urbana board and a data-capable micro-USB cable;
- a separate MicroSD card for the Linux image;
- network access for Nix, Buildroot and the MNIST download.

If flakes are not already enabled, add this to the NixOS configuration:

```nix
nix.settings.experimental-features = [ "nix-command" "flakes" ];
```

Enable the project module in the NixOS configuration:

```nix
imports = [
  /home/arthur/Documents/Projects/TernaryEdge-RV/nix/ternaryedge.nix
];

services.ternaryedge = {
  enable = true;
  user = "arthur";
};
```

Apply it and start a new login session so the group membership is active:

```bash
sudo nixos-rebuild switch
id
lsusb -nn
```

The udev rule covers the FTDI FT2232H IDs used by the Urbana. If the board
reports a different product ID, inspect it with `lsusb -nn` and extend
`nix/ternaryedge.nix` instead of using Docker with `--privileged`.

## 2. Repository Shells

Run commands from the repository root:

```bash
nix develop .#hardware
nix develop .#software
nix develop .#ai
```

The `hardware` shell is for LiteX, RTL simulation, synthesis and programming.
The `software` shell is for Buildroot, QEMU and host-side cross-build support.
The `ai` shell is for the QAT pipeline and generated weights. The exact
package set is defined in `flake.nix`; do not install a second system-wide
toolchain for this repository.

Initialize the two local tool environments once:

```bash
nix develop .#hardware --command ternaryedge-setup-openxc7
nix develop .#ai --command ternaryedge-setup-ai
```

## 3. Validation Order

Do not flash hardware before the lower-level checks pass.

### 3.1 RTL and golden models

```bash
make -C hardware/npu_rtl/sim_cpp all
make -C hardware/npu_rtl/sim_cpp verilog_v2
python3 hardware/npu_rtl/python/golden_model.py
```

The C++ v2 model currently provides the host-side reference checks. The
Verilog testbench must still be run in the selected simulator before treating
the RTL as physically validated.

### 3.2 AI weights

```bash
nix develop .#ai
python3 ai_training/scripts/run_pipeline.py --epochs 20
```

Check that the generated header exists at
`software/user_app/weights.h`. The repository currently documents a known
contract gap: the HAL expects the CPU output-layer arrays while the checked-in
pipeline/header path may only contain the packed ternary layers. Stop and
resolve that mismatch before claiming end-to-end inference.

### 3.3 Buildroot Linux image

Buildroot must live in a writable sibling directory, not in the Nix store:

```bash
cd ..
git clone https://github.com/buildroot/buildroot.git
cd buildroot
git checkout 2026.02-882-g98a3912165

make BR2_EXTERNAL="$PWD/../TernaryEdge-RV/software/os_buildroot" \
  ternaryedge_rv_defconfig
make
```

The full build is required for the kernel tree and `Module.symvers` used by
the out-of-tree driver. The expected cross-compiler is:

```text
../buildroot/output/host/bin/riscv32-buildroot-linux-gnu-gcc
```

### 3.4 Driver, HAL and application

Run these from the repository root after the full Buildroot build:

```bash
BUILDROOT_DIR="$PWD/../buildroot"

make -C software/npu_driver BUILDROOT_DIR="$BUILDROOT_DIR"
make -C software/npu_hal BUILDROOT_DIR="$BUILDROOT_DIR"
make -C software/user_app BUILDROOT_DIR="$BUILDROOT_DIR"
```

The driver requires the Buildroot kernel build tree. The HAL and application
require the Buildroot RV32 cross-compiler. Native compilation is useful only
for syntax checks and does not prove target compatibility.

### 3.5 QEMU smoke test

```bash
cd ../buildroot/output/images
./start-qemu.sh
```

QEMU validates the software image path. It does not validate the Urbana DDR3,
FPGA timing, NPU IRQ, DMA or physical FTDI connection.

## 4. SoC Build and FPGA Programming

Enter the hardware shell and generate the LiteX SoC/bitstream with openXC7:

```bash
cd /home/arthur/Documents/Projects/TernaryEdge-RV
nix develop .#hardware
cd hardware/litex_soc
python3 base_soc.py --build --toolchain openxc7
```

Before this command, run the board-target check:

```bash
ternaryedge-check-litex-board
```

At the time this environment was created, that check fails because upstream
`litex-boards` does not contain `realdigital_urbana`, and this repository does
not yet contain a local `realdigital_urbana` target/platform module. The
missing LiteX board support is a project blocker, not a NixOS dependency. It
must be implemented from the Urbana schematic and official pinout before
synthesis. Do not guess DDR3, UART, SD or FTDI pins.

Before programming, verify that the board is visible:

```bash
openFPGALoader --detect
```

First load the bitstream into SRAM (volatile) so a failed experiment does not
alter the persistent SPI flash:

```bash
python3 base_soc.py --load
```

After the SRAM load and UART check are successful, program the SPI flash:

```bash
python3 base_soc.py --flash
```

The direct loader form is useful for a known generated `.bit`/`.bin` artifact:

```bash
openFPGALoader --board realdigital_urbana path/to/bitstream.bin
```

The exact persistent-flash flag is intentionally delegated to the LiteX
programmer wrapper in `base_soc.py`; do not guess a loader flag for a different
openFPGALoader version.

## 5. UART and Physical Linux Validation

The Urbana console is expected at 115200 baud through the FTDI USB interface.
After programming, identify the serial device and connect with a host serial
tool supplied by the hardware shell:

```bash
ls /dev/ttyUSB* /dev/ttyACM* 2>/dev/null
picocom --baud 115200 /dev/ttyUSB0
```

On the target, the physical validation order is:

```text
boot Linux -> dmesg -> insmod npu_driver.ko -> verify /dev/npu_ternaria
-> run CPU baseline -> run NPU path -> collect CSV measurements
```

Expected driver evidence includes a successful probe, IRQ registration and a
created `/dev/npu_ternaria`. A QEMU boot or a successful FPGA configuration is
not evidence that DMA and IRQ behavior work on the physical NPU.

## 6. MicroSD Is a Separate Flash Operation

Programming the FPGA SPI flash and writing the Linux MicroSD card are separate
operations. The current Buildroot defconfig is QEMU-oriented and still needs a
validated Urbana-specific boot layout before it can be called a production SD
image. Do not run `dd` against a block device until the target device has been
identified with `lsblk` and the partition plan has been reviewed.

The physical SD acceptance gate is:

```text
FAT32 boot partition + Linux Image + Urbana DTB + bootloader
ext4 root partition + driver + HAL + user_app + MNIST data
```

## 7. Copyable Build Prompt

Use the following prompt with an implementation agent after the repository
and NixOS module are available:

```text
Work on the TernaryEdge-RV repository on NixOS.

Goal: produce a reproducible, open-source-only build and flash workflow for
the RealDigital Urbana FPGA (AMD Spartan-7 XC7S50-CSGA324), without Vivado,
Docker, or privileged USB containers.

Use the repository flake and its shells:
  nix develop .#hardware
  nix develop .#software
  nix develop .#ai

Required phases, in this order:
1. Run the C++ and Verilog NPU v2 simulations and the Python golden model.
2. Run the QAT pipeline and verify that software/user_app/weights.h satisfies
   every symbol expected by the HAL, including the CPU output layer.
3. Clone Buildroot beside the repository at commit
   2026.02-882-g98a3912165. Configure it with
   software/os_buildroot as BR2_EXTERNAL and build the complete image.
4. Cross-compile npu_driver, npu_hal and user_app with the generated
   riscv32-buildroot-linux-gnu toolchain. Do not claim success if the kernel
   tree or Module.symvers is missing.
5. Build hardware/litex_soc/base_soc.py with the openXC7/Yosys/nextpnr flow.
   Run ternaryedge-check-litex-board first. If realdigital_urbana is missing,
   stop and implement the target/platform from the official Urbana schematic
   and pinout; do not invent board constraints. Confirm that the generated
   chip database matches xc7s50csga324 and stop with a concrete diagnostic if
   it does not.
6. Run openFPGALoader --detect, load SRAM with base_soc.py --load, validate
   UART at 115200 baud, and only then use base_soc.py --flash for SPI flash.
7. Treat MicroSD preparation as a separate acceptance gate. Do not use dd
   until the Urbana boot partition layout, DTB, kernel and rootfs have been
   validated.
8. On the target, validate dmesg, insmod, /dev/npu_ternaria, CPU inference,
   NPU inference and benchmark CSV output.

Constraints:
- Never invent a successful synthesis, boot, IRQ, DMA or power result.
- Preserve existing project changes and do not alter unrelated files.
- Report the exact command, artifact path and failure cause for every blocked
  phase.
- Keep the OpenXC7 path reproducible in the flake; do not silently fall back
  to Vivado or Docker.

Success means that each phase has an artifact and an observed verification
result, not merely that a command was started.
```
