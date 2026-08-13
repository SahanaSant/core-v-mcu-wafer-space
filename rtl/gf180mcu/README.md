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
| `core_v_mcu_interleaved_ram` | 4 | `gf180_interleaved_ram.sv` | `fpga_interleaved_ram.sv` | one per `NB_L2_CHANNELS`, 4 × `sram512x8` per 32-bit word |
| `core_v_mcu_private_ram` | 2 | `gf180_private_ram.sv` | `fpga_private_ram.sv` | may be dropped entirely, see below |
| `a2_bootrom` | 1 | `gf180_bootrom.sv` | `a2_bootrom.sv` (sim only) | `$readmemh` does not synthesise |
| `apb_pll` | 1 | `gf180_clk_gen.sv` | `fpga_pll.sv` | no open GF180 PLL, bypass to the pad |

The six clock cells left this table in ticket 16 and are now in `gf180_clk_gate.sv`;
see [Clock cells](#clock-cells) below.

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

## Clock cells

Six module names, three cells, 70 instances, all in `gf180_clk_gate.sv`. Upstream declares
the same three behaviours under three naming families and expects the target to bind them.

| Module | Instances | Cell | Area (um2) |
| --- | ---: | --- | ---: |
| `pulp_clock_gating` | 55 | `gf180mcu_fd_sc_mcu7t5v0__icgtp_1` | 61.4656 |
| `cluster_clock_gating` | 1 | the same | |
| `cv32e40p_clock_gate` | 1 | the same, `scan_cg_en_i` to `TE` | |
| `pulp_clock_inverter` | 4 | `gf180mcu_fd_sc_mcu7t5v0__clkinv_1` | 8.7808 |
| `cluster_clock_inverter` | 1 | the same | |
| `pulp_clock_mux2` | 8 | `gf180mcu_fd_sc_mcu7t5v0__mux2_1` | 28.5376 |

`icgtp` is a real integrated clock gate, `latch_posedge_precontrol` in its liberty, latching
`E|TE` while `CLK` is low with `Q = CLK & IQ2`. That is upstream's Xilinx model exactly, and
`TE` is a real pin marked `clock_gate_test_pin`, so the test enable reaches the cell rather
than being ORed into the enable in RTL. The negedge sibling `icgtn` exists and is unused:
every gated domain here is posedge, and the negedge logic that does exist inverts rather than
gates.

**There is no glitch-free clock mux in GF180MCU and the design does not want one.** The only
clock-specific cells in the library are `clkbuf`, `clkinv`, `icgtp` and `icgtn`; `mux2` and
`mux4` are ordinary data muxes. Upstream's own generic and FPGA implementations of
`pulp_clock_mux2` are the plain ternary, and every live instance selects between phase
variants of one clock: CPHA and CPOL in the SPI master, TCK against inverted TCK in the JTAG
TAP, and a divided clock against its own source in the three uDMA clock generators. Nothing
here selects between unrelated clocks, and break-before-make would stall the SPI clock
mid-transfer on a CPOL change rather than protect anything. It could not be built behind this
port list regardless: glitch-free muxing needs synchroniser flops, upstream's port list has no
reset, and adding one means patching every instantiation site. The remaining hazard belongs to
software, unchanged from upstream: `cfg_cpha_i`, `cfg_cpol_i` and the uDMA `r_clockout_mux`
are APB-writable at any time, so configure a peripheral before enabling it.

`clkinv` rather than `inv` is intent at no cost: identical area at `_1`, and it is the
library's clock inverter. Nothing more should be read into it, since ABC already picks
`clkinv_1` as its general-purpose inverter, 9,974 of them in the flattened netlist.

Drive strengths are all `_1`, the smallest offered. These cells sit at the root of a fanout
cone with no tree yet; CTS inserts the buffers and the resizer upsizes what it must, and
starting from the minimum is what lets it.

The cells cost 3,776 um², which the hierarchical pass of `make area` reports exactly:
4,723,425 um² against ticket 14's 4,719,649 on an identical cell count. Three of the 57 clock
gates have no load once flattened and drop out, so the flat netlist carries 54 (`ep_pf_evt_i`
and the uDMA `genblk1[7]` and `[8]` per-channel gates, whose `periph_per_clk_o` reaches no
flop; flop counts are unchanged, so nothing lost a clock). **The flattened total is not stable
to better than roughly 0.3% under a structural change of this size**, so read small deltas in
`flow/build/area/area.md` with care: it came out 8,741 um² *lower* here, almost all of it ABC
remapping rather than anything the clock cells did.

Cells are instantiated by name, never inferred. Yosys has no reliable path from a
latch-and-AND to an integrated clock gate, and a clock path left as ordinary logic is free to
be restructured into gates with unbalanced arrival. The names carry the library
`gf180mcu_fd_sc_mcu7t5v0`, which is a library and not a variant, so nothing here asserts C
against D. It does bind the file to that one library: **`make area SCL=<other>` no longer
works**, because the cells will not resolve. `gf180mcu_as_sc_mcu7t3v3` is dead on
measurement (ticket 15), so nothing needs that override today; if something ever does, the
fix is a per-library binding file rather than a parameter, since Verilog cannot parameterise
a module name.

`flow/synth/filelist.sh` reads the liberty with `read_liberty -lib` before the RTL, which is
what makes the instantiation legal: yosys-slang imports an instance as a black box only when
an earlier yosys command loaded the module. Cell area then comes from the liberty rather than
being silently zero, and no path into `pdk/` appears in the RTL.

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

A `1x1` slot has 12.92 mm² of core area. **Logic takes about 9.75 mm² of it**, measured with
`make area`: 3.42 mm² of standard cells placed at `PL_TARGET_DENSITY_PCT: 35`. That leaves
**3.16 to 3.18 mm²**, and it is the number every memory decision has to fit inside.

The range is not hedging. Ticket 10 measured 3.417 mm² and ticket 16 measured 3.408 after
adding 3,776 um² of clock cells, because removing 70 hierarchy boundaries made ABC remap the
whole design. Read the flattened total as good to roughly 0.3% and no better, and do not treat
a 0.02 mm² move in the remainder as a real saving.

| L2 size | Foundry `sram512x8` | Share of what is left | OCD `sram1024x8` | Share |
| --- | --- | --- | --- | --- |
| 4 KiB | 1.68 mm² | 53% | 0.62 mm² | 20% |
| 8 KiB | 3.35 mm² | 106%, does not fit | 1.24 mm² | 39% |
| 16 KiB | 6.70 mm² | does not fit | 2.48 mm² | 78% |
| 32 KiB | 13.4 mm² | does not fit | 4.96 mm² | does not fit |

Foundry SRAM costs 0.409 mm² per KiB and the `gf180mcu_ocd_ip_sram` macro 0.155, from
ticket 07. The consequence is blunt: **the 16 KiB target is unreachable with the foundry
macro** without cutting logic first, and reachable with the OCD macro only because it is 2.6x
denser. Upstream's 512 KiB interleaved plus 64 KiB private would need 241 mm², which is why
the private banks are the first thing to drop.

Re-run `make area` after any change that adds or removes RTL. The budget above is a
measurement with a date on it, not an invariant.

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
