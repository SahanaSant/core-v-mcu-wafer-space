# Copyright 2026 Yusef Karim
# Solderpad Hardware License, Version 2.1, see LICENSE.md for details.
# SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
#
# Timing constraints for chip_top, used for both PnR and sign-off. Seeded from
# librelane/chip_top.sdc in the gf180mcu project template (Apache-2.0, (c) 2025
# Project Template Contributors), which is itself LibreLane's base SDC. The
# changes from it are the port names, the jtag_tck clock and its clock group,
# the jtag_tdo output constraint, and the hold false paths on asynchronous
# inputs.

current_design $::env(DESIGN_NAME)
set_units -time ns

# --- The main clock ---------------------------------------------------------
#
# CLOCK_PORT is the pad, CLOCK_NET the pad cell's core-side output, so the
# clock is defined after the input buffer rather than at the bond pad. The
# period comes from flow/config.yaml: 200 ns / 5 MHz, chosen after 166.67 ns
# still missed setup by 7.72 ns on one structural decoder-to-interconnect path.
# The clock is external, so this is a bring-up target rather than anything
# burned into silicon.

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

# --- The JTAG clock ---------------------------------------------------------
#
# The JTAG TAP is a genuinely asynchronous second domain, and declaring it is
# worth real area. Charging every buffer design repair inserted back to the pad
# net it descends from, before this was declared:
#
#   clk_pad     5780 loads      0 buffers    has a create_clock
#   inputs[0]    258 loads   3377 buffers    does not
#
# The clock pad drives twenty-two times the loads and takes no repair buffers
# at all, because repair_design leaves clock nets to CTS. The JTAG pad was
# repaired as data instead: 7% of every buffer in the design, spent reaching a
# twenty-second of the loads.
#
# set_clock_groups is required alongside it. Everything crossing between the
# two domains goes through the debug module's own CDC synchronisers, so without
# it the tool would time paths that have no meaning and repair_timing would
# chase them.
set jtag_tck_pin [get_pins -quiet {inputs\[0\].pad/Y}]
if { [llength $jtag_tck_pin] } {
    create_clock $jtag_tck_pin -name jtag_tck -period $::env(CLOCK_PERIOD)
    set_clock_groups -asynchronous -group [get_clocks $clock_port] \
        -group [get_clocks jtag_tck]
    puts "\[INFO] Declared jtag_tck on inputs\[0\].pad/Y, asynchronous to $clock_port"
} else {
    puts "\[WARNING] inputs\[0\].pad/Y not found; jtag_tck left unconstrained"
}

# --- The one clock still undeclared -----------------------------------------
#
# ref_clk_div40 would be `create_generated_clock -divide_by 40` off the output
# pin of net `*apb_fll_if_i.ref_clk_o`, which is gf180_clk_gen.sv's `clkdv`
# output. (Note the name: clkdv's internal `clkout` register folds away,
# because `assign clk_o = (CLK_DIV_VALUE <= 1) ? clk_i : clkout` is a straight
# connection at the constant divisor of 40.)
#
# It resolves correctly and OpenSTA reports it; CheckSDCFiles and STAPrePNR
# accept it. It is left out because each extra clock is another tree for CTS to
# build, and TritonCTS crashes on this design roughly 99 attempts in 100 unless
# the patched OpenROAD is used (see docs/explanation/known-issues.md). Try
# declaring it again on a newer OpenROAD.
#
# What the domain loses is a *balanced* tree; it is still buffered by
# repair_design as an ordinary high-fanout net. At 125 kHz that is close to
# immaterial, since skew that would matter against 200 ns is nothing against
# 8000 ns, and everything crossing back goes through upstream's own
# synchronisers.

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

# The min (hold) half of those input delays describes a launch that does not
# exist. bidir_PAD and rst_n_PAD are asynchronous to clk_PAD: nothing outside
# the chip launches them off this clock, so there is no real hold relationship
# to check. Both are synchronised in RTL before anything acts on them.
# apb_gpio shifts gpio_in through r_gpio_sync0, r_gpio_sync1 and r_gpio_in
# before the APB side sees it; rst_n reaches the SoC through rstgen_bypass,
# whose synch_regs_q chain asserts asynchronously and releases synchronously.
# Those synchronisers are what makes the pad-to-first-flop arrival time not
# matter, which is precisely what a hold check on it would be asserting.
#
# Left declared, the check is not merely noise. With set_input_delay -min 0
# against a clock network of zero propagated delay the requirement cannot be
# satisfied at any corner, so the resizer chases it: the worst offender,
# bidir_PAD[27], carries eight inserted hold buffers in series and still
# reports -0.416 ns. The repair is unbounded because the target is fictitious,
# and every buffer it adds is area and leakage spent on nothing.
#
# Scoped to -hold so the max/setup constraints stay exactly as they were; they
# already pass with room and they are what keeps these ports from being
# unconstrained. The other asynchronous inputs (input_PAD, carrying stm_i, the
# JTAG inputs and the spares) very likely deserve the same treatment, but they
# are not violating and their consumers have not been traced, so they are left
# alone rather than false-pathed on an assumption.
set_false_path -hold -from $clk_core_inout_ports
set_false_path -hold -from [get_ports rst_n_PAD]

# jtag_tdo is the one output outside the io array. It is constrained against
# the main clock rather than jtag_tck, which is not the clock that launches it;
# the constraint is here so the port is not left unconstrained entirely.
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
