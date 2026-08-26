# Why the design is shaped this way

The CORE-V MCU cannot be ported to GF180MCU as-is. Everything below follows from that, and
each decision here is the answer to a question that had to be settled before anything could
be built. The original research that raised most of them is in
[porting-analysis.md](porting-analysis.md); this page is what was actually decided, and why.

## The memory had to shrink by a factor of thirty

This is the finding that dictates the whole project.

Upstream carries 512 KiB of interleaved L2 SRAM plus 64 KiB of private banks. The largest
SRAM macro in the open GF180MCU PDK holds 512 bytes and occupies 0.209 mm². Reproducing
576 KiB would take roughly 236 mm² of silicon against 12.90 mm² of core area on wafer.space's
largest slot.

So: **16 KiB**, as two interleaved channels of 4 KiB plus two private banks of 4 KiB.
`NB_L2_CHANNELS` drops from 4 to 2, which also removes two crossbar ports, and `L2_BANK_SIZE`
drops from 29184 to 1024, which narrows the uDMA address registers from 15 bits to 10.

The macro is **wafer.space's `gf180mcu_ocd_ip_sram` 1024 × 8**, not the foundry's 512 × 8. It
is denser, and 1024 words is exactly what a 4 KiB bank needs from four macros side by side,
so the wrapper has no depth decoding and no output mux at all. Its Liberty is not
trustworthy; see [known-issues.md](known-issues.md).

## Three subsystems had to go

**The eFPGA.** The QuickLogic ArcticPro-2 fabric is a proprietary hard macro with no GF180
implementation, and its sources sit inside `` `protect `` envelopes that no open front end
reads. It is replaced by `gf180_efpga_stub.sv`, which provides `efpga_subsystem` with
upstream's exact port list and terminates every interface. Nothing upstream is patched:
`soc_peripherals.sv` still instantiates it, and the QuickLogic sources simply never enter the
file list.

**The FLL.** `rtl/generic_FLL/` and `rtl/apb_fll_if/apb_pll.sv` model an analog
frequency-locked loop, and there is no open GF180 equivalent. The design takes an **external
reference clock, bypassed undivided**, with no PLL and no on-die oscillator. That makes
`ref_clk_i` the real SoC clock rather than a stand-in for one hidden behind a black box, and
it makes the operating frequency a crystal choice on the bring-up board rather than something
burned into silicon. The APB register file stays, readable and writable, so software that
pokes FLL registers does not fault — but nothing those registers hold drives an output.

**The boot ROM.** Upstream's `a2_bootrom.sv` is a 2048-word array initialised with
`$readmemh`, which does not synthesise. It is replaced by a generated case statement over the
compiled `sw/bootrom/` image: 208 words, 832 bytes.

## Boot is SPI flash, CRC-checked, with no fallback

Copy-then-jump: the ROM reads the image over QSPI into L2 at `0x1C00_0000`, verifies a CRC32
over it, and jumps. A mismatch calls `halt()`, so reaching the application at all is the CRC
passing.

There is no bootsel-driven ROM fallback and no I2C boot path — upstream's dual path exists to
serve a board this design is not. `bootsel_i` is removed from the top level entirely. JTAG is
the only recovery path on a boot failure, which is why the TAP's clock domain is declared in
the SDC despite the cost of building a second clock tree.

## The core runs at 3.3 V on a 5 V-oxide library

`gf180mcu_fd_sc_mcu7t5v0`'s `5v0` is the **oxide, not the supply**. The library ships fifteen
Liberty corners spanning 5.0 V, 3.3 V and 1.8 V, and all 229 cells are present at every one
of them with identical geometry — `nand2_1` is 10.976 µm² at `ss_125C_3v00` exactly as at
`ss_125C_4v50`. So the supply choice costs no area and no library change.

3.3 V rather than 5.0 V because **`gf180mcu_ocd_ip_sram` has no `ss_125C_4v50` corner at
all**. Running the core at 5 V would have removed the denser SRAM macro permanently, and the
memory is the binding constraint on this design. What 3.3 V costs is logic speed, and
`make sta` keeps a 5.0 V informational arm precisely so that cost stays visible.

## The IO ring runs at 5.0 V over the 3.3 V core

Two voltage domains, with the level shifter inside each `gf180mcu_ocd_io` pad cell. The
foundry `gf180mcu_fd_io` cannot do this at all: it has no core-supply pad cell and shorts the
two domains on purpose. `gf180mcu_ocd_io__vdd` and `__vss` bond the core rail with DVDD and
DVSS explicitly unconnected, which is the whole reason the ring can be split.

## Peripherals were cut to fit, and only some cuts save silicon

`apb_i2cs`, the uDMA filter and the uDMA camera are cut. GPIO drops from 32 to 16, UART from
2 instances to 1, I2C masters from 2 to 1. Together those took flattened area down 25.9% and
core occupancy from 95.6% to 76.4%.

The distinction worth keeping: `apb_adv_timer`, `udma_spim_top` and `udma_sdio_top` are
fixed-shape upstream IP with no channel-count parameter, so bonding fewer of their pins is
free but saves nothing. `N_UART` is a real generate-loop instance count, so cutting it is a
real saving. Do not assume a pad-count reduction is an area reduction.

## Synthesis flattens

Worth 1.30 mm² of cell area, which is not a preference. Flattened, constant propagation
removes the stubbed eFPGA's four TCDM master ports completely; with module boundaries kept,
nothing propagates across them and the three crossbars arbitrate between nine masters instead
of five. See [reference/flow.md](../reference/flow.md).

## The front end is yosys-slang

Upstream's RTL is heavy SystemVerilog: interfaces, packages, packed structs, parameterised
generate blocks across more than fifty files. Yosys alone will not read it. The PULP chain
(Bender, Morty, SVase, sv2v) would, but the `read_slang` plugin shipped with Yosys in the
pinned container reads the whole SoC and elaborates it in about three seconds, and Morty and
SVase are not in the container anyway.

The consequence worth stating: **no upstream source file needs patching to read this design**,
which is what makes the technology cells contributable back.

## The clock target is 5 MHz

Reached by measurement, not by choice. [timing.md](timing.md) has the whole story.

## What "done" means

A design is done when it passes
[gf180mcu-precheck](https://github.com/wafer-space/gf180mcu-precheck), not when LibreLane
finishes. LibreLane completing every step tells you the tools did not error; the precheck
tells you the layout is submittable. Run `make precheck` before every submission attempt.
