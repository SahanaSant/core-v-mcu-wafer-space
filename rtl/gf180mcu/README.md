# GF180MCU technology cells

One implementation per technology-dependent cell, mirroring upstream's
`emulation/xilinx/rtl/`. Upstream already separates portable RTL from per-target
implementations and selects between them with fusesoc filesets, so this directory is a third
sibling of `rtl-simulation` and `emulation-rtl`. Nothing here should contain design logic.

## What has to be provided

| Upstream Xilinx file | File here | Module to provide | Notes |
| --- | --- | --- | --- |
| `fpga_interleaved_ram.sv` | `gf180_interleaved_ram.sv` | `core_v_mcu_interleaved_ram` | 4 × `sram512x8` per 32-bit word |
| `fpga_private_ram.sv` | `gf180_private_ram.sv` | `core_v_mcu_private_ram` | may be dropped entirely, see below |
| `fpga_pll.sv` | `gf180_clk_gen.sv` | clock source | no open GF180 PLL, bypass to the pad |
| `pulp_clock_gating_xilinx.sv` | `gf180_clk_gate.sv` | `pulp_clock_gating` | bind to `gf180mcu_fd_sc_mcu7t5v0__icgtp_*` |
| `cv32e40p_clock_gate.sv` | `gf180_clk_gate.sv` | `cv32e40p_clock_gate` | same ICG cell |
| `pad_functional_xilinx.sv` | `gf180_pads.sv` | pad wrappers | wrap `gf180mcu_fd_io` cells |
| `a2_bootrom.sv` (sim only) | `gf180_bootrom.sv` | `a2_bootrom` | `$readmemh` does not synthesise |

Treat this table as the starting point, not the final list. The definitive set is whatever
the first elaboration run reports as missing once the eFPGA is removed. Add rows as they
surface rather than guessing ahead.

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
