# Copyright 2026 Yusef Karim
# Solderpad Hardware License, Version 2.1, see LICENSE.md for details.
# SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
#
# Timing constraints for chip_top, used for both PnR and sign-off. Seeded from
# librelane/chip_top.sdc in the gf180mcu project template (Apache-2.0, (c) 2025
# Project Template Contributors), which is itself LibreLane's base SDC. The
# changes from it are the port names, the jtag_tdo output constraint, and the
# long note below on the two clocks that are missing and why.

current_design $::env(DESIGN_NAME)
set_units -time ns

# --- The main clock ---------------------------------------------------------
#
# CLOCK_PORT is the pad, CLOCK_NET the pad cell's core-side output, so the clock
# is defined after the input buffer rather than at the bond pad. 100 ns / 10 MHz
# is ticket 05's settled target; since the clock is external, that is a
# synthesis and bring-up target rather than anything burned into silicon.

set clock_port __VIRTUAL_CLK__
if { [info exists ::env(CLOCK_PORT)] } {
    set port_count [llength $::env(CLOCK_PORT)]

    if { $port_count == "0" } {
        puts "\[WARNING] No CLOCK_PORT found. A dummy clock will be used."
    } elseif { $port_count != "1" } {
        puts "\[WARNING] Multi-clock files are not currently supported by the base SDC file. Only the first clock will be constrained."
    }

    if { $port_count > "0" } {
        set ::clock_port [lindex $::env(CLOCK_PORT) 0]
    }
}

if { $::env(CLOCK_PORT) == $::env(CLOCK_NET) } {
    set port_args [get_ports $clock_port]
} else {
    set port_args [get_pins [lindex $::env(CLOCK_NET) 0]]
}

puts "\[INFO] Using clock $clock_port…"
create_clock {*}$port_args -name $clock_port -period $::env(CLOCK_PERIOD)

# --- One clock, and not because one is enough -------------------------------
#
# This design has three clock domains and only one of them is constrained here,
# because `OpenROAD.CTS` crashes on it. The crash is a null dereference in
# TritonCTS, from the stack trace:
#
#   odb::dbNet::get1stSignalInput(bool)
#   cts::TritonCTS::separateMacroRegSinks(...)
#   cts::TritonCTS::initClockTreeForMacrosAndRegs(...)
#   cts::TritonCTS::initClock(...)
#   cts::TritonCTS::initOneClockTree(...)   x11, recursing
#
# It is **intermittent, at roughly one success in twenty-five**, and that is the
# part that matters, because it makes every single-shot experiment worthless.
# The proof is direct: one attempt passed, and re-running the very same step
# later against the byte-identical resolved SDC that pass had emitted, from the
# same placement database, failed. `separateMacroRegSinks` iterates an
# `unordered_set<dbMaster*>`, keyed on pointers and therefore ordered
# differently in every process, which is a plausible mechanism for the variance.
#
# Two consequences. The flow needs **retrying at this step**, the way `make pdk`
# already retries magic (ticket 15):
#
#   until make harden ARGS="--last-run --from OpenROAD.CTS --to OpenROAD.CTS"; \
#       do :; done
#
# And every "fix" anyone reports for it, including the ones below, has to be
# assumed to be a lucky run until it survives twenty-plus attempts. Ticket 25
# tried all of these and none of them changed the rate: adding or removing the
# JTAG clock, adding or removing the divided clock, `set_clock_groups`, the
# `jtag_tdo` output delay, and `CTS_SINK_CLUSTERING_ENABLE`,
# `CTS_OBSTRUCTION_AWARE`, `CTS_DISABLE_POST_PROCESSING` and
# `CTS_BALANCE_LEVELS`, singly and in combination. Memory is not the cause
# either: 5.3 GB free at the low-water mark and nothing in the kernel log.
#
# The two clocks left out, and what each would be:
#
#   jtag_tck        create_clock on {inputs\[0\].pad/Y}, the first west input
#                   pad, at $::env(CLOCK_PERIOD). It clocks the debug module's
#                   TAP, which ticket 04 made the sole recovery path on a boot
#                   CRC failure, so this is the one whose absence matters.
#   ref_clk_div40   create_generated_clock -divide_by 40 off the output pin of
#                   net `*apb_fll_if_i.ref_clk_o`, which is `gf180_clk_gen.sv`'s
#                   `clkdv` output. Note the name: `clkdv`'s internal `clkout`
#                   register folds away, because `assign clk_o = (CLK_DIV_VALUE
#                   <= 1) ? clk_i : clkout` is a straight connection at the
#                   constant divisor of 40.
#
# Both resolve correctly and OpenSTA reports them (100 ns and 4000 ns);
# `CheckSDCFiles` and `STAPrePNR` accept either. They are out for now because
# each extra clock is another tree for CTS to build and so another chance to hit
# the crash, not because either is wrong. Declaring them is the first thing to
# try again on a newer OpenROAD.
#
# What the two unconstrained domains lose is a *balanced* tree; they are still
# buffered by `repair_design` as ordinary high-fanout nets. For the 250 kHz
# divided clock that is close to immaterial, since skew that would be fatal
# against a 100 ns period is nothing against 4000 ns and everything crossing
# back goes through upstream's own synchronisers. For the TAP it is a real gap,
# and it is why a gate-level JTAG timing result from this netlist should not be
# trusted until the clock is constrained.

