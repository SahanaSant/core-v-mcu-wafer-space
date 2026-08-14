#!/bin/sh
# Copyright 2026 Yusef Karim
# Solderpad Hardware License, Version 2.1, see LICENSE.md for details.
# SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
#
# Build sw/bootrom, convert it to rtl/gf180mcu/gf180_bootrom.sv, and report the
# real ROM size against ticket 04's 2 KiB estimate. Runs inside the toolchain
# container; invoke it as `make bootrom`.

set -eu

ROOT=${ROOT:-/foss/designs}
SW="$ROOT/sw/bootrom"
CORE="$ROOT/core-v-mcu"
BUILD="$ROOT/flow/build/bootrom"

mkdir -p "$CORE/sw/inc" "$BUILD"

# The submodule's own `make sw` targets nexys-pin-table.csv, an FPGA board pin
# table this GF180 port has no reason to track: ticket 06 already diverged
# N_UART/N_GPIO/N_I2CM from what that table assumes, which is why `make sw`'s
# default recipe throws a KeyError on PERIO_UART1_TX today. gf180-pin-table.csv
# is this chip's own pin table, so headers are regenerated against it directly
# rather than depending on that recipe. --peripheral-defines is left off: it's
# an *output* flag (ioscript.py would happily overwrite the tracked
# pulp_peripheral_defines.svh with a byte-identical copy plus a fresh
# BUILD_DATE/BUILD_TIME stamp) and cvmcu_h generation doesn't need it.
echo "==> regenerating sw/inc headers against gf180-pin-table.csv"
python3 "$CORE/util/ioscript.py" \
    --soc-defines "$CORE/rtl/includes/pulp_soc_defines.svh" \
    --periph-bus-defines "$CORE/rtl/includes/periph_bus_defines.svh" \
    --pin-table "$CORE/gf180-pin-table.csv" \
    --perdef-json "$CORE/perdef.json" \
    --cvmcu-h "$CORE/sw/inc/core-v-mcu-config.h" >/dev/null

for reg in udma_core:udma_ctrl udma_qspi:udma_qspi; do
    dir=${reg%%:*}
    name=${reg##*:}
    python3 "$CORE/util/ioscript.py" \
        --soc-defines "$CORE/rtl/includes/pulp_soc_defines.svh" \
        --periph-bus-defines "$CORE/rtl/includes/periph_bus_defines.svh" \
        --reg-def-csv "$CORE/rtl/udma/$dir/data/${name}_reg_defs.csv" \
        --reg-def-h "$CORE/sw/inc/${name}_reg_defs.h" >/dev/null
done

echo "==> compiling sw/bootrom"
make -C "$SW" INC_GEN="$CORE/sw/inc" BUILD="$BUILD" clean all

echo "==> generating rtl/gf180mcu/gf180_bootrom.sv"
python3 "$SW/gen_bootrom.py" \
    --input "$BUILD/bootrom.bin" \
    --output "$ROOT/rtl/gf180mcu/gf180_bootrom.sv" \
    --golden "$BUILD/gf180_bootrom_golden.mem" \
    --golden-words-vh "$BUILD/gf180_bootrom_golden.vh"

echo
echo "==> ROM size"
riscv64-unknown-elf-size "$BUILD/bootrom.elf"
wc -c "$BUILD/bootrom.bin"

# ROM <-> compiled-binary equivalence check under Icarus (ticket 16 pinned it
# for every gate-level check here: the PDK's icgtp model needs a UDP-capable
# simulator). Proves the generated case statement is a lossless, correctly-
# timed encoding of the image, not that the CPU actually boots it -- see
# tb/bootrom_tb.sv's header for why that's a separate, larger piece of work.
echo
echo "==> simulating gf180_bootrom.sv against the compiled image (Icarus)"
cd "$ROOT"
iverilog -g2012 -I"$BUILD" -o "$BUILD/bootrom_tb.vvp" \
    rtl/gf180mcu/gf180_bootrom.sv sw/bootrom/tb/bootrom_tb.sv
vvp "$BUILD/bootrom_tb.vvp"
