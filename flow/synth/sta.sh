#!/bin/sh
# Copyright 2026 Yusef Karim
# Solderpad Hardware License, Version 2.1, see LICENSE.md for details.
# SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
#
# A first look at the critical path of the synthesised netlist. Runs inside the
# toolchain container; invoke it as `make sta`, after `make area`.
#
# Read the output as logic depth, not as a frequency. The netlist has been
# through neither placement nor buffering, so every net has zero parasitics and
# the reset net drives 4,841 loads from one minimum-drive inverter. Those errors
# do not cancel: raw slack here is hundreds of nanoseconds and means nothing.
# `path_summary.py` recovers the part that is real, which is the number of
# stages and what a properly driven stage costs. See its header.
#
# Ticket 14 settled the core supply at 3.3 V, so ss_125C_3v00 is the signoff
# corner and is reported first. ss_125C_4v50 is kept as the informational arm:
# it is the margin the design gave up to reach the 3.3 V SRAM macros, and
# keeping it visible is what makes that cost re-checkable if timing gets tight.

set -eu

ROOT=${ROOT:-/foss/designs}
TOP=${TOP:-core_v_mcu}
PDK=${PDK:-gf180mcuD}
SCL=${SCL:-gf180mcu_fd_sc_mcu7t5v0}
SRAM=${SRAM:-gf180mcu_ocd_ip_sram}
SRAM_MACRO=${SRAM_MACRO:-gf180mcu_ocd_ip_sram__sram1024x8m8wm1}
CLOCK_PERIOD_NS=${CLOCK_PERIOD_NS:-50}
SIGNOFF_CORNER=${LIB_CORNER:-ss_125C_3v00}
NETLIST=${NETLIST:-$ROOT/flow/build/area/$TOP.flat.v}

# Nets above this fanout are the unbuffered reset and clock trees. Timing
# through them is an artefact of the flow not having built those trees yet, so
# they are excluded rather than allowed to hide every real path behind them.
FANOUT_LIMIT=${FANOUT_LIMIT:-500}

PDK_ROOT=${PDK_ROOT:-$ROOT/pdk}
LIBDIR=$PDK_ROOT/$PDK/libs.ref/$SCL/lib
SRAM_LIBDIR=$PDK_ROOT/$PDK/libs.ref/$SRAM/lib
OUT=$ROOT/flow/build/area

# Ticket 19 put sixteen SRAM macros in the netlist, so the L2 paths now need the
# macro's own liberty rather than blackbox.lib's zero-delay model. That liberty
# is the foundry sram512x8's timing under an OCD cell name (ticket 20), so read
# what it reports as a pessimistic proxy, not as characterisation.
#
# gf180mcu_ocd_ip_sram has no 4v50 corner at all, which is exactly what ticket 14
# settled the supply on: 5.0 V would have removed this macro permanently. The
# informational 5.0 V arm therefore runs the standard cells at 4v50 against SRAM
# arcs from 3v00 and says so, because what that arm is for is the logic
# comparison. There is no 5.0 V chip to measure here, only a 5.0 V logic path.
sram_liberty_for() {
    lib=$SRAM_LIBDIR/${SRAM_MACRO}__$1.lib
    if [ -r "$lib" ]; then
        echo "$lib"
    else
        echo "$SRAM_LIBDIR/${SRAM_MACRO}__ss_125C_3v00.lib"
    fi
}

[ "$PDK" = gf180mcuD ] || { echo "error: PDK is $PDK, this design is gf180mcuD only" >&2; exit 1; }
[ -r "$NETLIST" ] || { echo "error: no netlist at $NETLIST, run \`make area\` first" >&2; exit 1; }

# OpenSTA reads a structural netlist and treats every instance as a library
# cell, which cannot carry parameters. The black boxes can, so strip them.
READABLE=$OUT/$(basename "$NETLIST" .v).sta.v
"$ROOT/flow/synth/strip_params.py" <"$NETLIST" >"$READABLE"

for corner in ss_125C_3v00 ss_125C_4v50; do
    lib=$LIBDIR/${SCL}__${corner}.lib
    [ -r "$lib" ] || { echo "error: no liberty at $lib" >&2; exit 1; }
    sram_lib=$(sram_liberty_for "$corner")
    [ -r "$sram_lib" ] || { echo "error: no liberty at $sram_lib" >&2; exit 1; }
    case $sram_lib in
        *__${corner}.lib) ;;
        *) echo "note: $SRAM has no $corner corner, SRAM arcs are $(basename "$sram_lib" .lib | sed 's/.*__//')" ;;
    esac

    # The SoC clock is generated inside apb_pll, which is still a black box, so
    # there is no clock to find by tracing. Constrain the reference the ASIC
    # build drives and let blackbox.lib's ideal arcs carry it through.
    sta -exit >"$OUT/sta-$corner.log" 2>&1 <<EOF
read_liberty $lib
read_liberty $sram_lib
read_liberty $ROOT/flow/synth/blackbox.lib
read_verilog $READABLE
link_design $TOP
create_clock -name ref_clk -period $CLOCK_PERIOD_NS [get_ports ref_clk_i]
set excluded 0
foreach net [get_nets *] {
    if {[llength [get_pins -of_object \$net]] > $FANOUT_LIMIT} {
        set_false_path -through \$net
        incr excluded
    }
}
puts "excluded \$excluded nets above $FANOUT_LIMIT fanout"
report_checks -path_delay max -path_group ref_clk -group_path_count 1 -digits 3
EOF
    grep -h '^excluded' "$OUT/sta-$corner.log" || true
    "$ROOT/flow/synth/path_summary.py" \
        --corner "$corner" \
        --clock-period "$CLOCK_PERIOD_NS" \
        "$OUT/sta-$corner.log"
    echo "    full log: flow/build/area/sta-$corner.log"
done

echo
echo "Highest-fanout nets, which is what the flow has to buffer:"
sta -exit 2>/dev/null <<EOF | grep '^  ' || true
read_liberty $LIBDIR/${SCL}__${SIGNOFF_CORNER}.lib
read_liberty $(sram_liberty_for "$SIGNOFF_CORNER")
read_liberty $ROOT/flow/synth/blackbox.lib
read_verilog $READABLE
link_design $TOP
set nets {}
foreach net [get_nets *] {
    lappend nets [list [llength [get_pins -of_object \$net]] [get_full_name \$net]]
}
foreach e [lrange [lsort -integer -decreasing -index 0 \$nets] 0 5] {
    puts "  [format %6d [lindex \$e 0]]  [lindex \$e 1]"
}
EOF
