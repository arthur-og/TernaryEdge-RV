# Ternary Edge-RV: Build, Test and Flash Order

This project uses a repository-local Nix flake and pure Nix hardware shells.
Docker is intentionally not part of the hardware workflow: the FTDI programmer
is easier to access from the host through udev than through a USB-passthrough
container.

## Current Operational Ownership

- **Arthur:** RTL, LiteX SoC generation, synthesis, bitstream and hardware design.
- **Gildo:** OS, Buildroot, HAL, CPU classifier, MicroSD image and Linux boot.
- **Gustavo:** AI pipeline maintenance, weight export and `weights.h` contract, C++ Golden Model regression and maintenance, kernel driver, RV32 cross-compilation, physical validation coordination, CPU-versus-NPU benchmarks, and Paper 1 results and discussion.
- **Gilvan:** Historical QAT, ternary packing, C++ Golden Model v2 contribution, and fourth Paper 1 authorship only.

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
nix develop path:.#vivado
```

The `hardware` shell is for LiteX, RTL simulation, generic checks and programming.
The `software` shell is for Buildroot, QEMU and host-side cross-build support.
The `ai` shell is for the QAT pipeline and generated weights. The exact
package set is defined in `flake.nix`; do not install a second system-wide
toolchain for this repository.

The Vivado shell is a pure Nix wrapper. `nix/vivado.nix` is currently
untracked, so `nix develop path:.#vivado` is the validation form until that
file is included in a future commit. Do not stage it as part of this document
update.

Initialize the two local tool environments once:

```bash
nix develop .#hardware --command ternaryedge-setup-openxc7
nix develop .#ai --command ternaryedge-setup-ai
```

## 3. Validation Order

Do not flash hardware before the lower-level checks pass.

### 3.1 Hardware verification, first gate

Run the current RTL checks from the repository root. This is Arthur's
canonical lightweight hardware gate. It runs the focused Icarus tests, the
16, 32 and 64 PE top matrix, and the Verilator lint matrix.

```bash
nix develop .#hardware --command make -C hardware/npu_rtl test test_matrix lint_matrix
```

This gate does not run the protected `sim_cpp` or Python golden-model paths.
Those remain separate team-owned reference checks and are not evidence of
current physical hardware behavior. The historical Verilog 4/4 result is
retained as history only.

The generic Yosys synthesis/check flow and its 16/32/64 PE matrix pass after
the current RTL changes. These host checks prove elaboration and generic
synthesis only; current physical resource metrics still require Vivado.

### 3.2 AI weights

```bash
nix develop .#ai
python3 ai_training/scripts/run_pipeline.py --epochs 20
```

Check that the generated header exists at
`software/user_app/weights.h`. The current header has the FP32 symbols expected
by the HAL, but its fallback values, including `0.01` and `0.1`, are not
validated trained parameters. Gustavo owns this export and contract check.
Resolve the parameter validation gap before claiming end-to-end inference.

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

Current blocker: the Buildroot RV32 compiler is absent in this environment, so
driver, HAL and application cross-compilation remain pending.

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

Gustavo owns the RV32 cross-compilation and driver validation workflow. Gildo
owns the OS, Buildroot, HAL, classifier, MicroSD image and Linux boot path.

### 3.5 QEMU smoke test

```bash
cd ../buildroot/output/images
./start-qemu.sh
```

QEMU validates the software image path. It does not validate the Urbana DDR3,
FPGA timing, NPU IRQ, DMA or physical FTDI connection.

## 4. SoC Build and FPGA Programming

The frozen address contract is DDR `0x40000000`, NPU `0x80000000`, IRQ 10.
The local Urbana provenance check covers device `xc7s50csga324-1` and must
pass before the heavy user-run Vivado step.

Run the board-target check from the repository root:

```bash
nix develop .#hardware --command ternaryedge-check-litex-board
```

The local Urbana target and device provenance are now validated. Do not
replace them with guessed DDR3, UART, SD or FTDI pins.

Vivado is a heavy user-run step. From the repository root, validate the pure
Nix wrapper and then run the build:

