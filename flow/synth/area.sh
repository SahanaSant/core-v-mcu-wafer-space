#!/bin/sh
# Copyright 2026 Yusef Karim
# Solderpad Hardware License, Version 2.1, see LICENSE.md for details.
# SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
#
# Synthesise the CORE-V MCU SoC to GF180MCU standard cells and report its area.
# Runs inside the toolchain container; invoke it as `make area`.
#
# This is a measurement, not an implementation. Memories and the unwritten
# technology cells stay black boxes, there is no floorplan and there are no
# pads, so what comes out is the logic area of the SoC and nothing else. The
# point is to replace the 200-300 kGE guess in docs/porting-analysis.md with a
# number, and to re-measure in one command every time the RTL moves.
#
# Two passes, because they answer different questions:
#
#   hier  keeps every module boundary, so `stat` can attribute area per module.
#         That is the table ticket 12 needs to cut peripherals with data. It
#         over-reports the total, because nothing optimises across a boundary.
#   flat  flattens first, which is what the real flow does. That is the honest
#         total, and the one to compare against the core budget.
#
# Environment overrides: MODE (hier|flat|both), LIB_CORNER, CLOCK_PERIOD_NS.

set -eu

. "${ROOT:-/foss/designs}/flow/synth/filelist.sh"

MODE=${MODE:-both}
PDK=${PDK:-gf180mcuD}
SCL=${SCL:-gf180mcu_fd_sc_mcu7t5v0}
CLOCK_PERIOD_NS=${CLOCK_PERIOD_NS:-50}

# Cell area does not depend on the corner, but delay-driven technology mapping
# does: a slower corner makes ABC buy drive strength. Map at the setup corner
# the flow will sign off at, so the area number is the one implementation will
# actually see. Ticket 14 settled that at 3.3 V, so the corner is ss_125C_3v00
# rather than the PDK LibreLane default's 5.0 V. Note this is still
# gf180mcu_fd_sc_mcu7t5v0: the `5v0` is the oxide, and the library carries all
# 229 cells at every one of its fifteen corners with identical geometry.
LIB_CORNER=${LIB_CORNER:-ss_125C_3v00}

PDK_ROOT=${PDK_ROOT:-$ROOT/pdk}
LIBDIR=$PDK_ROOT/$PDK/libs.ref/$SCL/lib
LIB=$LIBDIR/${SCL}__${LIB_CORNER}.lib

# `pdk/` carries gf180mcuA through gf180mcuD as symlinks into one ciel version,
# so a wrong variant name resolves to a real populated directory instead of
# failing. C and D differ in top-metal thickness and therefore in DRC rules, so
# assert rather than trust.
[ "$PDK" = gf180mcuD ] || { echo "error: PDK is $PDK, this design is gf180mcuD only" >&2; exit 1; }
[ -r "$LIB" ] || { echo "error: no liberty at $LIB" >&2; exit 1; }

# `dfflibmap` maps flip-flops only. Upstream's apb_soc_ctrl infers four latches,
# and without this they survive as behavioural `always` blocks that OpenSTA
# cannot read. The PDK ships the map; LibreLane uses the same file.
LATCH_MAP=$PDK_ROOT/$PDK/libs.tech/librelane/$SCL/latch_map.v
[ -r "$LATCH_MAP" ] || { echo "error: no latch map at $LATCH_MAP" >&2; exit 1; }

# `report` re-runs only the summary, against logs a previous run left behind.
# Synthesis is minutes; the summary is instant, and it gets iterated on.
if [ "$MODE" != report ]; then
    gf180_filelist
fi

OUT=$BUILD/area
mkdir -p "$OUT"

# ABC wants picoseconds.
DELAY_PS=$(awk "BEGIN{printf \"%d\", $CLOCK_PERIOD_NS * 1000}")

synth_pass() {
    pass=$1
    flatten=$2

    # The hierarchical netlist is also dumped as JSON, for anything that wants
    # to query the design structurally. `area_report.py` does not need it: the
    # stat log already carries per-module areas keyed by instance path.
    json=""
    [ "$pass" = hier ] && json="write_json $OUT/$TOP.$pass.json"

    echo "==> synthesising $TOP ($pass, corner $LIB_CORNER, target ${CLOCK_PERIOD_NS} ns)"
    yosys -l "$OUT/synth-$pass.log" -p "
        plugin -i slang
        read_slang -F gf180.f -D SYNTHESIS --top $TOP --keep-hierarchy --error-limit=0
        hierarchy -check -top $TOP
        synth -top $TOP $flatten
        dfflibmap -liberty $LIB
        techmap -map $LATCH_MAP
        abc -liberty $LIB -D $DELAY_PS
        setundef -zero
        splitnets
        opt_clean -purge
        stat -top $TOP -liberty $LIB
        write_verilog -noattr $OUT/$TOP.$pass.v
        $json
    " >/dev/null
    echo "    netlist: flow/build/area/$TOP.$pass.v"
    echo "    log:     flow/build/area/synth-$pass.log"
}

case $MODE in
    hier) synth_pass hier "" ;;
    flat) synth_pass flat "-flatten" ;;
    both) synth_pass hier ""; synth_pass flat "-flatten" ;;
    report) ;;
    *) echo "error: MODE must be hier, flat, both or report" >&2; exit 1 ;;
esac

echo
echo "==> summarising"
"$ROOT/flow/synth/area_report.py" \
    --liberty "$LIB" \
    --scl "$SCL" \
    --clock-period "$CLOCK_PERIOD_NS" \
    --logs "$OUT" \
    | tee "$OUT/area.md"
echo
echo "report: flow/build/area/area.md"
