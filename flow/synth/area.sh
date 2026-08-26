#!/bin/sh
# Copyright 2026 Yusef Karim
# Solderpad Hardware License, Version 2.1, see LICENSE.md for details.
# SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
#
# Synthesise the SoC to GF180MCU standard cells and report its logic area.
# Invoke it as `make area`.
#
# This is a measurement, not an implementation: no floorplan and no pads, so
# what comes out is the SoC's logic area and nothing else.
#
# Two passes, answering different questions. `hier` keeps module boundaries so
# `stat` can attribute area per module; it over-reports the total, because
# nothing optimises across a boundary. `flat` is what the real flow does and is
# the honest total.
#
# Environment overrides: MODE (hier|flat|both|report), LIB_CORNER,
# CLOCK_PERIOD_NS.

set -eu

. "${ROOT:-/foss/designs}/flow/synth/filelist.sh"

MODE=${MODE:-both}
CLOCK_PERIOD_NS=${CLOCK_PERIOD_NS:-200}

gf180_liberty

# Only $LIB reaches dfflibmap, abc and stat. The SRAM macros stay out of
# `stat -liberty` because their Liberty area is the wrong macro's;
# area_report.py adds them back from LEF geometry.
READ_LIBS=$(for l in $LIBS; do echo "        read_liberty -lib $l"; done)

# dfflibmap maps flip-flops only, and upstream's apb_soc_ctrl infers latches.
# Without the map they survive as behavioural `always` blocks that OpenSTA
# cannot read.
LATCH_MAP=$PDK_ROOT/$PDK/libs.tech/librelane/$SCL/latch_map.v
[ -r "$LATCH_MAP" ] || {
    echo "error: no latch map for $SCL at $LATCH_MAP" >&2
    exit 1
}

# `report` re-runs only the summary against a previous run's logs. Synthesis is
# minutes; the summary is instant and gets iterated on.
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

    # The hierarchical netlist is also dumped as JSON for anything that wants
    # to query the design structurally.
    json=""
    [ "$pass" = hier ] && json="write_json $OUT/$TOP.$pass.json"

    echo "==> synthesising $TOP ($pass, corner $LIB_CORNER, target ${CLOCK_PERIOD_NS} ns)"
    yosys -l "$OUT/synth-$pass.log" -p "
$READ_LIBS
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
    --sram "$SRAM" \
    --sram-lef-dir "$PDK_ROOT/$PDK/libs.ref/$SRAM/lef" \
    --clock-period "$CLOCK_PERIOD_NS" \
    --logs "$OUT" \
    | tee "$OUT/area.md"
echo
echo "report: flow/build/area/area.md"
