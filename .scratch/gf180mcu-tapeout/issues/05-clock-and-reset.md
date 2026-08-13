# Clock and reset architecture without a PLL

Type: grilling
Status: open
Blocked by: none

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

## Definition of done

A named clock source with its pad allocation, a decision on the FLL block, a target frequency
with a stated basis, and a reset scheme. Enough that `gf180_clk_gen.sv` can be written
without further discussion.

## Answer

<!-- filled on resolution -->
