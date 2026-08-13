#!/bin/sh
# Copyright 2026 Yusef Karim
# Solderpad Hardware License, Version 2.1, see LICENSE.md for details.
# SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
#
# Resolve the GF180MCU file list and standard-cell liberty for the CORE-V MCU
# SoC. Sourced, not executed: `elaborate.sh` and `area.sh` both need the same
# two things and they are generated rather than maintained by hand, so they live
# in one place.
#
# On return from gf180_filelist, $WORK/gf180.f is a yosys `-F` command file and
# $WORK is the cwd. gf180_liberty sets $LIB.

ROOT=${ROOT:-/foss/designs}
CORE=openhwgroup.org:systems:core-v-mcu
TOP=core_v_mcu
BUILD=$ROOT/flow/build
WORK=$BUILD/build/openhwgroup.org_systems_core-v-mcu_0/default-verilator

# Resolve the standard-cell liberty and assert the variant. Both callers read it
# with `read_liberty -lib` before the RTL, because rtl/gf180mcu/gf180_clk_gate.sv
# instantiates PDK cells by name and yosys-slang can only import a module as a
# black box if some earlier yosys command already loaded it. Cell area then comes
# from the liberty rather than being silently zero.
#
# Cell area does not depend on the corner, but delay-driven technology mapping
# does: a slower corner makes ABC buy drive strength. Map at the setup corner the
# flow will sign off at, so the area number is the one implementation will
# actually see. Ticket 14 settled that at 3.3 V, so the corner is ss_125C_3v00
# rather than the PDK LibreLane default's 5.0 V. Note this is still
# gf180mcu_fd_sc_mcu7t5v0: the `5v0` is the oxide, and the library carries all
# 229 cells at every one of its fifteen corners with identical geometry.
gf180_liberty() {
    PDK=${PDK:-gf180mcuD}
    SCL=${SCL:-gf180mcu_fd_sc_mcu7t5v0}
    LIB_CORNER=${LIB_CORNER:-ss_125C_3v00}
    PDK_ROOT=${PDK_ROOT:-$ROOT/pdk}
    LIBDIR=$PDK_ROOT/$PDK/libs.ref/$SCL/lib
    LIB=$LIBDIR/${SCL}__${LIB_CORNER}.lib

    # Ticket 15 built the PDK for gf180mcuD alone, so a wrong variant name no
    # longer resolves to a real populated directory. Assert anyway: the
    # assertion is what keeps that true. C and D differ in top-metal thickness
    # and therefore in DRC rules.
    [ "$PDK" = gf180mcuD ] || {
        echo "error: PDK is $PDK, this design is gf180mcuD only" >&2
        exit 1
    }
    [ -r "$LIB" ] || { echo "error: no liberty at $LIB" >&2; exit 1; }
}

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
    # cells that have not been written yet. The PDK cells that gf180_clk_gate.sv
    # instantiates are not here: they arrive from the liberty, see gf180_liberty.
    find "$ROOT/rtl/gf180mcu" -name '*.sv' | sort >>"$WORK/gf180.f"
    echo "$ROOT/flow/synth/stubs.sv" >>"$WORK/gf180.f"

    cd "$WORK"
}
