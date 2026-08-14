// Copyright 2026 Yusef Karim
// Solderpad Hardware License, Version 2.1, see LICENSE.md for details.
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
//
// Seeded from `src/chip_top.sv` in the wafer.space gf180mcu project template
// (Apache-2.0, (c) 2025 Project Template Contributors), which is where the pad
// instance names, the generate-loop shapes and the marker-cell block come from.
// Three deliberate differences from the template, each with a reason:
//
//  1. No `gf180mcu_xxx_io__*` indirection. Ticket 18 fixed the ring at
//     `gf180mcu_ocd_io` (5.0 V over a 3.3 V core, level shifter inside each pad
//     cell), and the foundry `gf180mcu_fd_io` alternative the template carries
//     is not buildable here at all, since it has no core-supply pad and shorts
//     the two domains on purpose. Cells are named directly, the way
//     `rtl/gf180mcu/gf180_clk_gate.sv` names standard cells.
//  2. No `slot_defines.svh`. The design does not fit in anything smaller than
//     the 1x1 slot, so there is one pad count per parameter and no slot switch.
//  3. One west input position carries a `bi_24t` rather than an `in_c`, so that
//     `jtag_tdo_o` gets an output-capable pad beside the rest of JTAG. See the
//     pad budget note below.
//
// Pad budget (ticket 06 assigned the functions; ticket 25 assigned the pads).
// The 1x1 slot is 40 bidirectional, 14 input-only and 2 analog. The template's
// README is explicit that the *count* and *position* of every pad is what the
// default bonding setup and the breakout PCB are drawn against, and that only a
// signal pad's type may change. So all 58 positions below are the template's,
// unmoved, and the only edit is one type:
//
//    40 x bi_24t   io_in_i/io_out_o/io_oe_o[39:0], all forty bonded, which
//                  keeps ticket 06's spare at io_num 39 a genuine spare.
//     1 x in_s     ref_clk_i, Schmitt trigger because it is a clock input.
//     1 x in_c     rstn_i.
//     1 x bi_24t   jtag_tdo_o. This is the template's `inputs[11]` position,
//                  retyped: `jtag_tdo_o` is the only signal outside the io
//                  array that drives, and `in_c`/`in_s` have no output driver.
//                  Spending a bidirectional pad from the io array instead would
//                  have cost ticket 06's spare for no gain.
//    11 x in_c     jtag_tck/tms/tdi/trst and stm_i, then six spares.
//     2 x asig_5p0 unused. Nothing in this design is analog (ticket 05 dropped
//                  the PLL's analog ports), but the positions are part of the
//                  bonding setup, so the pads stay and the ports float.
//
// The five JTAG signals sit in one contiguous run on the west edge, immediately
// after the core VDD/VSS pads, with the I/O-domain pair at the template's
// position 11/12 separating TDO from the four inputs.

`default_nettype none

module chip_top #(
    // I/O-domain power pads: 5.0 V ring (ticket 18).
    parameter int NUM_DVDD_PADS   = 6,
    parameter int NUM_DVSS_PADS   = 8,
    // Core-domain power pads: 3.3 V single rail (tickets 14, 21).
    parameter int NUM_VDD_PADS    = 2,
    parameter int NUM_VSS_PADS    = 2,
    // Signal pads.
    parameter int NUM_INPUT_PADS  = 11,
    parameter int NUM_BIDIR_PADS  = 40,
    parameter int NUM_ANALOG_PADS = 2
) (
`ifdef USE_POWER_PINS
    inout wire                       VDD,
    inout wire                       VSS,
    inout wire                       DVDD,
    inout wire                       DVSS,