```bash
nix develop path:.#vivado
nix develop path:.#vivado --command python3 hardware/litex_soc/base_soc.py --build --toolchain vivado
```

After the user-run build, apply the report acceptance gate:

```bash
python3 hardware/litex_soc/check_vivado_reports.py
```

Historical Vivado reports are stale and rejected. Their generated Tcl omitted
`postprocess_unit.v`, the artifacts predate the current RTL, WNS was
`-7.392 ns`, and TNS was `-35888.277 ns`. They cannot establish current
resources, timing, bitstream generation or physical behavior.

Before programming, verify that the board is visible:

```bash
openFPGALoader --detect
```

The current blocker is `device not found` from this command. Do not treat the
historical FTDI detection record as current board evidence.

First load the bitstream into SRAM (volatile) so a failed experiment does not
alter the persistent SPI flash:

```bash
python3 hardware/litex_soc/base_soc.py --load
```

After the SRAM load and UART check are successful, program the SPI flash:

```bash
python3 hardware/litex_soc/base_soc.py --flash
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

Gustavo coordinates this physical validation with Arthur and Gildo. No FPGA
end-to-end inference or CPU-versus-NPU benchmark is current evidence until the
target procedure produces an observed result.

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

Use the following handoff procedure after the repository and NixOS module are
available. It describes user-run steps and does not claim that they have
already completed:

```text
Work on the TernaryEdge-RV repository on NixOS.

Goal: produce a reproducible Vivado build and flash workflow for the RealDigital
Urbana FPGA (AMD Spartan-7 XC7S50-CSGA324), using the pure Nix wrapper and
without Docker or privileged USB containers.

Use the repository flake and its shells:
  nix develop .#hardware
  nix develop .#software
  nix develop .#ai
  nix develop path:.#vivado

Required phases, in this order:
1. Run the canonical hardware gate:
   nix develop .#hardware --command make -C hardware/npu_rtl test test_matrix lint_matrix
   Do not substitute the protected sim_cpp or Python golden-model paths.
2. Gustavo runs the AI pipeline and verifies that software/user_app/weights.h
   satisfies every symbol expected by the HAL, including the CPU output layer.
   The current FP32 values are fallbacks, not validated trained parameters.
3. Clone Buildroot beside the repository at commit
   2026.02-882-g98a3912165. Configure it with
   software/os_buildroot as BR2_EXTERNAL and build the complete image.
4. Cross-compile npu_driver, npu_hal and user_app with the generated
   riscv32-buildroot-linux-gnu toolchain. Do not claim success if the kernel
   tree or Module.symvers is missing.
5. Run nix develop .#hardware --command ternaryedge-check-litex-board first. Confirm the local Urbana provenance
   for xc7s50csga324-1. The frozen map is DDR 0x40000000, NPU 0x80000000, IRQ 10.
6. Run the heavy user step from the repository root:
   nix develop path:.#vivado --command python3 hardware/litex_soc/base_soc.py --build --toolchain vivado
   Then run python3 hardware/litex_soc/check_vivado_reports.py. Reject stale
   reports that omit postprocess_unit.v or predate the current RTL.
7. Run openFPGALoader --detect, load SRAM with base_soc.py --load, validate
   UART at 115200 baud, and only then use base_soc.py --flash for SPI flash.
8. Treat MicroSD preparation as a separate acceptance gate. Do not use dd
   until the Urbana boot partition layout, DTB, kernel and rootfs have been
   validated.
9. On the target, Gustavo coordinates validation of dmesg, insmod,
   /dev/npu_ternaria, CPU inference, NPU inference and benchmark CSV output
   with Arthur and Gildo. Do not claim these results before they are observed.

Constraints:
- Never invent a successful synthesis, boot, IRQ, DMA or power result.
- Preserve existing project changes and do not alter unrelated files.
- Report the exact command, artifact path and failure cause for every blocked
  phase.
- Keep the Vivado path reproducible in the pure Nix wrapper; do not silently
  fall back to Docker.

Success means that each phase has an artifact and an observed verification
result, not merely that a command was started.
```
