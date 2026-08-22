# Copyright 2026 Yusef Karim
# Solderpad Hardware License, Version 2.1, see LICENSE.md for details.
# SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
#
# Builds ticket 31's app image: the payload sw/bootrom/main.c copies from
# flash and jumps to. Mirrors sw/bootrom/Makefile (same toolchain, same
# -march), invoked by flow/synth/app.sh the way bootrom.sh drives
# sw/bootrom/Makefile.

CC      = riscv64-unknown-elf-gcc
OBJCOPY = riscv64-unknown-elf-objcopy
SIZE    = riscv64-unknown-elf-size

INC_GEN ?= ../../core-v-mcu/sw/inc
BUILD   ?= .

ARCH    = -march=rv32imc -mabi=ilp32
CFLAGS  = $(ARCH) -Os -g -Wall -ffunction-sections -fdata-sections \
          -Iinclude -I$(INC_GEN)
LDFLAGS = $(ARCH) -nostartfiles -nostdlib -T app.ld \
          -Wl,--gc-sections -Wl,-Map,$(BUILD)/app.map

# crt0.o first: _start has to be the first symbol *(.text*) emits, and ld
# places input sections in link-line order within one output section.
SRCS = main.c uart.c sram_test.c
OBJS = $(BUILD)/crt0.o $(addprefix $(BUILD)/,$(SRCS:.c=.o))

all: $(BUILD)/app.elf $(BUILD)/app.bin

$(BUILD)/%.o: %.c | $(BUILD)
	$(CC) $(CFLAGS) -c -o $@ $<

$(BUILD)/crt0.o: crt0.S | $(BUILD)
	$(CC) $(CFLAGS) -c -o $@ $<

$(BUILD)/app.elf: $(OBJS) app.ld
	$(CC) $(LDFLAGS) -o $@ $(OBJS)
	$(SIZE) $@

$(BUILD)/app.bin: $(BUILD)/app.elf
	$(OBJCOPY) -O binary $< $@

$(BUILD):
	mkdir -p $(BUILD)

clean:
	rm -f $(BUILD)/*.o $(BUILD)/app.elf $(BUILD)/app.bin $(BUILD)/app.map

.PHONY: all clean