`endif

    inout wire                       clk_PAD,
    inout wire                       rst_n_PAD,
    inout wire                       jtag_tdo_PAD,

    inout wire [ NUM_INPUT_PADS-1:0] input_PAD,
    inout wire [ NUM_BIDIR_PADS-1:0] bidir_PAD,

    inout wire [NUM_ANALOG_PADS-1:0] analog_PAD
);

  // West input row, in bonding order. Six spares follow.
  localparam int PadJtagTck  = 0;
  localparam int PadJtagTms  = 1;
  localparam int PadJtagTdi  = 2;
  localparam int PadJtagTrst = 3;
  localparam int PadStm      = 4;

  wire                      clk_PAD2CORE;
  wire                      rst_n_PAD2CORE;
  wire                      jtag_tdo_CORE2PAD;

  wire [NUM_INPUT_PADS-1:0] input_PAD2CORE;

  wire [NUM_BIDIR_PADS-1:0] bidir_PAD2CORE;
  wire [NUM_BIDIR_PADS-1:0] bidir_CORE2PAD;
  wire [NUM_BIDIR_PADS-1:0] bidir_CORE2PAD_OE;
  wire [NUM_BIDIR_PADS-1:0] bidir_CORE2PAD_CS;
  wire [NUM_BIDIR_PADS-1:0] bidir_CORE2PAD_SL;
  wire [NUM_BIDIR_PADS-1:0] bidir_CORE2PAD_IE;
  wire [NUM_BIDIR_PADS-1:0] bidir_CORE2PAD_PU;
  wire [NUM_BIDIR_PADS-1:0] bidir_CORE2PAD_PD;

  // Power and ground pad instances. `gf180mcu_ocd_io__vdd`/`__vss` bond the
  // core rail with DVDD and DVSS explicitly unconnected, which is the whole
  // reason ticket 18 could split the ring at all: the foundry library has no
  // core-supply pad cell.
  generate
    for (genvar i = 0; i < NUM_DVDD_PADS; i++) begin : dvdd_pads
      (* keep *) gf180mcu_ocd_io__dvdd pad (
`ifdef USE_POWER_PINS
          .DVDD(DVDD),
          .DVSS(DVSS),
          .VDD (VDD),
          .VSS (VSS)
`endif
      );
    end
    for (genvar i = 0; i < NUM_DVSS_PADS; i++) begin : dvss_pads
      (* keep *) gf180mcu_ocd_io__dvss pad (
`ifdef USE_POWER_PINS
          .DVDD(DVDD),
          .DVSS(DVSS),
          .VDD (VDD),
          .VSS (VSS)
`endif
      );
    end
    for (genvar i = 0; i < NUM_VDD_PADS; i++) begin : vdd_pads
      (* keep *) gf180mcu_ocd_io__vdd pad (
`ifdef USE_POWER_PINS
          .DVDD(DVDD),
          .DVSS(DVSS),
          .VDD (VDD),
          .VSS (VSS)
`endif
      );
    end
    for (genvar i = 0; i < NUM_VSS_PADS; i++) begin : vss_pads
      (* keep *) gf180mcu_ocd_io__vss pad (
`ifdef USE_POWER_PINS
          .DVDD(DVDD),
          .DVSS(DVSS),
          .VDD (VDD),
          .VSS (VSS)
`endif
      );
    end
  endgenerate

  // Reference clock. Schmitt trigger, because a board-level oscillator arriving
  // over a wire bond is the one input whose edge quality is not this chip's to
  // control (ticket 05: there is no PLL and no on-die oscillator).
  gf180mcu_ocd_io__in_s clk_pad (
`ifdef USE_POWER_PINS
      .DVDD(DVDD),
      .DVSS(DVSS),
      .VDD (VDD),
      .VSS (VSS),
`endif
      .Y  (clk_PAD2CORE),
      .PAD(clk_PAD),
      .PU (1'b0),
      .PD (1'b0)
  );

  // Reset. Active low, and there is no on-die power-on reset or debounce
  // (ticket 05 assumes an external supervisor), so it is pulled down here: an
  // unbonded or floating reset holds the chip in reset rather than releasing it
  // into an undefined state.
  gf180mcu_ocd_io__in_c rst_n_pad (
`ifdef USE_POWER_PINS
      .DVDD(DVDD),
      .DVSS(DVSS),
      .VDD (VDD),
      .VSS (VSS),
`endif
      .Y  (rst_n_PAD2CORE),
      .PAD(rst_n_PAD),
      .PU (1'b0),
      .PD (1'b1)
  );

  // JTAG TDO. Permanently an output: OE high, input buffer off, no pull.
  gf180mcu_ocd_io__bi_24t jtag_tdo_pad (
`ifdef USE_POWER_PINS
      .DVDD(DVDD),
      .DVSS(DVSS),
      .VDD (VDD),
      .VSS (VSS),
`endif
      .A  (jtag_tdo_CORE2PAD),
      .OE (1'b1),
      .Y  (),
      .PAD(jtag_tdo_PAD),
      .CS (1'b0),
      .SL (1'b1),
      .IE (1'b0),
      .PU (1'b0),
      .PD (1'b0)
  );

  // West input row. JTAG's four inputs, `stm_i`, then six spares. Every one is
  // pulled down: TRST and STM both have a defined safe level at 0 (JTAG held in
  // reset, pads not forced), and a spare pad left floating is an input buffer
  // oscillating on noise.
  generate
    for (genvar i = 0; i < NUM_INPUT_PADS; i++) begin : inputs
      (* keep *) gf180mcu_ocd_io__in_c pad (
`ifdef USE_POWER_PINS
          .DVDD(DVDD),
          .DVSS(DVSS),
          .VDD (VDD),
          .VSS (VSS),
