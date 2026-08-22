// Copyright 2026 Yusef Karim
// Solderpad Hardware License, Version 2.1, see LICENSE.md for details.
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
//
// Behavioural stand-ins for the eight gf180mcu_ocd_io cells rtl/chip/chip_top.sv
// instantiates, for RTL simulation only.
//
// The PDK ships real models in
// libs.ref/gf180mcu_ocd_io/verilog/gf180mcu_ocd_io.v and they are what
// gate-level simulation reads. They cannot be used for an RTL run, because
// gf180mcu_ocd_io__bi_24t builds its pull-up and pull-down out of `rnmos`, a
// Verilog-1995 gate primitive that Verilator does not implement, and there is
// no `ifdef` around it. The file's own ``ifdef functional`` switches
// only `timescale` and delay mode, so defining it changes nothing here.
//
// Ticket 31 needs RTL simulation because the boot ROM is compiled into gates
// and no software change can be tested against a netlist. This file, plus the
// clock-cell swap in sim/cocotb/tb_top_tb.py, is what removes the last
// dependency on the PDK cell libraries from an RTL run.
//
// The logic below is transcribed from the real models, not invented:
//
//   in_c, in_s   buf #1 (Y, PAD)
//   bi_24t       and #1 (Y, PAD, IE)
//                bufif1 #1 (PAD, A, OE)
//                rnmos #1 (PAD, gnd, ~OE && ~PU && PD)
//                rnmos #1 (PAD, pwr, ~OE && PU && ~PD)
//   vdd, vss, dvdd, dvss, asig_5p0
//                no behaviour, supply declarations only
//
// What is deliberately not carried over, and what that costs: the unit delays
// and the `specify` blocks are dropped, so this models function and not
// timing. An RTL run through these pads therefore says nothing about pad
// timing or level shifting, which is correct for what RTL simulation is for
// here, and is a real reason gate-level remains the sign-off simulation.
// in_c is a CMOS-threshold input and in_s a Schmitt-trigger one; that
// distinction is analog and both reduce to the same buffer in either model.

`timescale 1ns / 1ps

module gf180mcu_ocd_io__in_c (
    input  PU,
    input  PD,
    input  PAD,
    output Y,
    inout  DVDD,
    inout  DVSS,
    inout  VDD,
    inout  VSS
);
  assign Y = PAD;
endmodule

module gf180mcu_ocd_io__in_s (
    input  PU,
    input  PD,
    input  PAD,
    output Y,
    inout  DVDD,
    inout  DVSS,
    inout  VDD,
    inout  VSS
);
  assign Y = PAD;
endmodule

module gf180mcu_ocd_io__bi_24t (
    input  CS,
    input  SL,
    input  IE,
    input  OE,
    input  PU,
    input  PD,
    input  A,
    inout  PAD,
    output Y,
    inout  DVDD,
    inout  DVSS,
    inout  VDD,
    inout  VSS
);
  // bufif1 (PAD, A, OE): the pad drives only while OE is high, and is high
  // impedance otherwise so the outside world (or the pull below) wins.
  assign PAD = OE ? A : 1'bz;

  // The keeper the real cell builds from two rnmos devices. Weak strength so
  // an external driver overrides it, matching the resistive devices it stands
  // in for. Only active while the output driver is off, exactly as the real
  // cell's ~OE terms require.
  assign (weak0, weak1) PAD = (!OE && PU && !PD) ? 1'b1 :
                              (!OE && !PU && PD) ? 1'b0 : 1'bz;

  // and (Y, PAD, IE): the input path is gated by the input enable, so a
  // disabled input reads 0 rather than following the pad.
  assign Y = PAD & IE;
endmodule

module gf180mcu_ocd_io__asig_5p0 (
    inout ASIG5V,
    inout DVDD,
    inout DVSS,
    inout VDD,
    inout VSS
);
endmodule

module gf180mcu_ocd_io__vdd (
    inout DVDD,
    inout DVSS,
    inout VDD,
    inout VSS
);
endmodule

module gf180mcu_ocd_io__vss (
    inout DVDD,
    inout DVSS,
    inout VDD,
    inout VSS
);
endmodule

module gf180mcu_ocd_io__dvdd (
    inout DVDD,
    inout DVSS,
    inout VDD,
    inout VSS
);
endmodule

module gf180mcu_ocd_io__dvss (
    inout DVDD,
    inout DVSS,
    inout VDD,
    inout VSS
);
endmodule
