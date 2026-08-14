// Copyright 2026 Yusef Karim
// Solderpad Hardware License, Version 2.1, see LICENSE.md for details.
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1

// GF180MCU clock generator for the CORE-V MCU. Ticket 05 settled the
// architecture; this is that decision built and measured.
//
// apb_pll is the whole clock generator, not a PLL cell inside one: upstream's
// ASIC build wraps a PLL18_TOP hard macro, and its FPGA build (fpga_pll.sv)
// replaces the entire module instead of swapping the macro inside it. There is
// no open GF180 PLL, so this file takes the FPGA route: apb_pll itself is
// provided here, register file and all.
//
// Clock source: external ref_clk_i bypass, undivided. soc_clk_o, periph_clk_o
// and cluster_clk_o are ref_clk_i, wired straight through with no divider and
// no mux, because there is nothing to divide from or select between. That
// makes ref_clk_i the actual SoC clock, not a stand-in for one hidden behind a
// black box.
//
// FLL/apb_pll register slot: an inert stub, matching fpga_pll.sv's own
// precedent exactly. The eight registers below (ControlReg, DivisorReg,
// FracReg, Spread1Reg, Spread2Reg, SocDiv, PeriphDiv, ClusterDiv) stay
// APB-readable and -writable at the same offsets upstream's ASIC and FPGA
// builds both use, so software that pokes them does not fault or hang, but
// nothing they hold drives any output. The PD/PDDP/MODE/DM/BYPASS decode that
// fed the PLL18_TOP hard macro is gone with it: there is no hardware left for
// those fields to configure, so keeping the combinational decode around would
// describe behaviour that does not exist. LOCK reads back tied to 1, so
// software that polls it for "PLL locked" before proceeding never blocks.
//
// The one register-adjacent behaviour that stays structurally real is
// ref_clk_o's divide-by-40, feeding low_speed_clk_i on SPI/RTC-adjacent logic
// downstream. It is not driven by a register on either upstream precedent
// (apb_pll.sv gates it through RefDiv, itself APB-writable but reset to a
// fixed 40; fpga_pll.sv hardcodes the 40 directly), so this file follows
// fpga_pll.sv and hardcodes it too: one clkdv instance, reused unmodified from
// both upstream files, CLK_DIV_VALUE tied to 10'd40.
//
// The five analog PLL supply ports (AVDD, AVDD2, AVSS, VDDC, VSSC) are gone.
// Nothing analog is instantiated, so there is no supply to thread to the SoC
// boundary; soc_peripherals.sv's instantiation of this module drops the
// connections to match.

