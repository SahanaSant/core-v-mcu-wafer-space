# Clock and reset architecture without a PLL

Type: grilling
Status: resolved
Blocked by: 22

## Question

There is no open GF180 PLL, so upstream's clock generation has to be replaced with something
that exists.

What drives the SoC clock? The obvious answer is bypassing `ref_clk_i` straight from the pad,
which is what `fpga_pll.sv` effectively does in bypass mode and requires an external
oscillator on the board. A ring oscillator is the alternative if a self-clocked die matters,
at the cost of a frequency that varies with process, voltage and temperature.

What happens to `apb_fll_if/apb_pll.sv`? The `not_emulation-rtl` fileset pulls it in, so the
GF180 target either replaces it with a stub that keeps the APB registers readable, or drops
it and removes its slot from the memory map. Software that pokes FLL registers should not
hang.

What frequency do we target? `flow/README.md` carries `CLOCK_PERIOD: 40` for 25 MHz, on the
grounds that standard-cell delay and open-tool timing closure are the limit, not the memory
(the SRAM macro runs at 164 MHz typical at 5.0 V). Confirm or revise, and note that ticket 10
will produce the first evidence either way.

What is the reset scheme? Async assert with synchronous deassert is the default answer, but
decide whether `rstn_i` needs debouncing or a power-on reset, and how reset is distributed
across the clock domains upstream already has.

**What ticket 03 changed here.** The FLL block is not a separate decision from the clock
source: the module to replace is `apb_pll` itself, and it is the *whole* clock generator.
Upstream's ASIC version (`rtl/apb_fll_if/apb_pll.sv`) is an APB register file, three
dividers, three clock muxes and a `PLL18_TOP` hard macro; its FPGA version replaces the
entire module through `fpga_pll.sv` rather than swapping the macro inside it. GF180MCU takes
the FPGA route, so `gf180_clk_gen.sv` provides `apb_pll` and decides in one place what the
registers do, what divides what, and where the clock comes from. Keeping the APB registers
readable is therefore free; dropping the slot is the option that costs work.

Also from ticket 03: `apb_pll` carries five analog supply ports (`AVDD`, `AVDD2`, `AVSS`,
`VDDC`, `VSSC`) for the hard PLL, and `soc_peripherals.sv` connects them to identifiers that
are declared nowhere. They are implicit wires going nowhere, so **no analog supply reaches
the SoC boundary today**. If the answer here needs an analog supply, that is new hierarchy
to thread, not a connection to make; if it does not, the ports should come off the module.

**What ticket 19 changed here, and why this was blocked.** The target frequency could not be
chosen against `make sta`'s old headline: it reported the path with the worst pre-layout
slack, not the deepest one, and moved identity under unrelated churn.

**Ticket 22 resolved this, and the number is bad news, not a green light.** Fixed metric,
re-measured on the current (post-ticket-06) netlist: **89 stages, a 62.3 ns floor, 125% of the
50 ns / 20 MHz budget at 3.3 V.** The 5.0 V logic-only arm has real margin (88%), but the
supply is 3.3 V, settled by ticket 14. Re-mapping at a tighter `abc -D` target changed nothing
(byte-identical netlist), so this is not slack synthesis left on the table. The floor already
assumes zero wire RC and a zero-skew clock, so real numbers only get worse from here until a
first full harden exists to measure against. Ticket 22's Answer has the full case and the
options it leaves open: a slower clock (the floor implies a defensible target somewhere below
16 MHz, at 3.3 V), unproven retiming, or pipelining the CV32E40P decoder path, which is new
microarchitecture off this map. This ticket should settle the clock number against that
finding, not against 20 MHz.

## Definition of done

A named clock source with its pad allocation, a decision on the FLL block, a target frequency
with a stated basis, and a reset scheme. Enough that `gf180_clk_gen.sv` can be written
without further discussion.

## Answer

