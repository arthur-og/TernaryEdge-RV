# Makefile for NPU Ternaria LKM - TernaryEdge-RV

ifeq ($(shell uname -m),riscv64)
    CROSS_COMPILE ?= 
    # Try to find riscv headers, fallback to current running kernel
    KDIR_CANDIDATE := $(shell ls -d /usr/src/linux-headers-*-riscv64 2>/dev/null | head -n 1)
    ifeq ($(KDIR_CANDIDATE),)
        KDIR ?= /lib/modules/$(shell uname -r)/build
    else
        KDIR ?= $(KDIR_CANDIDATE)
    endif
else
    CROSS_COMPILE ?= riscv64-linux-gnu-
    KDIR_ALT1 := /usr/riscv64-linux-gnu/lib/modules/$(shell uname -r)/build
    KDIR_ALT2 := /lib/modules/6.18.5+deb14-riscv64/build
    KDIR ?= $(shell if [ -d $(KDIR_ALT2) ]; then echo $(KDIR_ALT2); else echo $(KDIR_ALT1); fi)
endif

CC := $(CROSS_COMPILE)gcc
PWD := $(shell pwd)
obj-m := npu_driver.o
EXTRA_CFLAGS := -DDEBUG

all:
	@echo "Building NPU Driver for RISC-V with compiler: $(CC)"
	@echo "Using kernel headers: $(KDIR)"
	@if [ ! -d "$(KDIR)" ]; then \
		echo "ERROR: Kernel headers not found at $(KDIR)!"; \
		exit 1; \
	fi
	$(MAKE) -C $(KDIR) M=$(PWD) ARCH=riscv CROSS_COMPILE=$(CROSS_COMPILE) modules

clean:
	$(MAKE) -C $(KDIR) M=$(PWD) clean 2>/dev/null || rm -f *.o *.ko *.mod.c *.mod *.order *.symvers .*.cmd
