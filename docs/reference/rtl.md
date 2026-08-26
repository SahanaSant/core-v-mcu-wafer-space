# RTL reference

Two directories. `rtl/gf180mcu/` holds one implementation per technology-dependent cell,
mirroring upstream's `emulation/xilinx/rtl/`; upstream already separates portable RTL from
per-target implementations and selects between them with fusesoc filesets, so this is a third
sibling of `rtl-simulation` and `emulation-rtl`. Nothing there should contain design logic.
`rtl/chip/` is the pad ring and the SoC instantiation, covered in [pinout.md](pinout.md).

`make elaborate` reads the whole SoC and ends its report with one line per unresolved module.
That list is currently empty. Re-run it after any RTL change; it is the definitive statement
of what `rtl/gf180mcu/` still owes the design.

There are **no pad wrappers here, and never were**. `pad_functional_pd` and
`pad_functional_pu` are defined in `tech_cells_generic` and in upstream's Xilinx directory but
never instantiated: `core_v_mcu.sv` exposes `io_in_i` / `io_out_o` / `io_oe_o` as plain
ports. Pads are entirely a `chip_top` concern.

## Clock cells — `gf180_clk_gate.sv`

Six module names, three cells, 70 instances. Upstream declares the same three behaviours
under three naming families and expects the target to bind them.

| Module | Instances | Cell | Area (µm²) |
| --- | ---: | --- | ---: |
| `pulp_clock_gating` | 55 | `gf180mcu_fd_sc_mcu7t5v0__icgtp_1` | 61.4656 |
| `cluster_clock_gating` | 1 | the same | |
| `cv32e40p_clock_gate` | 1 | the same, `scan_cg_en_i` to `TE` | |
| `pulp_clock_inverter` | 4 | `gf180mcu_fd_sc_mcu7t5v0__clkinv_1` | 8.7808 |
| `cluster_clock_inverter` | 1 | the same | |
| `pulp_clock_mux2` | 8 | `gf180mcu_fd_sc_mcu7t5v0__mux2_1` | 28.5376 |

`icgtp` is a real integrated clock gate, `latch_posedge_precontrol` in its Liberty, latching
`E|TE` while `CLK` is low with `Q = CLK & IQ2`. That matches upstream's Xilinx model exactly,
and `TE` is a real pin marked `clock_gate_test_pin`, so the test enable reaches the cell
rather than being ORed into the enable in RTL. The negedge sibling `icgtn` is unused: every
gated domain here is posedge, and the negedge logic that exists inverts rather than gates.

**There is no glitch-free clock mux in GF180MCU and the design does not want one.** The only
clock-specific cells in the library are `clkbuf`, `clkinv`, `icgtp` and `icgtn`; `mux2` and
`mux4` are ordinary data muxes. Upstream's own generic and FPGA implementations of
`pulp_clock_mux2` are the plain ternary, and every live instance selects between phase
variants of one clock: CPHA and CPOL in the SPI master, TCK against inverted TCK in the JTAG
TAP, and a divided clock against its own source in the three uDMA clock generators. Nothing
selects between unrelated clocks, and break-before-make would stall the SPI clock
mid-transfer on a CPOL change rather than protect anything. It could not be built behind this
port list regardless: glitch-free muxing needs synchroniser flops, upstream's port list has
no reset, and adding one means patching every instantiation site. The remaining hazard
belongs to software, unchanged from upstream — `cfg_cpha_i`, `cfg_cpol_i` and the uDMA
`r_clockout_mux` are APB-writable at any time, so configure a peripheral before enabling it.

Drive strengths are all `_1`, the smallest offered. These cells sit at the root of a fanout
cone with no tree yet; CTS inserts the buffers and the resizer upsizes what it must, and
starting from the minimum is what lets it.

Cells are instantiated by name, never inferred. Yosys has no reliable path from a
latch-and-AND to an integrated clock gate, and a clock path left as ordinary logic is free to
be restructured into gates with unbalanced arrival. Naming them does bind this file to
`gf180mcu_fd_sc_mcu7t5v0`: **`make area SCL=<other>` no longer works**, because the cells will
not resolve. If a second library is ever needed, the fix is a per-library binding file rather
than a parameter, since Verilog cannot parameterise a module name.

## L2 memory — `gf180_l2_ram.sv`

Two module names, one implementation, six instances. Both banks are 4 KiB, so upstream's two
names bind to one 1024 × 32 body, the way the six clock-cell names bind to three cells.

