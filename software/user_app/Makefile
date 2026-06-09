# SPDX-License-Identifier: MIT
#
# Makefile for User-Space Inference App — Ternary Edge-RV
#
# =============================================================================
#  PREREQUISITES
# =============================================================================
#  Build the Buildroot toolchain before cross-compiling this application:
#
#      git clone https://github.com/buildroot/buildroot.git
#      cd buildroot
#      git checkout 2026.02-882-g98a3912165
#      make BR2_EXTERNAL=/path/to/TernaryEdge-RV/software/os_buildroot/ \
#          ternaryedge_rv_defconfig
#      make sdk
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
#      # With a custom Buildroot location:
#      make BUILDROOT_DIR=/home/user/code/buildroot
#
#      # Override the compiler directly:
#      make CROSS_COMPILE=riscv32-buildroot-linux-gnu-
#
# =============================================================================
#  VARIABLES (all overridable)
# =============================================================================

# Root of the Buildroot checkout.
# Default assumes TernaryEdge-RV/ and buildroot/ are siblings.
BUILDROOT_DIR       ?= $(abspath $(PWD)/../../../buildroot)
BUILDROOT_OUTPUT     = $(BUILDROOT_DIR)/output

# Cross-compiler prefix — derived from the Buildroot host toolchain by default.
CROSS_COMPILE       ?= $(BUILDROOT_OUTPUT)/host/bin/riscv32-buildroot-linux-gnu-

# Derived tools
CC                  := $(CROSS_COMPILE)gcc

# Build the application statically so that it runs regardless of the target's
# runtime libraries (the toolchain's libc may differ from the target rootfs).
CFLAGS              := -Wall -Wextra -O2 -static
LDFLAGS             := -static

# Target binary and sources
TARGET               = npu_inference
SRC                  = user_app.c

# =============================================================================
#  TARGETS
# =============================================================================

all: check $(TARGET)

$(TARGET): $(SRC)
	@echo ">>> Building user-space inference app ..."
	@echo "    CC : $(CC)"
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $<

clean:
	rm -f $(TARGET)

# ---------------------------------------------------------------------------
#  Pre-build validation
# ---------------------------------------------------------------------------
check:
	@echo "=== [user_app] Pre-build validation ==="
	@echo "  BUILDROOT_DIR : $(BUILDROOT_DIR)"
	@echo "  CROSS_COMPILE : $(CROSS_COMPILE)"
	@echo "  CC            : $(CC)"
	@echo ""
	$(Q)if ! command -v $(CC) >/dev/null 2>&1; then \
		echo "!! ERROR: Cross-compiler not found."; \
		echo "   Tried: $(CC)"; \
		echo ""; \
		echo "   Build the Buildroot toolchain first:"; \
		echo "     cd \$$(BUILDROOT_DIR) && make sdk"; \
		echo ""; \
		echo "   Or override CROSS_COMPILE to point at your"; \
		echo "   RISC-V compiler:"; \
		echo "     make CROSS_COMPILE=riscv32-linux-gnu-"; \
		exit 1; \
	fi
	@echo "  All checks passed."
	@echo ""

.PHONY: all clean check