`endif
          .Y  (input_PAD2CORE[i]),
          .PAD(input_PAD[i]),
          .PU (1'b0),
          .PD (1'b1)
      );
    end
  endgenerate

  // The io array. Everything that ever drives out lives here (ticket 06), and
  // the five configuration pins are software-controlled through
  // `apb_soc_ctrl`'s pad configuration register; `chip_core.sv` owns the bit
  // mapping.
  generate
    for (genvar i = 0; i < NUM_BIDIR_PADS; i++) begin : bidir
      (* keep *) gf180mcu_ocd_io__bi_24t pad (
`ifdef USE_POWER_PINS
          .DVDD(DVDD),
          .DVSS(DVSS),
          .VDD (VDD),
          .VSS (VSS),
`endif
          .A  (bidir_CORE2PAD[i]),
          .OE (bidir_CORE2PAD_OE[i]),
          .Y  (bidir_PAD2CORE[i]),
          .PAD(bidir_PAD[i]),
          .CS (bidir_CORE2PAD_CS[i]),
          .SL (bidir_CORE2PAD_SL[i]),
          .IE (bidir_CORE2PAD_IE[i]),
          .PU (bidir_CORE2PAD_PU[i]),
          .PD (bidir_CORE2PAD_PD[i])
      );
    end
  endgenerate

  // Analog pads, kept for their bonding positions only. `asig_5p0` is a
  // straight pass-through with ESD, so an unconnected one is inert.
  generate
    for (genvar i = 0; i < NUM_ANALOG_PADS; i++) begin : analog
      (* keep *) gf180mcu_ocd_io__asig_5p0 pad (
`ifdef USE_POWER_PINS
          .DVDD  (DVDD),
          .DVSS  (DVSS),
          .VDD   (VDD),
          .VSS   (VSS),
`endif
          .ASIG5V(analog_PAD[i])
      );
    end
  endgenerate

  chip_core #(
      .NUM_BIDIR_PADS(NUM_BIDIR_PADS)
  ) i_chip_core (
`ifdef USE_POWER_PINS
      .VDD      (VDD),
      .VSS      (VSS),
`endif

      .clk      (clk_PAD2CORE),
      .rst_n    (rst_n_PAD2CORE),

      .jtag_tck (input_PAD2CORE[PadJtagTck]),
      .jtag_tms (input_PAD2CORE[PadJtagTms]),
      .jtag_tdi (input_PAD2CORE[PadJtagTdi]),
      .jtag_trst(input_PAD2CORE[PadJtagTrst]),
      .jtag_tdo (jtag_tdo_CORE2PAD),
      .stm      (input_PAD2CORE[PadStm]),

      .bidir_in (bidir_PAD2CORE),
      .bidir_out(bidir_CORE2PAD),
      .bidir_oe (bidir_CORE2PAD_OE),
      .bidir_cs (bidir_CORE2PAD_CS),
      .bidir_sl (bidir_CORE2PAD_SL),
      .bidir_ie (bidir_CORE2PAD_IE),
      .bidir_pu (bidir_CORE2PAD_PU),
      .bidir_pd (bidir_CORE2PAD_PD)
  );

  // The six spare west inputs have no consumer. Terminate them so synthesis
  // does not warn, the same way `chip_core.sv` terminates the spare pad
  // configuration bit.
  wire _unused_input_pads;
  assign _unused_input_pads = &input_PAD2CORE[NUM_INPUT_PADS-1:PadStm+1];

  // Do not remove, necessary for tapeout. wafer.space replaces the placeholder
  // GDS in `ip/` with the real cells at submission; each must appear exactly
  // once, which is what `rtl/chip/README.md` records the precheck as enforcing.
  (* keep *) gf180mcu_ws_ip__qrcode_id qrcode_id ();
  (* keep *) gf180mcu_ws_ip__shuttle_id shuttle_id ();
  (* keep *) gf180mcu_ws_ip__project_id project_id ();
  (* keep *) gf180mcu_ws_ip__marker marker ();
  (* keep *) gf180mcu_ws_ip__logo wafer_space_logo ();

endmodule

`default_nettype wire
