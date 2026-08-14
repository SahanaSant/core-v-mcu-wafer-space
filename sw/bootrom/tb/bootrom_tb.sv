// Copyright 2026 Yusef Karim
// Solderpad Hardware License, Version 2.1, see LICENSE.md for details.
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
//
// Standalone check that gf180_bootrom.sv's generated case statement is a
// lossless, correctly-timed encoding of the compiled sw/bootrom image: every
// word gen_bootrom.py read from bootrom.bin reads back identically through
// a2_bootrom's registered CEN/A/Q interface, and an address past the image
// reads zero (the case statement's default). Run under Icarus (ticket 16
// pinned it: the PDK's icgtp model needs a UDP-capable simulator, so this
// design's gate-level checks all have to live on the same tool), invoked as
// `make bootrom`.
//
// This proves the ROM ==> compiled-binary equivalence, not that the CPU
// actually fetches, runs main(), and jumps: that needs the CV32E40P core, the
// uDMA QSPI block, a flash model and the rest of the SoC wired up, which is
// the gate-level simulation harness (map fog entry, not built by this
// ticket). What this testbench proves is a real precondition for that harness
// ever working, not a placeholder for it.
//
// Golden data comes from flow/build/bootrom/gf180_bootrom_golden.{mem,vh},
// gen_bootrom.py's byproduct of the same run that wrote gf180_bootrom.sv --
// not hand-maintained, and not synthesised.

`timescale 1ns / 1ps

`include "gf180_bootrom_golden.vh"

module bootrom_tb;

  localparam ADDR_WIDTH = 11;
  localparam DATA_WIDTH = 32;
  localparam NUM_WORDS = `BOOTROM_GOLDEN_WORDS;

  logic                  clk;
  logic                  cen;
  logic [ADDR_WIDTH-1:0] addr;
  logic [DATA_WIDTH-1:0] q;

  logic [DATA_WIDTH-1:0] golden[0:NUM_WORDS-1];

  integer errors;
  integer i;

  a2_bootrom #(
      .ADDR_WIDTH(ADDR_WIDTH),
      .DATA_WIDTH(DATA_WIDTH)
  ) dut (
      .CLK(clk),
      .CEN(cen),
      .A  (addr),
      .Q  (q)
  );

  initial clk = 0;
  always #5 clk = ~clk;

  initial begin
    $readmemh("flow/build/bootrom/gf180_bootrom_golden.mem", golden);
    errors = 0;
    cen = 1'b1;
    addr = '0;

    // a2_bootrom's registered read: CEN low on the clock edge that samples A
    // latches the addressed word into both read_data and Q (one-cycle
    // latency), matching upstream's a2_bootrom.sv exactly.
    for (i = 0; i < NUM_WORDS; i = i + 1) begin
      @(negedge clk);
      addr = i[ADDR_WIDTH-1:0];
      cen  = 1'b0;
      @(negedge clk);
      cen = 1'b1;
      if (q !== golden[i]) begin
        $display("FAIL word %0d: got %08h, expected %08h", i, q, golden[i]);
        errors = errors + 1;
      end
    end

    // One address well past the image: the case statement's default, not
    // anything gen_bootrom.py emitted, so it should read back zero.
    @(negedge clk);
    addr = 11'd1500;
    cen  = 1'b0;
    @(negedge clk);
    cen = 1'b1;
    if (q !== 32'h0) begin
      $display("FAIL word 1500 (past image, expect default 0): got %08h", q);
      errors = errors + 1;
    end

    if (errors == 0) begin
      $display("PASS: all %0d ROM words plus the out-of-range default match", NUM_WORDS);
    end else begin
      $display("FAIL: %0d mismatch(es)", errors);
      $fatal(1);
    end

    $finish;
  end

endmodule
