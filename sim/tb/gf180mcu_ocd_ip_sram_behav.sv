// Copyright 2026 Yusef Karim
// Solderpad Hardware License, Version 2.1, see LICENSE.md for details.
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
//
// Behavioural stand-in for the 1024x8 SRAM macro the L2 banks are built from,
// for RTL simulation only.
//
// The PDK ships a real model in
// libs.ref/gf180mcu_ocd_ip_sram/verilog/gf180mcu_ocd_ip_sram__sram1024x8m8wm1.v.
// It cannot be used in a zero-delay RTL simulation, and using it silently
// destroys every access rather than reporting anything.
//
// The vendor model does its work in `always @(posedge clk_dly)`, where
// `clk_dly` is CLK delayed by 100 ps, and inside that block it samples CEN,
// GWEN, A and D as they are at that later moment. It also gates itself on
// `write_flag`/`read_flag`, which are combinational on CEN and GWEN. In real
// silicon, and in a gate-level run with SDF back-annotation, clock-to-Q delay
// means those inputs still hold the pre-edge values 100 ps in, so the model
// captures the access that was set up before the edge, which is what a
// synchronous SRAM does.
//
// In RTL there is no clock-to-Q delay. Every input has already moved to the
// next cycle's value by the time `clk_dly` rises, so a single isolated access
// (CEN low for one cycle, high the next) is seen with CEN already high:
// `write_flag` and `read_flag` are both zero, the write never happens and Q
// holds its previous value. The memory reads back as all zeros forever, which
// is exactly what ticket 31 spent a long time chasing. Back-to-back accesses
// fare no better, being committed against the following transaction's address.
//
// rtl/gf180mcu/gf180_bootrom.sv already models the ROM macro this way, with a
// plain `always_ff @(posedge CLK) if (!CEN)`, which is why instruction fetch
// worked throughout while every L2 access was being dropped.
//
// Timing behaviour matched to the vendor model: one-cycle read latency, Q
// holds its last value while CEN is high, per-bit active-low write enables
// under an active-low global write enable, and memory zeroed at time zero.
// What is deliberately dropped is the setup/hold/cycle-time checking, which is
// only meaningful against annotated delays. Ticket 20 recorded that this
// model's access time is 2x optimistic at 3.3 V in any case, so its checks were
// never load-bearing; `make sta` is what signs off memory timing.

`timescale 1ps / 1ps

module gf180mcu_ocd_ip_sram__sram1024x8m8wm1 (
`ifdef USE_POWER_PINS
    inout VDD,
    inout VSS,
`endif
    input        CLK,
    input        CEN,   // chip enable, active low
    input        GWEN,  // global write enable, active low
    input  [7:0] WEN,   // per-bit write enable, active low
    input  [9:0] A,
    input  [7:0] D,
    output [7:0] Q
);

  reg [7:0] mem[1023:0];
  reg [7:0] qo;

  assign Q = qo;

  always @(posedge CLK) begin
    if (!CEN) begin
      if (!GWEN) mem[A] <= (mem[A] & WEN) | (D & ~WEN);
      else qo <= mem[A];
    end
  end

  integer i;
  initial begin
    qo = 8'd0;
    for (i = 0; i < 1024; i = i + 1) mem[i] = 8'd0;
  end

endmodule
