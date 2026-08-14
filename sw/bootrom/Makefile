# Copyright 2026 Yusef Karim
# Solderpad Hardware License, Version 2.1, see LICENSE.md for details.
# SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
#
# Builds inside the toolchain container; invoke via `make bootrom` at the repo
# root (flow/synth/bootrom.sh drives this Makefile after regenerating the
# headers INC_GEN points at). riscv64-unknown-elf-gcc is the container's only
# RISC-V toolchain -- there is no riscv32-corev-elf-gcc, which is what
# core-v-mcu/a2_boot/Makefile assumed. -march=rv32imc -mabi=ilp32 targets the
# CV32E40P's RV32IMC configuration through it.

CC      = riscv64-unknown-elf-gcc
OBJCOPY = riscv64-unknown-elf-objcopy
SIZE    = riscv64-unknown-elf-size

INC_GEN ?= ../../core-v-mcu/sw/inc
BUILD   ?= .

ARCH    = -march=rv32imc -mabi=ilp32
CFLAGS  = $(ARCH) -Os -g -Wall -ffunction-sections -fdata-sections \
          -Iinclude -I$(INC_GEN)
LDFLAGS = $(ARCH) -nostartfiles -nostdlib -T boot.ld \
          -Wl,--gc-sections -Wl,-Map,$(BUILD)/bootrom.map

SRCS = main.c crc.c spi.c
OBJS = $(addprefix $(BUILD)/,$(SRCS:.c=.o)) $(BUILD)/crt0.o

all: $(BUILD)/bootrom.elf $(BUILD)/bootrom.bin

$(BUILD)/%.o: %.c | $(BUILD)
	$(CC) $(CFLAGS) -c -o $@ $<

$(BUILD)/crt0.o: crt0.S | $(BUILD)
	$(CC) $(CFLAGS) -c -o $@ $<

$(BUILD)/bootrom.elf: $(OBJS) boot.ld
	$(CC) $(LDFLAGS) -o $@ $(OBJS)
	$(SIZE) $@

$(BUILD)/bootrom.bin: $(BUILD)/bootrom.elf
	$(OBJCOPY) -O binary $< $@

$(BUILD):
	mkdir -p $(BUILD)

clean:
	rm -f $(BUILD)/*.o $(BUILD)/bootrom.elf $(BUILD)/bootrom.bin $(BUILD)/bootrom.map

.PHONY: all clean
