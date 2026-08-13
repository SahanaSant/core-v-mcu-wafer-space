// Copyright 2026 Yusef Karim
// Solderpad Hardware License, Version 2.1, see LICENSE.md for details.
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1

// GF180MCU clock cells for the CORE-V MCU.
//
// Six module names, three technology cells, 70 instances. Upstream declares the
// same three behaviours under three naming families (pulp_*, cluster_*, and the
// one cv32e40p brings with it) and expects each target to bind them; this file
// is that binding for GF180MCU, a third sibling of the behavioural models in
// tech_cells_generic and the Xilinx models in emulation/xilinx/rtl/.
//
// Every cell here is instantiated by name rather than inferred. Yosys has no
// reliable path from a latch-and-AND to an integrated clock gate, and a clock
// path that survives as ordinary logic is free to be restructured by the mapper
// into gates with unbalanced arrival, which is precisely what these cells exist
// to prevent. An explicit instance also keeps the cell name in the netlist,
// where `make area` and any clock-tree review can find it.
//
// The names carry the library gf180mcu_fd_sc_mcu7t5v0, which is a library and
// not a variant: the same standard cells exist in every gf180mcu variant, so
// nothing here asserts C against D. It does bind this file to that one library.
// `flow/synth/filelist.sh` hands the definitions to yosys with
// `read_liberty -lib` before the RTL is read, so no path into pdk/ appears here.
//
// Drive strengths are all _1, the smallest offered. The clock cells sit at the
// root of a fanout cone that has no tree yet; CTS inserts the buffers and the
// resizer upsizes what it has to, and starting from the minimum is what lets it.

// --- Integrated clock gating -------------------------------------------------
// gf180mcu_fd_sc_mcu7t5v0__icgtp_1, 61.4656 um2, drive strengths 1, 2 and 4.
//
// Its liberty declares `clock_gating_integrated_cell : "latch_posedge_precontrol"`
// and its state table latches E|TE while CLK is low, with Q = CLK & IQ2. That is
// the same function as upstream's Xilinx model, so the three wrappers below are
// a rename and nothing more.
//
// TE is a real pin, marked `clock_gate_test_pin` in the liberty, so the test
// enable goes to the cell rather than being ORed into the enable in RTL. All
// three families pass one and all three reach the cell unchanged.
//
// The negedge sibling icgtn exists (68.0512 um2, `latch_negedge_precontrol`) and
// is not used: every gated domain in this SoC is posedge. The negedge logic that
// does exist (the JTAG TAP and the SPI master phase inversion) inverts the
// clock rather than gating it, and takes clkinv below.

module pulp_clock_gating (
    input  logic clk_i,
    input  logic en_i,
    input  logic test_en_i,
    output logic clk_o
);

  gf180mcu_fd_sc_mcu7t5v0__icgtp_1 i_icg (
      .CLK(clk_i),
      .E  (en_i),
      .TE (test_en_i),
      .Q  (clk_o)
  );

endmodule

module cluster_clock_gating (
    input  logic clk_i,
    input  logic en_i,
    input  logic test_en_i,
    output logic clk_o
);

  gf180mcu_fd_sc_mcu7t5v0__icgtp_1 i_icg (
      .CLK(clk_i),
      .E  (en_i),
      .TE (test_en_i),
      .Q  (clk_o)
  );

endmodule

// cv32e40p names the test enable scan_cg_en_i. Same pin, same cell.
module cv32e40p_clock_gate (
    input  logic clk_i,
    input  logic en_i,
    input  logic scan_cg_en_i,
    output logic clk_o
);

  gf180mcu_fd_sc_mcu7t5v0__icgtp_1 i_icg (
      .CLK(clk_i),
      .E  (en_i),
      .TE (scan_cg_en_i),
      .Q  (clk_o)
  );

endmodule

// --- Clock inversion ---------------------------------------------------------
// gf180mcu_fd_sc_mcu7t5v0__clkinv_1, 8.7808 um2, drive strengths 1 through 20.
//
// clkinv rather than inv: identical area at _1 (8.7808 both), and it is the
// library's clock inverter, so the choice states intent at no cost. Do not read
// more into it than that: ABC already picks clkinv_1 as its general-purpose
// inverter, 9,974 of them in the flattened netlist, so the name carries no
// special meaning to the flow. Pins are I and ZN.

module pulp_clock_inverter (
    input  logic clk_i,
    output logic clk_o
);

  gf180mcu_fd_sc_mcu7t5v0__clkinv_1 i_clkinv (
      .I (clk_i),
      .ZN(clk_o)
  );

endmodule

module cluster_clock_inverter (
    input  logic clk_i,
    output logic clk_o
);

  gf180mcu_fd_sc_mcu7t5v0__clkinv_1 i_clkinv (
      .I (clk_i),
      .ZN(clk_o)
  );

endmodule

// --- Clock muxing ------------------------------------------------------------
// gf180mcu_fd_sc_mcu7t5v0__mux2_1, 28.5376 um2, Z = (I0 & !S) | (I1 & S).
//
// GF180MCU has no glitch-free clock mux, and this does not want one. The only
// clock-specific cells in the library are clkbuf, clkinv, icgtp and icgtn; mux2
// and mux4 are ordinary data muxes. That is the right cell here for a reason
// beyond availability: upstream's own generic and FPGA implementations of this
// module are the plain ternary `clk_sel_i ? clk1_i : clk0_i`, and every live
// instance selects between phase variants of one clock rather than between
// unrelated clocks. Each of the two SPI masters has a CPHA mux, between a clock
// and its gated self, and a CPOL mux, between a clock and its own inversion; the
// JTAG TAP mux picks between TCK and inverted TCK for test mode; and the three
// uDMA clock generators pick between a divided clock and the source it was
// divided from. That is four, one and three. A break-before-make
// mux would stall the SPI clock mid-transfer on a CPOL change rather than
// protect anything.
//
// It could not be built behind this port list in any case. Glitch-free muxing
// needs synchroniser flops, the port list upstream fixed has no reset, and
// adding one means patching every instantiation site, which would give up
// ticket 03's result that the SoC needs no upstream source patches, and ticket
// 13's hope of contributing this file back. Reset-less synchronisers would come
// up unknown and propagate X into the clock, which is exactly what the
// gate-level boot simulation in this map's destination has to survive.
//
// The hazard is real but it belongs to software: cfg_cpha_i, cfg_cpol_i and the
// uDMA r_clockout_mux are APB-writable at any time, and switching one while the
// peripheral is clocking can produce a runt. Configure the peripheral before
// enabling it. That constraint is upstream's, unchanged by this file.

module pulp_clock_mux2 (
    input  logic clk0_i,
    input  logic clk1_i,
    input  logic clk_sel_i,
    output logic clk_o
);

  gf180mcu_fd_sc_mcu7t5v0__mux2_1 i_clkmux (
      .I0(clk0_i),
      .I1(clk1_i),
      .S (clk_sel_i),
      .Z (clk_o)
  );

endmodule
