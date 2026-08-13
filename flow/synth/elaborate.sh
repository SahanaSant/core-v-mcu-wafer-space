#!/bin/sh
# Copyright 2026 Yusef Karim
# Solderpad Hardware License, Version 2.1, see LICENSE.md for details.
# SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
#
# Elaborate the CORE-V MCU SoC for the GF180MCU target and report what is
# missing. Runs inside the toolchain container; invoke it as `make elaborate`.
#
# The file list is not maintained by hand. fusesoc resolves upstream's `default`
# target from the submodule, unmodified, and this script filters that list and
# adds the GF180MCU sources on top. Upstream RTL needs no patches: the only
# thing removed is the eFPGA, and only because its sources are unreadable.

set -eu

ROOT=${ROOT:-/foss/designs}
CORE=openhwgroup.org:systems:core-v-mcu
TOP=core_v_mcu
BUILD=$ROOT/flow/build
WORK=$BUILD/build/openhwgroup.org_systems_core-v-mcu_0/default-verilator

rm -rf "$BUILD"
mkdir -p "$BUILD"
cd "$BUILD"

echo "==> resolving the file list with fusesoc"
fusesoc --cores-root "$ROOT/core-v-mcu" run \
    --target default --tool verilator --setup "$CORE" >fusesoc.log 2>&1

# Everything the eFPGA brings with it comes out. `quicklogic.com:ip:efpga` ships
# inside `protect envelopes that no open front end reads, and there is no GF180
# implementation of it to read anyway; rtl/gf180mcu/gf180_efpga_stub.sv keeps
# the SoC's eFPGA interfaces terminated in its place. Nothing else is excluded:
# upstream's filesets already pick the flip-flop register file over the latch
# one and leave the assertion and logging files out.
grep -E '^(\+incdir\+|src/)' "$WORK"/*.vc \
    | grep -v 'quicklogic.com_ip_efpga_0' \
    | grep -v 'core-v-mcu/efpga_subsystem/' \
    >"$WORK/gf180.f"

# The GF180MCU target's own sources, plus black boxes for the technology cells
# that have not been written yet.
find "$ROOT/rtl/gf180mcu" -name '*.sv' | sort >>"$WORK/gf180.f"
echo "$ROOT/flow/synth/stubs.sv" >>"$WORK/gf180.f"

echo "==> elaborating $TOP with yosys-slang"
cd "$WORK"
yosys -l "$BUILD/elaborate.log" -p "
    plugin -i slang
    read_slang -F gf180.f -D SYNTHESIS --top $TOP --keep-hierarchy --error-limit=0
    hierarchy -check -top $TOP
    stat -top $TOP
" >/dev/null

# The per-instance hierarchy runs to thousands of lines with --keep-hierarchy;
# print only the roll-up, which ends with one line per unresolved module.
echo
echo "==> $TOP, counting submodules"
awk '/\+----------Count including submodules/ {buf = ""}
     /^End of script/ {exit}
     {buf = buf $0 ORS}
     END {printf "%s", buf}' "$BUILD/elaborate.log"
echo "full log: flow/build/elaborate.log"