module apb_pll #(
    parameter APB_ADDR_WIDTH = 12
) (
    input  logic                      ref_clk_i,
    output logic                      soc_clk_o,
    output logic                      periph_clk_o,
    output logic                      cluster_clk_o,
    output logic                      ref_clk_o,
    input  logic                      rst_ni,
    input  logic                      HCLK,
    input  logic                      HRESETn,
    input  logic [APB_ADDR_WIDTH-1:0] PADDR,
    input  logic [              31:0] PWDATA,
    input  logic                      PWRITE,
    input  logic                      PSEL,
    input  logic                      PENABLE,
    output logic [              31:0] PRDATA,
    output logic                      PREADY,
    output logic                      PSLVERR
);

  logic [31:0] ControlReg;
  logic [31:0] DivisorReg;
  logic [31:0] FracReg;
  logic [31:0] Spread1Reg;
  logic [31:0] Spread2Reg;
  logic [31:0] SocDiv;
  logic [31:0] PeriphDiv;
  logic [31:0] ClusterDiv;

  logic        slverr;
  logic        ready;

  localparam reg_CTL = 0;
  localparam reg_DIV = 4;
  localparam reg_FRAC = 8;
  localparam reg_SS1 = 12;
  localparam reg_SS2 = 16;
  localparam reg_SOC = 20;
  localparam reg_PERIPH = 24;
  localparam reg_CLUSTER = 28;

  enum logic [3:0] {
    IDLE,
    READ,
    WRITE,
    WAIT
  } state;

  always_comb begin
    PREADY  = ready & PENABLE;
    PSLVERR = slverr & PENABLE;
  end

  always_ff @(posedge HCLK, negedge HRESETn) begin
    if (!HRESETn) begin
      state      <= IDLE;
      ControlReg <= 32'h03000103;  // matches apb_pll.sv's PD, PDDP, Refdiv=1, RESET, BYPASS
      DivisorReg <= 32'h00A00004;
      FracReg    <= 32'h0;
      Spread1Reg <= 32'h0;
      Spread2Reg <= 32'h0;
      SocDiv     <= 32'd0;
      PeriphDiv  <= 32'd0;
      ClusterDiv <= 32'd0;

      ready      <= 0;
      slverr     <= 0;
    end else begin
      case (state)
        IDLE: begin
          ready <= 0;
          if (PSEL & PENABLE)
            if (PWRITE) state <= WRITE;
            else state <= READ;
        end
        WRITE: begin
          case (PADDR[APB_ADDR_WIDTH-1:0])
            reg_CTL:     ControlReg <= PENABLE ? PWDATA : ControlReg;
            reg_DIV:     DivisorReg <= PENABLE ? PWDATA : DivisorReg;
            reg_SS1:     Spread1Reg <= PENABLE ? PWDATA : Spread1Reg;
            reg_SS2:     Spread2Reg <= PENABLE ? PWDATA : Spread2Reg;
            reg_FRAC:    FracReg <= PENABLE ? PWDATA : FracReg;
            reg_SOC:     SocDiv <= PENABLE ? PWDATA : SocDiv;
            reg_PERIPH:  PeriphDiv <= PENABLE ? PWDATA : PeriphDiv;
            reg_CLUSTER: ClusterDiv <= PENABLE ? PWDATA : ClusterDiv;
            default:     slverr <= 1;
          endcase
          ready <= 1;
          if (PENABLE == 0) state <= IDLE;
        end
        READ: begin
          case (PADDR[APB_ADDR_WIDTH-1:0])
            // LOCK tied to 1: this bit read "PLL locked" on the hard macro
            // upstream had; there is no PLL to lock here, and the bypass
            // clock is valid as soon as ref_clk_i is, so 1 is both the inert
            // answer and the true one.
            reg_CTL:     PRDATA <= {1'b1, ControlReg[30:0]};
            reg_DIV:     PRDATA <= DivisorReg;
            reg_SS1:     PRDATA <= Spread1Reg;
            reg_SS2:     PRDATA <= Spread2Reg;
            reg_FRAC:    PRDATA <= FracReg;
            reg_SOC:     PRDATA <= SocDiv;
            reg_PERIPH:  PRDATA <= PeriphDiv;
            reg_CLUSTER: PRDATA <= ClusterDiv;
            default:     slverr <= 1;
          endcase
          ready <= 1;
          if (PENABLE == 0) state <= IDLE;
        end
      endcase
    end
  end

  assign soc_clk_o     = ref_clk_i;
  assign periph_clk_o  = ref_clk_i;
  assign cluster_clk_o = ref_clk_i;

  clkdv ref_div (
      .clk_i(soc_clk_o),
      .clk_o(ref_clk_o),
      .rst_ni(rst_ni),
      .CLK_DIV_VALUE(10'd40)
  );

endmodule  // apb_pll

// Reused unmodified from apb_pll.sv / fpga_pll.sv: a free-running divide-by-N
// counter, bypassed to clk_i directly at N <= 1.
module clkdv (
    input  logic       clk_i,
    input  logic       rst_ni,
    output logic       clk_o,
    input  logic [9:0] CLK_DIV_VALUE
);
  localparam COUNTER_WIDTH = 10;

  logic [COUNTER_WIDTH-1:0] clk_counter;
  logic                     clkout;

  assign clk_o = (CLK_DIV_VALUE <= 1) ? clk_i : clkout;

  always_ff @(posedge clk_i, negedge rst_ni) begin
    if (!rst_ni) begin
      clk_counter <= '0;
      clkout      <= 1'b0;
    end else begin
      clk_counter <= clk_counter + 1;
      case (CLK_DIV_VALUE)
        0, 1: clkout <= 0;
        2: clkout <= ~clkout;
        default: begin
          if (clk_counter == ((CLK_DIV_VALUE - 1) >> 1)) clkout <= 1;
          if (clk_counter == (CLK_DIV_VALUE - 1)) begin
            clkout      <= ~clkout;
            clk_counter <= 0;
          end
        end
      endcase
    end
  end

endmodule : clkdv
