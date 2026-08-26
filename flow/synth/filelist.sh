#!/bin/sh
# Copyright 2026 Yusef Karim
# Solderpad Hardware License, Version 2.1, see LICENSE.md for details.
# SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
#
# Resolve the file list and the Liberty files that elaborate.sh and area.sh
# both need. Sourced, not executed.
#
# After gf180_filelist, $WORK/gf180.f is a yosys `-F` command file and $WORK is
# the cwd. gf180_liberty sets $LIB (standard cells) and $LIBS (everything).

ROOT=${ROOT:-/foss/designs}
CORE=openhwgroup.org:systems:core-v-mcu
# core_v_mcu is the SoC alone, which every area and timing measurement is
# quoted against. chip_top adds the pad ring and marker cells and is what
# `make harden` builds.
TOP=${TOP:-core_v_mcu}
BUILD=$ROOT/flow/build
WORK=$BUILD/build/openhwgroup.org_systems_core-v-mcu_0/default-verilator

# Both callers read these with `read_liberty -lib` before the RTL, because
# rtl/gf180mcu/ instantiates PDK cells by name and yosys-slang imports an
# instance as a black box only if an earlier command already loaded the module.
# Cell area then comes from Liberty instead of being silently zero.
#
# The corner is the 3.3 V signoff corner: cell area does not depend on it but
# delay-driven mapping does, and a slower corner makes ABC buy drive strength.
# The library is still gf180mcu_fd_sc_mcu7t5v0 -- `5v0` is the oxide, and all
# 229 cells exist at all fifteen corners with identical geometry.
#
# The SRAM Liberty is loaded for module definitions only. Its numbers are the
# foundry sram512x8's under an OCD cell name, so area comes from LEF geometry
# instead (see docs/explanation/known-issues.md). The pad Liberty is named for
# the core corner rather than the ring's 5.0 V, which is pessimistic on the
# output driver and left that way.
gf180_liberty() {
    PDK=${PDK:-gf180mcuD}
    SCL=${SCL:-gf180mcu_fd_sc_mcu7t5v0}
    SRAM=${SRAM:-gf180mcu_ocd_ip_sram}
    SRAM_MACRO=${SRAM_MACRO:-gf180mcu_ocd_ip_sram__sram1024x8m8wm1}
    PAD=${PAD:-gf180mcu_ocd_io}
    LIB_CORNER=${LIB_CORNER:-ss_125C_3v00}
    PAD_LIB_CORNER=${PAD_LIB_CORNER:-ss_125C_2v97}
    PDK_ROOT=${PDK_ROOT:-$ROOT/pdk}
    LIBDIR=$PDK_ROOT/$PDK/libs.ref/$SCL/lib
    LIB=$LIBDIR/${SCL}__${LIB_CORNER}.lib
    SRAM_LIBDIR=$PDK_ROOT/$PDK/libs.ref/$SRAM/lib
    SRAM_LIB=$SRAM_LIBDIR/${SRAM_MACRO}__${LIB_CORNER}.lib
    PAD_LIB=$PDK_ROOT/$PDK/libs.ref/$PAD/lib/${PAD}__${PAD_LIB_CORNER}.lib

    # C and D differ in top-metal thickness and therefore in DRC rules.
    [ "$PDK" = gf180mcuD ] || {
        echo "error: PDK is $PDK, this design is gf180mcuD only" >&2
        exit 1
    }
    [ -r "$LIB" ] || { echo "error: no liberty at $LIB" >&2; exit 1; }
    [ -r "$SRAM_LIB" ] || { echo "error: no liberty at $SRAM_LIB" >&2; exit 1; }
    [ -r "$PAD_LIB" ] || { echo "error: no liberty at $PAD_LIB" >&2; exit 1; }

    LIBS="$LIB $SRAM_LIB $PAD_LIB"
}

gf180_filelist() {
    rm -rf "$BUILD"
    mkdir -p "$BUILD"
    cd "$BUILD"

    echo "==> resolving the file list with fusesoc"
    fusesoc --cores-root "$ROOT/core-v-mcu" run \
        --target default --tool verilator --setup "$CORE" >fusesoc.log 2>&1

    # The eFPGA and everything it brings comes out: quicklogic.com:ip:efpga
    # ships inside `protect envelopes no open front end reads, and there is no
    # GF180 implementation of it. rtl/gf180mcu/gf180_efpga_stub.sv terminates
    # the SoC's eFPGA interfaces in its place. Nothing else is excluded.
    grep -E '^(\+incdir\+|src/)' "$WORK"/*.vc \
        | grep -v 'quicklogic.com_ip_efpga_0' \
        | grep -v 'core-v-mcu/efpga_subsystem/' \
        >"$WORK/gf180.f"

    # The GF180MCU technology cells. The PDK cells they instantiate arrive from
    # Liberty, not from here.
    find "$ROOT/rtl/gf180mcu" -name '*.sv' | sort >>"$WORK/gf180.f"

    # The pad ring and the wafer.space marker cells, always in the list whether
    # or not $TOP is chip_top: slang parses every file it is given, so
    # chip_top's instantiations have to resolve either way. The marker cells are
    # port-less black boxes with no netlist cost.
    find "$ROOT/rtl/chip" -name '*.sv' | sort >>"$WORK/gf180.f"
    find "$ROOT/ip" -path '*/vh/*.v' | sort >>"$WORK/gf180.f"

    cd "$WORK"
}
