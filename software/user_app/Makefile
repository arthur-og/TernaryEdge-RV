BUILDROOT_DIR       ?= $(abspath $(PWD)/../../../buildroot)
BUILDROOT_OUTPUT     = $(BUILDROOT_DIR)/output
CROSS_COMPILE       ?= $(BUILDROOT_OUTPUT)/host/bin/riscv32-buildroot-linux-gnu-
CC                  := $(CROSS_COMPILE)gcc
AR                  ?= $(CROSS_COMPILE)ar
CFLAGS              ?= -Wall -Wextra -O2
LDFLAGS             ?=

ifneq (,$(findstring riscv,$(CC)))
CFLAGS              += -static -march=rv32ima -mabi=ilp32
LDFLAGS             += -static
endif

TARGET               = npu_inference
SRC                  = user_app.c
NPU_HAL_DIR          = $(abspath $(CURDIR)/../npu_hal)

all: check $(TARGET)

$(TARGET): $(SRC) $(NPU_HAL_DIR)/libnpu_hal.a
	$(CC) $(CFLAGS) -I$(NPU_HAL_DIR) $(LDFLAGS) -o $@ $< -L$(NPU_HAL_DIR) -lnpu_hal -lm

$(NPU_HAL_DIR)/libnpu_hal.a:
	$(MAKE) -C $(NPU_HAL_DIR) CC=$(CC) AR=$(AR)

clean:
	rm -f $(TARGET)

check:
	$(Q)if ! command -v $(CC) >/dev/null 2>&1; then \
		echo "Cross-compiler not found: $(CC)"; \
		echo "Override CROSS_COMPILE or build Buildroot toolchain first."; \
		exit 1; \
	fi

.PHONY: all clean check
