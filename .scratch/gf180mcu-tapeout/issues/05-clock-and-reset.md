# Clock and reset architecture without a PLL

Type: grilling
Status: open
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

<!-- filled on resolution -->
