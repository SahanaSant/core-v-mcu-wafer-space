# GF180MCU technology cells

One implementation per technology-dependent cell, mirroring upstream's
`emulation/xilinx/rtl/`. Upstream already separates portable RTL from per-target
implementations and selects between them with fusesoc filesets, so this directory is a third
sibling of `rtl-simulation` and `emulation-rtl`. Nothing here should contain design logic.

## What has to be provided

This is the measured list, not a guess. `make elaborate` reads the whole SoC through
yosys-slang and ends its report with one line per unresolved module and the number of
instances of it; the table below is that report, with a home for each entry. Re-run it after
any RTL change and the list moves with the design.

| Module to provide | Instances | File here | Upstream's version | Notes |
| --- | --- | --- | --- | --- |
| `pulp_clock_gating` | 55 | `gf180_clk_gate.sv` | `pulp_clock_gating_xilinx.sv` | bind to `gf180mcu_fd_sc_mcu7t5v0__icgtp_*` |
| `pulp_clock_mux2` | 8 | `gf180_clk_gate.sv` | `tech_cells_generic` | glitch-free clock mux, in the uDMA clock dividers |
| `pulp_clock_inverter` | 4 | `gf180_clk_gate.sv` | `tech_cells_generic` | SPI master phase inversion |
| `cluster_clock_gating` | 1 | `gf180_clk_gate.sv` | `tech_cells_xilinx` | same ICG cell, second naming family |
| `cluster_clock_inverter` | 1 | `gf180_clk_gate.sv` | `tech_cells_xilinx` | JTAG TAP negedge domain |
| `cv32e40p_clock_gate` | 1 | `gf180_clk_gate.sv` | `cv32e40p_clock_gate.sv` | same ICG cell, third naming family |
| `core_v_mcu_interleaved_ram` | 4 | `gf180_interleaved_ram.sv` | `fpga_interleaved_ram.sv` | one per `NB_L2_CHANNELS`, 4 × `sram512x8` per 32-bit word |
| `core_v_mcu_private_ram` | 2 | `gf180_private_ram.sv` | `fpga_private_ram.sv` | may be dropped entirely, see below |
| `a2_bootrom` | 1 | `gf180_bootrom.sv` | `a2_bootrom.sv` (sim only) | `$readmemh` does not synthesise |
| `apb_pll` | 1 | `gf180_clk_gen.sv` | `fpga_pll.sv` | no open GF180 PLL, bypass to the pad |

Two entries in this table are not what an earlier reading of upstream suggested.

`apb_pll` is the whole clock generator, not a PLL cell inside one. Upstream's ASIC build
takes `rtl/apb_fll_if/apb_pll.sv`, which wraps a `PLL18_TOP` hard macro, and its FPGA build
replaces the entire module through `fpga_pll.sv`. GF180MCU follows the FPGA route, so
`gf180_clk_gen.sv` provides `apb_pll` itself: the APB register file, the dividers and the
clock source. Note its five analog supply ports (`AVDD`, `AVDD2`, `AVSS`, `VDDC`, `VSSC`).
`soc_peripherals.sv` connects them to undeclared identifiers, so they are implicit wires
going nowhere and no analog supply reaches the SoC boundary today.

There are **no pad wrappers in this list**. `pad_functional_pd` and `pad_functional_pu` are
defined in `tech_cells_generic` and in upstream's Xilinx directory but never instantiated:
`core_v_mcu.sv` exposes `io_in_i` / `io_out_o` / `io_oe_o` as plain ports. Pads are entirely
a `chip_top` concern, so `gf180_pads.sv` belongs to `rtl/chip/`, not here.

Until a cell is written, `flow/synth/stubs.sv` carries an empty black box for it so the
hierarchy closes. Delete the stub as each real implementation lands.

## The eFPGA slot

`gf180_efpga_stub.sv` is the one file here that is not a technology cell. It provides
`efpga_subsystem` with upstream's exact port list and terminates every interface, which is
how the eFPGA is removed without patching a single upstream file: `soc_peripherals.sv` still
instantiates it, and the QuickLogic sources simply never enter the file list. They could not
be read anyway, since they sit inside `protect envelopes.

The APB slot at `0x1A30_0000` stays decoded and answers every access with zero, so software
that probes the FCB registers reads zeros rather than stalling. The APB-T1 TCDM port answers
through upstream's own `tcdm_error_slave`, which returns `0xBADACCE5` and is recognisable in
a trace. The four TCDM master ports into L2 never request, so the interconnect ports feeding
them should constant-fold away in synthesis. Whether they actually do is worth checking in
ticket 10's per-module breakdown.

## SRAM pin mapping

`gf180mcu_fd_ip_sram__sram512x8m8wm1` is 512 words × 8 bits, 431.86 × 484.88 µm. A 32-bit
word needs four of them side by side; anything deeper than 512 words needs depth decoding and
an output mux on top.

| Wrapper signal | SRAM pin | Notes |
| --- | --- | --- |
| `clk_i` | `CLK` | rising edge |
| `csn_i` | `CEN` | already active low, connect directly |
| `wen_i` | `GWEN` | global write enable, active low |
| `be_i[3:0]` | `WEN[7:0]` per macro | expand each byte enable across its macro's mask, active low |
| `addr_i` | `A[8:0]` | 512 words per macro, upper bits select the depth slice |
| `wdata_i[31:0]` | `D[7:0]` × 4 | split by byte lane |
| `rdata_o[31:0]` | `Q[7:0]` × 4 | concatenate byte lanes, then mux by depth slice |

The wrapper must present one-cycle read latency to match the TCDM handshake that
`l2_ram_multi_bank.sv` already implements. Verify against the behavioural `generic_memory`
model in `rtl/simulation/core_v_mcu_sim_ram.sv` before trusting it.

## Area budget

Foundry SRAM costs **0.409 mm² per KiB**. A `1x1` slot has 12.92 mm² of core area, and logic
plausibly takes 3 to 5 mm² of it.

| L2 size | Macros | Area | Share of core |
| --- | --- | --- | --- |
| 8 KiB | 16 | 3.35 mm² | 26% |
| 16 KiB | 32 | 6.70 mm² | 52% |
| 32 KiB | 64 | 13.4 mm² | does not fit |

Target 16 KiB. Upstream's 512 KiB interleaved plus 64 KiB private would need 241 mm², which
is why the private banks are the first thing to drop. Do not commit to a bank configuration
before a synthesis-only run has produced a real cell count.

## Conventions

Files here are intended for upstream, so match upstream's style: `snake_case` module names,
ports suffixed `_i` / `_o` / `_ni`, and this header on every file.

```systemverilog
// Copyright 2026 <author>
// Solderpad Hardware License, Version 2.1, see LICENSE.md for details.
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
```

Keep PDK cell instantiation confined to this directory. Reference macros by cell name only;
LEF, LIB and GDS come from `PDK_ROOT` and must never be committed.