**Clock source: external `ref_clk_i` bypass, undivided.** No PLL and no calibrated on-die
oscillator; the SoC clock is whatever is wired to `ref_clk_i` off-chip. The pad costs nothing new:
`rtl/chip/README.md` already has `ref_clk_i` as a dedicated port outside the 40-pin general IO
array, unchanged from upstream. A self-contained (self-clocked) demo was investigated and
rejected for this shuttle: `docs/porting-analysis.md` points at Mabrains' `gf180mcu_riscv_soc`
project, which does have `Ring-Osc-3.3vFETs`/`Ring-Osc-5.0vFETs` IP, DRC/LVS/PEX-clean, Apache
2.0 — but its `lef/` has no standalone ring-oscillator macro, only a fused `analog_wrapper.lef`
bundling the oscillator with an LDO, bandgap reference and opamps for Mabrains' own
Caravel-GFMPW1 chip, and nothing found confirms that macro is `gf180mcuD` rather than `C`. Reusing
it means re-extracting and re-verifying an analog macro, unscoped effort in the same category as
the "no open GF180 PLL" problem this ticket opened with, not a drop-in. OpenFASoC was not checked.
Left in the fog as a stretch item, not blocking December.

**FLL/`apb_pll` register slot: inert stub, matching upstream's own FPGA-emulation precedent.**
`emulation/xilinx/rtl/fpga_pll.sv` already ships a fully readable/writable APB register file
(`ControlReg`, `DivisorReg`, `FracReg`, `Spread1Reg`, `Spread2Reg`, `SocDiv`, `PeriphDiv`,
`ClusterDiv`) whose values drive nothing: `soc_clk_o`/`periph_clk_o`/`cluster_clk_o` come from a
Xilinx clock IP wired independently of every register. `gf180_clk_gen.sv` repeats that shape for
real: same register offsets stay live so software polling them doesn't fault or hang, but
`soc_clk_o`, `periph_clk_o` and `cluster_clk_o` wire straight from `ref_clk_i` regardless of
register contents. The one register-adjacent behaviour that is structurally real, `ref_clk_o`'s
divide-by-40 (feeding `low_speed_clk_i` on SPI/RTC-adjacent logic downstream), is kept via the
existing `clkdv` module reused as-is from `fpga_pll.sv`, so anything tuned to that ratio needs no
redesign. The five analog PLL supply ports (`AVDD`, `AVDD2`, `AVSS`, `VDDC`, `VSSC`) come off the
module entirely — nothing analog is instantiated, so no new supply hierarchy threads to the SoC
boundary.

**Target frequency: 10 MHz (100 ns period).** Basis: ticket 22 measured a 62.3 ns pre-layout
floor (89 stages) at 3.3 V, an idealized ceiling of about 16.05 MHz assuming zero wire RC and a
zero-skew clock tree, neither of which exist without a floorplan. 100 ns gives roughly 60% margin
over that floor to absorb CTS and wire-RC degradation ticket 22 could not measure, and 10 MHz is
also a standard, cheap off-the-shelf crystal/oscillator frequency, which now matters concretely
since external bypass means a human wires a real part to the board. Since the clock is externally
supplied, this is a synthesis/CTS target and a board bring-up default, not a value burned into
silicon: the oscillator can be swapped for a slower one with no respin if a first full harden
doesn't close at 10 MHz.

**Reset scheme: async assert, sync deassert.** The RTL today has no synchronization at all —
`safe_domain.sv` is `assign rst_no = rst_ni`, a bare wire. Upstream's own intended design is
sitting there commented out: an `rstgen` instance (async-assert/sync-deassert) clocked by the
reference clock. `rstgen`/`rstgen_bypass` already exist, unmodified, in the vendored
`pulp_platform_common_cells` tree with no PDK dependency, so this is reinstating upstream's
commented-out intent for real rather than new design. `safe_domain.sv` needs a clock input added
(it has none today); one `rstgen` instance on the main 10 MHz domain covers the whole SoC,
including the `/40` slow domain, since a glitch-free deassertion on the fast clock stays
glitch-free for the slow one too. No on-die debounce and no on-die power-on-reset: debounce is a
raw-switch concern that doesn't apply when an external supervisor or RC circuit drives `rstn_i`
(the normal pairing with external clock bypass), and `gf180mcu_fd_io`'s support-cell list
(`06_Support_Cell.csv`) has no POR/brownout cell, so building one would be new analog IP in the
same category as the PLL problem above.

Follow-on: writing `gf180_clk_gen.sv` itself, reinstating `safe_domain.sv`'s reset logic, and
moving the flow's `CLOCK_PERIOD` off its 50 ns placeholder to the 100 ns target is new work, not
a further decision — spun off as ticket 24, the same shape as ticket 04 spinning off ticket 23 for
the boot ROM.