# --- Design rule and IO constraints -----------------------------------------

set input_delay_value [expr $::env(CLOCK_PERIOD) * $::env(IO_DELAY_CONSTRAINT) / 100]
set output_delay_value [expr $::env(CLOCK_PERIOD) * $::env(IO_DELAY_CONSTRAINT) / 100]
puts "\[INFO] Setting output delay to: $output_delay_value"
puts "\[INFO] Setting input delay to: $input_delay_value"

set_max_fanout $::env(MAX_FANOUT_CONSTRAINT) [current_design]
if { [info exists ::env(MAX_TRANSITION_CONSTRAINT)] } {
    set_max_transition $::env(MAX_TRANSITION_CONSTRAINT) [current_design]
}
if { [info exists ::env(MAX_CAPACITANCE_CONSTRAINT)] } {
    set_max_capacitance $::env(MAX_CAPACITANCE_CONSTRAINT) [current_design]
}

set clocks [get_clocks $clock_port]

# The io array: forty bidirectional pads, every function that ever drives out.
set clk_core_inout_ports [get_ports {
    bidir_PAD[*]
}]

set_input_delay -min 0 -clock $clocks $clk_core_inout_ports
set_input_delay -max $input_delay_value -clock $clocks $clk_core_inout_ports
set_output_delay $output_delay_value -clock $clocks $clk_core_inout_ports

# Input-only pads: reset, the four JTAG inputs, stm_i and six spares.
set clk_core_input_ports [get_ports {
    rst_n_PAD
    input_PAD[*]
}]

set_input_delay -min 0 -clock $clocks $clk_core_input_ports
set_input_delay -max $input_delay_value -clock $clocks $clk_core_input_ports

# jtag_tdo is the one output outside the io array. With the TAP's own clock
# undeclared (see above) it is constrained against the main clock, which is not
# the clock that launches it; the constraint is here so the port is not left
# unconstrained entirely, not because it is the right one.
set jtag_tdo_port [get_ports -quiet jtag_tdo_PAD]
if { [llength $jtag_tdo_port] } {
    set_output_delay $output_delay_value -clock $clocks $jtag_tdo_port
}

# Output load
set cap_load [expr $::env(OUTPUT_CAP_LOAD) / 1000.0]
puts "\[INFO] Setting load to: $cap_load"
set_load $cap_load [all_outputs]

puts "\[INFO] Setting clock uncertainty to: $::env(CLOCK_UNCERTAINTY_CONSTRAINT)"
set_clock_uncertainty $::env(CLOCK_UNCERTAINTY_CONSTRAINT) [all_clocks]

puts "\[INFO] Setting clock transition to: $::env(CLOCK_TRANSITION_CONSTRAINT)"
set_clock_transition $::env(CLOCK_TRANSITION_CONSTRAINT) [all_clocks]

puts "\[INFO] Setting timing derate to: $::env(TIME_DERATING_CONSTRAINT)%"
set_timing_derate -early [expr 1-[expr $::env(TIME_DERATING_CONSTRAINT) / 100]]
set_timing_derate -late [expr 1+[expr $::env(TIME_DERATING_CONSTRAINT) / 100]]

if { [info exists ::env(OPENLANE_SDC_IDEAL_CLOCKS)] && $::env(OPENLANE_SDC_IDEAL_CLOCKS) } {
    unset_propagated_clock [all_clocks]
} else {
    set_propagated_clock [all_clocks]
}
