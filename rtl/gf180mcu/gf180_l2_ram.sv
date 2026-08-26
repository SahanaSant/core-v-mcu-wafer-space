// Copyright 2026 Yusef Karim
// Solderpad Hardware License, Version 2.1, see LICENSE.md for details.
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1

// GF180MCU L2 memory banks for the CORE-V MCU.
//
// Two module names, one implementation, six instances: four interleaved banks
// became two when NB_L2_CHANNELS dropped to 2, and the two private banks are
// unchanged in count. Upstream declares core_v_mcu_interleaved_ram and
// core_v_mcu_private_ram separately because on an FPGA they are two different
// LogiCORE block-RAM instances with different depths. Both are 4 KiB here, so
// on GF180MCU they are the same 1024 x 32 gang and the two names bind
// to one body, the way the six clock-cell names in gf180_clk_gate.sv bind to
// three cells. One file, for the same reason: the alternative is two files whose
// only difference is the module name.
//
// The macro is gf180mcu_ocd_ip_sram__sram1024x8m8wm1, 1024 words x 8 bits,
// 301.30 x 515.81 um from its LEF. Four of them side by side make a 32-bit word,
// so 1024 words needs exactly four with no depth decoding and no output mux: the
// address bus is the macro's A[9:0] unmodified. Sixteen macros across the six
// banks is 2,486,624 um2 of macro.
//
// Do not take the area of these macros from their Liberty. Every Liberty file in
// gf180mcu_ocd_ip_sram is a foundry Liberty with the header swapped and the
// address bus resized, so the area field carries the foundry sram512x8's
// 209,400 um2 against a real 155,414, and the timing is the foundry 512x8's
// throughout. LEF SIZE is the only measured number here.

// --- The bank ----------------------------------------------------------------
// 1024 x 32, four ganged macros, one per byte lane.
//
// Pin mapping, from the macro's simulation model rather than from its Liberty:
//
//   write_flag = cen_fell & !CEN & !GWEN & !(&WEN)
//   read_flag  = cen_fell & !CEN &  GWEN
//
// so CEN, GWEN and WEN are all active low and a byte lane is masked off by
// driving its whole WEN bus high, which fails the !(&WEN) term. That is what
// makes the mapping below correct without any gating on CEN: on a write with
// be_i[k] low, macro k sees GWEN low and WEN all ones, so it neither writes nor
// reads and holds Q. TCDM ignores read data on a write cycle, so holding is
// enough and the write path stays combinationally shallow.
//
//   clk_i        -> CLK          rising edge
//   csn_i        -> CEN          already active low, connect directly
//   wen_i        -> GWEN         already active low, connect directly
//   be_i[k]      -> WEN[7:0]     replicated and inverted, per macro
//   addr_i       -> A[9:0]       word address, no decoding
//   wdata_i[k]   -> D[7:0]       byte lane k
//   rdata_o[k]   <- Q[7:0]       byte lane k
//
// One-cycle read latency, which is what the TCDM handshake in
// l2_ram_multi_bank.sv already assumes: it asserts gnt combinationally and
// registers r_valid one cycle behind req.
//
// rst_ni is unused. The macro has no reset and its contents are undefined out of
// power-up, which is upstream's behaviour on FPGA too (the Xilinx wrapper drops
// the port as well). It stays in the port list so the instantiation sites do not
// have to change.

module gf180_l2_bank #(
    parameter int unsigned ADDR_WIDTH = 10
) (
    input  logic                  clk_i,
    input  logic                  rst_ni,
    input  logic                  csn_i,
    input  logic                  wen_i,
    input  logic [           3:0] be_i,
    input  logic [ADDR_WIDTH-1:0] addr_i,
    input  logic [          31:0] wdata_i,
    output logic [          31:0] rdata_o
);

  // 1024 words is the macro's whole depth, so an ADDR_WIDTH of anything but 10
  // would silently address a different memory than the one the interconnect
  // decodes. Fail at elaboration rather than in the netlist.
  if (ADDR_WIDTH != 10)
    $error("gf180_l2_bank: ADDR_WIDTH is %0d, the sram1024x8 macro has A[9:0]", ADDR_WIDTH);

  for (genvar k = 0; k < 4; k++) begin : gen_byte_lane
    gf180mcu_ocd_ip_sram__sram1024x8m8wm1 i_sram (
        .CLK (clk_i),
        .CEN (csn_i),
        .GWEN(wen_i),
        .WEN ({8{~be_i[k]}}),
        .A   (addr_i),
        .D   (wdata_i[8*k+:8]),
        .Q   (rdata_o[8*k+:8])
    );
  end

  logic unused_rst_ni;
  assign unused_rst_ni = rst_ni;

endmodule

// --- The two upstream names --------------------------------------------------

module core_v_mcu_interleaved_ram #(
    parameter int unsigned ADDR_WIDTH = 10
) (
    input  logic                  clk_i,
    input  logic                  rst_ni,
    input  logic                  csn_i,
    input  logic                  wen_i,
    input  logic [           3:0] be_i,
    input  logic [ADDR_WIDTH-1:0] addr_i,
    input  logic [          31:0] wdata_i,
    output logic [          31:0] rdata_o
);

  gf180_l2_bank #(
      .ADDR_WIDTH(ADDR_WIDTH)
  ) i_bank (
      .clk_i,
      .rst_ni,
      .csn_i,
      .wen_i,
      .be_i,
      .addr_i,
      .wdata_i,
      .rdata_o
  );

endmodule

module core_v_mcu_private_ram #(
    parameter int unsigned ADDR_WIDTH = 10
) (
    input  logic                  clk_i,
    input  logic                  rst_ni,
    input  logic                  csn_i,
    input  logic                  wen_i,
    input  logic [           3:0] be_i,
    input  logic [ADDR_WIDTH-1:0] addr_i,
    input  logic [          31:0] wdata_i,
    output logic [          31:0] rdata_o
);

  gf180_l2_bank #(
      .ADDR_WIDTH(ADDR_WIDTH)
  ) i_bank (
      .clk_i,
      .rst_ni,
      .csn_i,
      .wen_i,
      .be_i,
      .addr_i,
      .wdata_i,
      .rdata_o
  );

endmodule
