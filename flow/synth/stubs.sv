// Copyright 2026 Yusef Karim
// Solderpad Hardware License, Version 2.1, see LICENSE.md for details.
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1

// Black boxes for every module the CORE-V MCU instantiates but does not define.
//
// This is the definitive list, measured by elaborating the SoC (see
// `flow/synth/elaborate.sh`), not a guess: with the eFPGA replaced by
// `rtl/gf180mcu/gf180_efpga_stub.sv`, ten modules were left unresolved. Ticket
// 16 wrote the six clock cells and ticket 19 the two L2 memories, so two are
// left. Upstream supplies them per target, from `emulation/xilinx/` for the FPGA
// and from `rtl/simulation/` for simulation; the GF180MCU implementations belong
// in `rtl/gf180mcu/`.
//
// Each stub here is empty on purpose. It carries the port list so the hierarchy
// closes and synthesis has something to instantiate, and it disappears from
// this file the moment the real cell lands in `rtl/gf180mcu/`. Keep the ports
// identical to the instantiation sites; the widths below are upstream's.

// --- Memories --------------------------------------------------------------
// The two L2 banks left this file in ticket 19: `rtl/gf180mcu/gf180_l2_ram.sv`
// binds both upstream names to four ganged `sram1024x8` macros, and the macro
// itself arrives as a black box from its liberty rather than from here.
//
// The boot ROM left this file in ticket 23:
// `rtl/gf180mcu/gf180_bootrom.sv` (a generated file; see its header) replaces
// upstream's $readmemh-initialised simulation model with a case statement
// over the compiled sw/bootrom image.

// --- Clock source ----------------------------------------------------------
// The SoC's clock generator, behind an APB register file. Upstream's ASIC
// version wraps a PLL18_TOP hard macro and its FPGA version replaces the whole
// module; GF180MCU has no open PLL, so it gets replaced the same way. Ticket 05
// decides what goes inside.

(* blackbox *)
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
    input  logic [                31:0] PWDATA,
    input  logic                      PWRITE,
    input  logic                      PSEL,
    input  logic                      PENABLE,
    output logic [                31:0] PRDATA,
    output logic                      PREADY,
    output logic                      PSLVERR,
    // Analog supplies for the hard PLL, threaded up through soc_domain to the
    // ports of core_v_mcu itself. They survive here so the hierarchy matches
    // upstream; whatever replaces this module decides what to do with them.
    inout                             AVDD,
    inout                             AVDD2,
    inout                             AVSS,
    inout                             VDDC,
    inout                             VSSC
);
endmodule
