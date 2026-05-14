# Makefile for User-Space Inference App

CROSS_COMPILE ?= riscv64-linux-gnu-
CC = $(CROSS_COMPILE)gcc
CFLAGS = -Wall -Wextra -O2

TARGET = dummy_app
SRC = dummy_app.c

all: $(TARGET)

$(TARGET): $(SRC)
	$(CC) $(CFLAGS) -o $(TARGET) $(SRC)

clean:
	rm -f $(TARGET)
