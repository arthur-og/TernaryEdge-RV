BUILDROOT_DIR       ?= $(abspath $(PWD)/../../../buildroot)
BUILDROOT_OUTPUT     = $(BUILDROOT_DIR)/output
CROSS_COMPILE       ?= $(BUILDROOT_OUTPUT)/host/bin/riscv32-buildroot-linux-gnu-

ifeq ($(origin CC), default)
CC                  := $(CROSS_COMPILE)gcc
endif
ifeq ($(origin AR), default)
AR                  := $(CROSS_COMPILE)ar
endif

CFLAGS              ?= -Wall -Wextra -O2 -static
CPPFLAGS            += -I$(CURDIR)/../user_app
ifneq (,$(findstring riscv,$(CC)))
CFLAGS              += -march=rv32ima -mabi=ilp32
endif
LIBNAME             := libnpu_hal.a

SRCS                := npu_hal.c npu_classifier.c npu_weights.c
OBJS                := $(SRCS:.c=.o)

all: $(LIBNAME)

$(LIBNAME): $(OBJS)
	$(AR) rcs $@ $^

%.o: %.c
	$(CC) $(CPPFLAGS) $(CFLAGS) -c -o $@ $<

clean:
	rm -f $(OBJS) $(LIBNAME)

.PHONY: all clean