| Module | Instances | Built from |
| --- | ---: | --- |
| `core_v_mcu_interleaved_ram` | 2 | 4 × `gf180mcu_ocd_ip_sram__sram1024x8m8wm1` |
| `core_v_mcu_private_ram` | 2 | the same |

Two interleaved channels rather than upstream's four (`NB_L2_CHANNELS` is 2). Sixteen macros
in total, 16 KiB, contiguous from `0x1C00_0000` with private bank 0 first, then private bank
1, then the interleaved region to `0x1C00_4000`.

The macro is 1024 words × 8 bits, 301.30 × 515.81 µm from its LEF. Four side by side make a
32-bit word, and 1024 words is the macro's whole depth, so there is **no depth decoding and
no output mux**: the wrapper is four macros and nothing else, and `ADDR_WIDTH` other than 10
is an elaboration error rather than a silent aliasing bug.

| Wrapper signal | SRAM pin | Notes |
| --- | --- | --- |
| `clk_i` | `CLK` | rising edge |
| `csn_i` | `CEN` | already active low, connect directly |
| `wen_i` | `GWEN` | already active low, connect directly |
| `be_i[k]` | `WEN[7:0]` on macro `k` | `{8{~be_i[k]}}`, so a masked lane sees all ones |
| `addr_i` | `A[9:0]` | word address, unmodified |
| `wdata_i[8k+:8]` | `D[7:0]` on macro `k` | one byte lane per macro |
| `rdata_o[8k+:8]` | `Q[7:0]` on macro `k` | one byte lane per macro |

The masking works without gating `CEN` because the macro's write condition is
`!CEN & !GWEN & !(&WEN)` and its read condition is `!CEN & GWEN`. A masked lane on a write
cycle therefore neither writes nor reads and holds `Q`, which is all the TCDM handshake
needs: it ignores read data on a write. Read latency is one cycle, matching the `r_valid`
register `l2_ram_multi_bank.sv` already had.

`rst_ni` reaches the wrapper and stops there. The macro has no reset and comes up undefined,
as it does on FPGA.

**Take macro area from LEF `SIZE`, never from Liberty.** Why, and what else in that library
is untrustworthy, is in [explanation/known-issues.md](../explanation/known-issues.md).

## Boot ROM — `gf180_bootrom.sv`

One module, `a2_bootrom`. This is a **generated file**: `sw/bootrom/gen_bootrom.py` compiles
`sw/bootrom/` with the container's `riscv64-unknown-elf-gcc` (there is no
`riscv32-corev-elf-gcc`; `-march=rv32imc -mabi=ilp32` targets the CV32E40P through it) and
converts the flat binary into a case statement — the same technique upstream's own
`a2_boot/srec2verilog.py` used for the original `a2_bootrom.sv`. `$readmemh` does not
synthesise, which is the only reason this file exists rather than a literal `initial` block.

Regenerate it with `make bootrom`, which also drives the RISC-V build and an Icarus
testbench (`sw/bootrom/tb/bootrom_tb.sv`) reading the generated module back against the
compiled image, word for word, over its registered CEN/A/Q interface.

