#!/bin/sh
# Copyright 2026 Yusef Karim
# Solderpad Hardware License, Version 2.1, see LICENSE.md for details.
# SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
#
# Resolve the GF180MCU file list for the CORE-V MCU SoC. Sourced, not executed:
# `elaborate.sh` and `area.sh` both need the same list and it is generated
# rather than maintained by hand, so it lives in one place.
#
# On return, $WORK/gf180.f is a yosys `-F` command file and $WORK is the cwd.

ROOT=${ROOT:-/foss/designs}
CORE=openhwgroup.org:systems:core-v-mcu
TOP=core_v_mcu
BUILD=$ROOT/flow/build
WORK=$BUILD/build/openhwgroup.org_systems_core-v-mcu_0/default-verilator

gf180_filelist() {
    rm -rf "$BUILD"
    mkdir -p "$BUILD"
    cd "$BUILD"

    echo "==> resolving the file list with fusesoc"
    fusesoc --cores-root "$ROOT/core-v-mcu" run \
        --target default --tool verilator --setup "$CORE" >fusesoc.log 2>&1

    # Everything the eFPGA brings with it comes out. `quicklogic.com:ip:efpga`
    # ships inside `protect envelopes that no open front end reads, and there is
    # no GF180 implementation of it to read anyway;
    # rtl/gf180mcu/gf180_efpga_stub.sv keeps the SoC's eFPGA interfaces
    # terminated in its place. Nothing else is excluded: upstream's filesets
    # already pick the flip-flop register file over the latch one and leave the
    # assertion and logging files out.
    grep -E '^(\+incdir\+|src/)' "$WORK"/*.vc \
        | grep -v 'quicklogic.com_ip_efpga_0' \
        | grep -v 'core-v-mcu/efpga_subsystem/' \
        >"$WORK/gf180.f"

    # The GF180MCU target's own sources, plus black boxes for the technology
    # cells that have not been written yet.
    find "$ROOT/rtl/gf180mcu" -name '*.sv' | sort >>"$WORK/gf180.f"
    echo "$ROOT/flow/synth/stubs.sv" >>"$WORK/gf180.f"

    cd "$WORK"
}
