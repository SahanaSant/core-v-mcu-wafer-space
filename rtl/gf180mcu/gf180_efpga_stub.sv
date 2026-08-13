// Copyright 2026 Yusef Karim
// Solderpad Hardware License, Version 2.1, see LICENSE.md for details.
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1

// GF180MCU implementation of the eFPGA slot: there isn't one.
//
// `quicklogic.com:ip:efpga` is not open, has no GF180 implementation, and its
// sources sit inside `protect envelopes that no open front end reads. This
// module keeps the SoC's eFPGA interfaces terminated so the rest of the design
// elaborates and synthesises unchanged, with the same name and port list as
// upstream's `efpga_subsystem` so no upstream file needs patching.
//
// Termination policy:
//   - the four TCDM master ports into L2 never request,
//   - the APB-T1 TCDM slave answers through upstream's own `tcdm_error_slave`,
//     so an access to it returns 0xBADACCE5 rather than hanging the bus,
//   - the APB programming slot at 0x1A30_0000 stays decoded and answers every
//     access with zero, so software that probes the FCB registers reads zeros
//     instead of stalling or trapping,
//   - the eFPGA IO, event and test outputs are driven low.

`include "pulp_soc_defines.svh"

module efpga_subsystem #(
    parameter L2_ADDR_WIDTH       = 32,
    parameter APB_FPGA_ADDR_WIDTH = 20
) (
    input logic asic_clk_i,
    input logic fpga_clk0_i,
    input logic fpga_clk1_i,
    input logic fpga_clk2_i,
    input logic fpga_clk3_i,
    input logic fpga_clk4_i,
    input logic fpga_clk5_i,

    input logic       clk_gating_dc_fifo_i,
    input logic [3:0] reset_type1_efpga_i,
    input logic       enable_udma_efpga_i,
    input logic       enable_events_efpga_i,
    input logic       enable_apb_efpga_i,
    input logic       enable_tcdm3_efpga_i,
    input logic       enable_tcdm2_efpga_i,
    input logic       enable_tcdm1_efpga_i,
    input logic       enable_tcdm0_efpga_i,

    input logic        rst_n,
    input logic [31:0] control_in,

    XBAR_TCDM_BUS.Master l2_asic_tcdm_o[`N_EFPGA_TCDM_PORTS-1:0],
    APB_BUS.Slave        apbprogram_i,
    XBAR_TCDM_BUS.Slave  apbt1_i,

    output       [               31:0] status_out,
    output       [                7:0] version,
    output logic [      `N_FPGAIO-1:0] fpgaio_oe_o,
    input  logic [      `N_FPGAIO-1:0] fpgaio_in_i,
    output logic [      `N_FPGAIO-1:0] fpgaio_out_o,
    output logic [`N_EFPGA_EVENTS-1:0] efpga_event_o,

    //eFPGA TEST MODE
    output logic [15:0] testio_o,
    input  logic [20:0] testio_i
);

  // No master ever requests, so the interconnect ports constant-fold away.
  for (genvar i = 0; i < `N_EFPGA_TCDM_PORTS; i++) begin : gen_tcdm_master_tieoff
    assign l2_asic_tcdm_o[i].req   = 1'b0;
    assign l2_asic_tcdm_o[i].add   = '0;
    assign l2_asic_tcdm_o[i].wen   = 1'b1;
    assign l2_asic_tcdm_o[i].wdata = '0;
    assign l2_asic_tcdm_o[i].be    = '0;
  end

  tcdm_error_slave i_apbt1_error_slave (
      .clk_i (asic_clk_i),
      .rst_ni(rst_n),
      .slave (apbt1_i)
  );

  assign apbprogram_i.prdata  = '0;
  assign apbprogram_i.pready  = 1'b1;
  assign apbprogram_i.pslverr = 1'b0;

  assign status_out           = '0;
  assign version              = '0;
  assign fpgaio_oe_o          = '0;
  assign fpgaio_out_o         = '0;
  assign efpga_event_o        = '0;
  assign testio_o             = '0;

endmodule
