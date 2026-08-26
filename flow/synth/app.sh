#!/bin/sh
# Copyright 2026 Yusef Karim
# Solderpad Hardware License, Version 2.1, see LICENSE.md for details.
# SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
#
# Build sw/app and turn it into the flash image the cocotb harness loads into
# the GD25Q128B flash model. Mirrors bootrom.sh's shape: regenerate the sw/inc
# headers this build needs, build, then report.

set -eu

ROOT=${ROOT:-/foss/designs}
SW="$ROOT/sw/app"
CORE="$ROOT/core-v-mcu"
BUILD="$ROOT/flow/build/app"

mkdir -p "$CORE/sw/inc" "$BUILD"

# udma_uart_reg_defs.h is the header this harness needs and nothing else
# generates. soc-defines/periph-bus-defines/pin-table/perdef-json
# and cvmcu-h are regenerated too, the same as bootrom.sh: deterministic from
# gf180-pin-table.csv and perdef.json, so re-running this is a no-op unless
# those changed, not a source of drift.
echo "==> regenerating sw/inc headers against gf180-pin-table.csv"
python3 "$CORE/util/ioscript.py" \
    --soc-defines "$CORE/rtl/includes/pulp_soc_defines.svh" \
    --periph-bus-defines "$CORE/rtl/includes/periph_bus_defines.svh" \
    --pin-table "$CORE/gf180-pin-table.csv" \
    --perdef-json "$CORE/perdef.json" \
    --cvmcu-h "$CORE/sw/inc/core-v-mcu-config.h" >/dev/null

for reg in udma_core:udma_ctrl udma_qspi:udma_qspi udma_uart:udma_uart; do
    dir=${reg%%:*}
    name=${reg##*:}
    python3 "$CORE/util/ioscript.py" \
        --soc-defines "$CORE/rtl/includes/pulp_soc_defines.svh" \
        --periph-bus-defines "$CORE/rtl/includes/periph_bus_defines.svh" \
        --reg-def-csv "$CORE/rtl/udma/$dir/data/${name}_reg_defs.csv" \
        --reg-def-h "$CORE/sw/inc/${name}_reg_defs.h" >/dev/null
done

echo "==> compiling sw/app"
make -C "$SW" INC_GEN="$CORE/sw/inc" BUILD="$BUILD" clean all

echo "==> building the flash image sim/ loads into the GD25Q128B model"
python3 "$SW/gen_flash_image.py" \
    --input "$BUILD/app.bin" \
    --flash-bin "$BUILD/flash_image.bin" \
    --flash-hex "$BUILD/flash_image.hex"

echo
echo "==> app size"
riscv64-unknown-elf-size "$BUILD/app.elf"
