CC ?= gcc

CPPFLAGS ?=
CFLAGS ?= -std=c11 -Wall -Wextra -Wpedantic -Werror -O2
INCLUDES := -I$(CURDIR)/../include -I$(CURDIR)/../user_app
WEIGHTS_CFLAGS := $(CFLAGS)
ifneq (,$(findstring clang,$(shell $(CC) --version 2>/dev/null)))
WEIGHTS_CFLAGS += -Wno-invalid-utf8
endif

IOCTL_SOURCE := npu_ioctl_abi_check.c
IOCTL_BINARY := npu_ioctl_abi_check
WEIGHTS_SOURCE := weights_header_contract_check.c
WEIGHTS_BINARY := weights_header_contract_check

.PHONY: ioctl-abi weights-header clean

ioctl-abi: $(IOCTL_BINARY)
	@./$(IOCTL_BINARY)

$(IOCTL_BINARY): $(IOCTL_SOURCE) ../include/npu_ioctl.h
	$(CC) $(CPPFLAGS) $(CFLAGS) $(INCLUDES) -o $@ $<

weights-header:
	@rm -f $(WEIGHTS_BINARY)
	@if ! $(CC) $(CPPFLAGS) $(WEIGHTS_CFLAGS) $(INCLUDES) -o $(WEIGHTS_BINARY) $(WEIGHTS_SOURCE); then \
		printf '%s\n' 'weights-header: compiler failure (not the expected contract diagnostic)' >&2; \
		exit 1; \
	fi
	@./$(WEIGHTS_BINARY)

$(WEIGHTS_BINARY): $(WEIGHTS_SOURCE) ../user_app/weights.h
	$(CC) $(CPPFLAGS) $(WEIGHTS_CFLAGS) $(INCLUDES) -o $@ $<

clean:
	rm -f $(IOCTL_BINARY) $(WEIGHTS_BINARY)
