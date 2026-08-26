// Copyright 2026 Yusef Karim
// Solderpad Hardware License, Version 2.1, see LICENSE.md for details.
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
//
// Seeded from `src/chip_core.sv` in the wafer.space gf180mcu project template
// (Apache-2.0, (c) 2025 Project Template Contributors). The template's own
// chip_core is a counter and two SRAMs; what survives from it is the module's
// role and its port naming, which `chip_top.sv` and the LibreLane configuration
// both depend on.
//
// Everything between the pad ring and the SoC lives here: `chip_top.sv` holds
// pad cells and nothing else, so that its instance names stay a clean one-to-one
// match for `PAD_SOUTH`/`PAD_EAST`/`PAD_NORTH`/`PAD_WEST`.

`include "pulp_soc_defines.svh"

`default_nettype none

module chip_core #(
    parameter int NUM_BIDIR_PADS = `N_IO
) (
`ifdef USE_POWER_PINS
    inout  wire                      VDD,
    inout  wire                      VSS,
`endif

    input  wire                      clk,        // ref_clk_i, 5 MHz
    input  wire                      rst_n,      // asynchronous, synchronised inside safe_domain

    input  wire                      jtag_tck,
    input  wire                      jtag_tms,
    input  wire                      jtag_tdi,
    // Upstream names the port `jtag_trst_i` and wires it straight to
    // `soc_domain`'s `jtag_trst_ni`, so the pad signal is active low.
    input  wire                      jtag_trst,
    output wire                      jtag_tdo,
    input  wire                      stm,        // forces every pad to a safe zero state

    input  wire [NUM_BIDIR_PADS-1:0] bidir_in,   // pad Y
    output wire [NUM_BIDIR_PADS-1:0] bidir_out,  // pad A
    output wire [NUM_BIDIR_PADS-1:0] bidir_oe,   // pad OE
    output wire [NUM_BIDIR_PADS-1:0] bidir_cs,   // pad CS: 1 = Schmitt trigger input
    output wire [NUM_BIDIR_PADS-1:0] bidir_sl,   // pad SL: 1 = slow slew
    output wire [NUM_BIDIR_PADS-1:0] bidir_ie,   // pad IE: 1 = input buffer enabled
    output wire [NUM_BIDIR_PADS-1:0] bidir_pu,   // pad PU
    output wire [NUM_BIDIR_PADS-1:0] bidir_pd    // pad PD
);

  // The bidirectional pad count is the pad frame's view of `N_IO` and there is
  // no mapping layer between them, so a mismatch would silently leave pads
  // unbonded. Fail at elaboration rather than in the netlist.
  if (NUM_BIDIR_PADS != `N_IO)
    $error("chip_core: NUM_BIDIR_PADS is %0d, `N_IO is %0d", NUM_BIDIR_PADS, `N_IO);

  wire [`N_IO-1:0][`NBIT_PADCFG-1:0] s_pad_cfg;
  wire [`N_IO-1:0]                   s_pad_cfg_spare;

  core_v_mcu #(
      .USE_FPU (0),
      .USE_HWPE(0)
  ) i_core_v_mcu (
      .jtag_tck_i (jtag_tck),
      .jtag_tdi_i (jtag_tdi),
      .jtag_tdo_o (jtag_tdo),
      .jtag_tms_i (jtag_tms),
      .jtag_trst_i(jtag_trst),
      .ref_clk_i  (clk),
      .rstn_i     (rst_n),
      .stm_i      (stm),
      .io_in_i    (bidir_in),
      .io_out_o   (bidir_out),
      .pad_cfg_o  (s_pad_cfg),
      .io_oe_o    (bidir_oe)
  );

  // `pad_cfg_o` is upstream's generic six-bit-per-pad electrical configuration
  // bus. Upstream never says what the bits mean ("electrical configuration,
  // which is not implemented in the current design", apb_soc_ctrl.rst), so the
  // mapping onto `gf180mcu_ocd_io__bi_24t`'s five configuration pins is fixed
  // here and nowhere else. Software reaches it through `apb_soc_ctrl`'s
  // IO_CTRL/WCFGFUN registers.
  //
  // The register resets to all ones, and that is deliberately the safe state
  // under this mapping: Schmitt-trigger inputs, slow slew, input buffer on, and
  // no pull. The pad's pull devices are `~OE && PU && ~PD` (up) and
  // `~OE && ~PU && PD` (down), so PU and PD both high is "neither", not
  // contention, and pulls are inert whenever the pad is driving anyway.
  for (genvar i = 0; i < `N_IO; i++) begin : gen_pad_cfg
    assign bidir_cs[i] = s_pad_cfg[i][0];
    assign bidir_sl[i] = s_pad_cfg[i][1];
    assign bidir_ie[i] = s_pad_cfg[i][2];
    assign bidir_pu[i] = s_pad_cfg[i][3];
    assign bidir_pd[i] = s_pad_cfg[i][4];

    // Bit 5 has no pad pin to drive. It stays readable and writable so the
    // register map does not change shape, and is terminated below rather than
    // left dangling for synthesis to warn about.
    assign s_pad_cfg_spare[i] = s_pad_cfg[i][5];
  end

  wire _unused_pad_cfg;
  assign _unused_pad_cfg = &s_pad_cfg_spare;

endmodule

`default_nettype wire
