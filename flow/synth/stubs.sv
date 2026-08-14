// Copyright 2026 Yusef Karim
// Solderpad Hardware License, Version 2.1, see LICENSE.md for details.
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1

// Black boxes for every module the CORE-V MCU instantiates but does not define.
//
// This is the definitive list, measured by elaborating the SoC (see
// `flow/synth/elaborate.sh`), not a guess: with the eFPGA replaced by
// `rtl/gf180mcu/gf180_efpga_stub.sv`, ten modules were left unresolved. Ticket
// 16 wrote the six clock cells, ticket 19 the two L2 memories, ticket 23 the
// boot ROM and ticket 24 the clock generator, so this file is now empty of
// stubs: every module the SoC instantiates is defined somewhere.
//
// Each stub here is empty on purpose. It carries the port list so the hierarchy
// closes and synthesis has something to instantiate, and it disappears from
// this file the moment the real cell lands in `rtl/gf180mcu/`. Keep the ports
// identical to the instantiation sites; the widths below are upstream's.
//
// The two L2 banks left this file in ticket 19: `rtl/gf180mcu/gf180_l2_ram.sv`
// binds both upstream names to four ganged `sram1024x8` macros, and the macro
// itself arrives as a black box from its liberty rather than from here.
//
// The boot ROM left this file in ticket 23:
// `rtl/gf180mcu/gf180_bootrom.sv` (a generated file; see its header) replaces
// upstream's $readmemh-initialised simulation model with a case statement
// over the compiled sw/bootrom image.
//
// The clock generator left this file in ticket 24: `rtl/gf180mcu/gf180_clk_gen.sv`
// provides `apb_pll` for real, ref_clk_i bypassed straight through per ticket
// 05's answer.