**208 words, 832 bytes.** The generated module keeps `a2_bootrom`'s exact port list
(`ADDR_WIDTH=11`, `DATA_WIDTH=32`, matching `boot_rom.sv`'s fixed 8 KiB decode window) and
its exact registered read timing, since `boot_rom.sv` instantiates it unmodified. The reset
vector (`apb_soc_ctrl.sv`'s `r_bootaddr`, `0x1A00_0080`) lands on word 32 of the case
statement, matching upstream's own 32-entry trap-vector table before the reset handler.

The L2 destination is `0x1C00_0000`. The ROM's boot-time stack is fixed at the *top* of the
region, 512 bytes (`sw/bootrom/include/boot_image.h`'s `BOOT_STACK_RESERVE_BYTES`), covering
both the ROM's `.bss` (`spi.c`'s 64-byte command buffer) and its stack. The application gets
the remaining 15,872 bytes, `0x1C00_0000`–`0x1C00_3E00`.

One real fix along the way: `udma_qspim_open`'s clock-divisor formula, carried over from
`a2_boot/spi.c`, assumed a fixed 5 MHz peripheral clock, which was that board's FLL-derived
`udma_ctrl` clock. It is now derived from this design's real `ref_clk_i` instead
(`udma_clk_div_cnt.sv`'s `spi_clk = periph_clk / (2*N)`).

## Clock generator — `gf180_clk_gen.sv`

One module, `apb_pll`, and it is the whole clock generator rather than a PLL cell inside one.
Upstream's ASIC build takes `rtl/apb_fll_if/apb_pll.sv`, which wraps a `PLL18_TOP` hard
macro, and its FPGA build replaces the entire module through `fpga_pll.sv`. GF180MCU follows
the FPGA route: `soc_clk_o`, `periph_clk_o` and `cluster_clk_o` are `ref_clk_i` wired straight
through, no divider and no mux, which makes `ref_clk_i` the real SoC clock rather than a
stand-in for one hidden behind a black box. `ref_clk_o`'s divide-by-40 stays structurally
real, one `clkdv` instance feeding `low_speed_clk_i` on SPI and RTC-adjacent logic
downstream.

The eight-register APB file (`CTL`/`DIV`/`FRAC`/`SS1`/`SS2`/`SOC`/`PERIPH`/`CLUSTER`) stays
readable and writable at `fpga_pll.sv`'s offsets, matching its precedent exactly: software
that pokes FLL registers does not fault or hang, but nothing the registers hold drives an
output. The `PD`/`PDDP`/`MODE`/`DM`/`BYPASS` decode that fed the hard PLL is gone with it,
since there is no hardware left for those fields to configure. `LOCK` (bit 31 of `CTL`) reads
back tied to 1, so anything polling "PLL locked" never blocks.

The five analog PLL supply ports (`AVDD`, `AVDD2`, `AVSS`, `VDDC`, `VSSC`) are gone entirely.
Nothing analog is instantiated, so there is no supply to thread to the SoC boundary;
`soc_peripherals.sv`'s instantiation drops the connections to match, which were implicit
wires going nowhere in the first place.

### Reset

`safe_domain.sv`'s reset synchronisation did not exist in upstream's ASIC path: `rst_no` was
`assign rst_no = rst_ni`, a bare wire with no clock input, sitting above an `rstgen` instance
upstream had commented out. That output (`s_rstn_por` in `core_v_mcu.sv`) fans out as
`rstn_glob_i` into several async resets inside `soc_domain`, so an unsynchronised pad-level
deassert reached those flops with no recovery-time guarantee.

This port reinstates upstream's own dead code for real. `safe_domain.sv` gained a `ref_clk_i`
port, wired from `core_v_mcu.sv`'s own top-level port (the same clock `apb_pll` bypasses), and
`rst_no` now comes from an `rstgen` instance (already vendored at
`rtl/vendor/pulp_platform_common_cells/src/rstgen.sv`, async assert / sync deassert) clocked
by it. One instance covers both the main clock domain and the `/40` slow domain downstream,
since a glitch-free deassertion on the fast clock stays glitch-free on the slow one.

No test-mode bypass exists at this level, matching `core_v_mcu.sv`'s own `dft_test_mode_i`
tied to `'0`. No on-die debounce or power-on reset either, since `gf180mcu_fd_io`'s
support-cell list has no POR or brownout cell and an external supervisor is assumed.

## The eFPGA slot — `gf180_efpga_stub.sv`

The one file in `rtl/gf180mcu/` that is not a technology cell. It provides `efpga_subsystem`
with upstream's exact port list and terminates every interface, which is how the eFPGA is
removed without patching a single upstream file: `soc_peripherals.sv` still instantiates it,
and the QuickLogic sources simply never enter the file list. They could not be read anyway,
since they sit inside `` `protect `` envelopes.

The APB slot at `0x1A30_0000` stays decoded and answers every access with zero, so software
probing the FCB registers reads zeros rather than stalling. The APB-T1 TCDM port answers
through upstream's own `tcdm_error_slave`, which returns `0xBADACCE5` and is recognisable in
a trace. The four TCDM master ports into L2 never request, which is what lets flattened
synthesis constant-fold the interconnect ports feeding them away entirely.

## Conventions

Files in `rtl/gf180mcu/` are intended for upstream, so match upstream's style: `snake_case`
module names, ports suffixed `_i` / `_o` / `_ni`, and this header on every file.

```systemverilog
// Copyright 2026 <author>
// Solderpad Hardware License, Version 2.1, see LICENSE.md for details.
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
```

Keep PDK cell instantiation confined to this directory. Reference macros by cell name only;
LEF, LIB and GDS come from `PDK_ROOT` and must never be committed.
