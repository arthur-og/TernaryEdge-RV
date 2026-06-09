# SPDX-License-Identifier: MIT
#
# Makefile for NPU Ternary Kernel Module — Ternary Edge-RV
#
# =============================================================================
#  PREREQUISITES
# =============================================================================
#  Before compiling this out-of-tree module, you need a full Buildroot build
#  that produces both the cross-compiler AND the kernel build tree:
#
#      git clone https://github.com/buildroot/buildroot.git
#      cd buildroot
#      git checkout 2026.02-882-g98a3912165
#      make BR2_EXTERNAL=/path/to/TernaryEdge-RV/software/os_buildroot/ \
#          ternaryedge_rv_defconfig
#      make
#
#  See software/os_buildroot/README.md for detailed instructions.
#
# =============================================================================
#  USAGE
# =============================================================================
#  From this directory:
#
#      # When Buildroot is a sibling of the project root (default layout):
#      make
#
#      # When Buildroot lives elsewhere:
#      make BUILDROOT_DIR=/home/user/code/buildroot
#
#      # All variables can be overridden individually:
#      make CROSS_COMPILE=riscv32-buildroot-linux-gnu- \
#           KDIR=/path/to/output/build/linux-custom
#
# =============================================================================
#  VARIABLES (all overridable from the command line or environment)
# =============================================================================

# Root of the Buildroot checkout.
# Default assumes TernaryEdge-RV/ is a sibling of buildroot/.
BUILDROOT_DIR       ?= $(abspath $(PWD)/../../../buildroot)
BUILDROOT_OUTPUT     = $(BUILDROOT_DIR)/output

# Cross-compiler prefix — derived from the Buildroot host toolchain by default.
CROSS_COMPILE       ?= $(BUILDROOT_OUTPUT)/host/bin/riscv32-buildroot-linux-gnu-

# Kernel build tree — auto-detected from the Buildroot linux-* output directory.
# Falls back to a placeholder if the build hasn't run yet (validated in `check`).
KDIR                ?= $(firstword $(wildcard $(BUILDROOT_OUTPUT)/build/linux-*))

# Target architecture (fixed to RISC-V for this project).
ARCH                := riscv

# Derived tools
CC                  := $(CROSS_COMPILE)gcc
PWD                 := $(shell pwd)

# Kernel module sources
obj-m               += npu_driver.o

# Compiler flags
EXTRA_CFLAGS        += -DDEBUG

# =============================================================================
#  TARGETS
# =============================================================================

all: check
	@echo ">>> Building npu_driver.ko ..."
	$(MAKE) -C $(KDIR) M=$(PWD) \
		ARCH=$(ARCH) \
		CROSS_COMPILE=$(CROSS_COMPILE) \
		modules

clean:
	$(MAKE) -C $(KDIR) M=$(PWD) clean 2>/dev/null || \
		rm -f *.o *.ko *.mod.c *.mod *.order *.symvers .*.cmd

# ---------------------------------------------------------------------------
#  Pre-build validation — fails early with actionable diagnostics.
# ---------------------------------------------------------------------------
check:
	@echo "=== [npu_driver] Pre-build validation ==="
	@echo "  BUILDROOT_DIR : $(BUILDROOT_DIR)"
	@echo "  CROSS_COMPILE : $(CROSS_COMPILE)"
	@echo "  CC            : $(CC)"
	@echo "  KDIR          : $(KDIR)"
	@echo "  ARCH          : $(ARCH)"
	@echo ""
	$(Q)if ! command -v $(CC) >/dev/null 2>&1; then \
		echo "!! ERROR: Cross-compiler not found."; \
		echo "   Tried: $(CC)"; \
		echo ""; \
		echo "   Make sure you have completed a Buildroot build that"; \
		echo "   produces the host toolchain:"; \
		echo "     cd \$$(BUILDROOT_DIR) && make"; \
		echo ""; \
		echo "   Or override CROSS_COMPILE if your toolchain lives"; \
		echo "   elsewhere:"; \
		echo "     make CROSS_COMPILE=/path/to/riscv32-linux-gnu-"; \
		exit 1; \
	fi
	$(Q)if [ ! -d "$(KDIR)" ]; then \
		echo "!! ERROR: Kernel build tree not found."; \
		echo "   Tried: $(KDIR)"; \
		echo ""; \
		echo "   The full Buildroot build must be completed before"; \
		echo "   building the driver:"; \
		echo "     cd \$$(BUILDROOT_DIR) && make"; \
		echo ""; \
		echo "   Or override KDIR to point at a pre-built kernel:"; \
		echo "     make KDIR=/path/to/linux-build"; \
		exit 1; \
	fi
	$(Q)if [ ! -f "$(KDIR)/Module.symvers" ]; then \
		echo "!! WARNING: Module.symvers not found in KDIR."; \
		echo "   The kernel may not be fully built, or the wrong"; \
		echo "   directory was specified."; \
		echo "   Path: $(KDIR)/Module.symvers"; \
		echo ""; \
	fi
	@echo "  All checks passed."
	@echo ""

.PHONY: all clean check
