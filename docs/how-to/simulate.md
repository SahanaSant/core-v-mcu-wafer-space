# Simulate the design

Two levels, both driven by cocotb from the repository root:

```sh
make sim      # RTL, Verilator, a few minutes
make sim-gl   # gate level against the hardened netlist, Icarus, roughly 12x slower
```

Both build the software they need first, so there is no separate step to remember.

## What each level is for

Upstream's own functional verification stays in the submodule; run it there with its
existing Verilator and Questa targets (`make model-lib`, `make lint`, `make buildsim sim`).
There is no reason to duplicate it here.

This directory covers what upstream cannot see:

- **RTL simulation** of `chip_top`, confirming the pad ring, pad multiplexer and reduced
  memory map behave once upstream is instantiated with GF180 configuration.
- **Gate-level simulation** of the hardened netlist. This is the only practical check that
  the SRAM wrappers, clock gates and pad cells survived synthesis and place-and-route. Run
  it before every submission.

`make sim-gl` needs `flow/final/pnl/chip_top.pnl.v`, so run `make harden` first.

## What a passing run proves

`sim/tb/tb_top.sv` instantiates `chip_top` with behavioural pad models, hangs upstream's
`GD25Q128B` QSPI flash model off the SPI pads, and decodes UART0 with `uart_rx.sv`. The
cocotb test in `sim/cocotb/tb_top_tb.py` drives reset and the reference clock and waits for
two strings out of the UART.

`sw/app/` produces those strings: a small RV32IMC program that walks every L2 bank
read-write-read with individual byte enables, then prints over UART0.
`sw/app/gen_flash_image.py` wraps it in the `boot_header_t` (size, CRC-32) the boot ROM
expects and writes both a raw image and a `$readmemh` file for the flash model.

So a passing run exercises the whole chain: reset release, clock reaching the core, the boot
ROM fetching from its own ROM, the uDMA/QSPI path pulling the image off flash, the CRC
matching, the jump into L2, the SRAM walk, and one peripheral talking to a pad. It prints
`BOOT OK` and `SRAM PASS` at about 28 ms of simulated time.

## Things the harness has to do that are not obvious

**Reset needs a real falling edge** on the internal synchronised reset, not a level held low
from time zero. `udma_ctrl` gates the uDMA core clock off until software enables a
peripheral, so those flops see no clock during reset and depend entirely on that edge; and
`rstgen_bypass` in `safe_domain` is four flops deep, so its output can only fall after it has
first risen. The harness holds `rst_n_PAD` high for twelve clocks before pulsing it low.

**The PDK SRAM model is replaced** by `sim/tb/gf180mcu_ocd_ip_sram_behav.sv` at both RTL and
gate level. The vendor model commits in `always @(posedge clk_dly)` with `clk_dly` 100 ps
behind `CLK`, sampling its own control inputs at that later moment. Without clock-to-Q delay
every input has already moved on, so it silently discards every access and the memory reads
back as zeros forever. A gate-level run without SDF has the same problem, which is why the
substitution is unconditional.

**Gate-level runs set `GL_SIM`**, because synthesis flattens hierarchy and any probe reaching
into the design has to be guarded or rewritten as an escaped flat identifier.

**Gate level uses Icarus, RTL uses Verilator.** The PDK's `icgtp` clock-gate model is built
on a Verilog user-defined primitive and carries a specify block, and Verilator implements
neither.

## Waveforms

Written as FST. Open them with GTKWave or Surfer inside the container (`make shell`).

Waveform dumping is expensive here: gate-level simulation runs at about 23.4 µs of simulated
time per real second with dumping off, and 5 to 6 µs with it on.

## Building the software on its own

Both images are built by the simulation targets, but you can drive them directly:

```sh
make bootrom   # sw/bootrom -> rtl/gf180mcu/gf180_bootrom.sv, plus an Icarus equivalence check
./run.sh sh /foss/designs/flow/synth/app.sh   # sw/app -> the flash image
```

`make bootrom` is the one to re-run after any change to `sw/bootrom/`: `gf180_bootrom.sv` is
a generated file, and the RTL is stale until it is regenerated.

Both builds regenerate the `core-v-mcu/sw/inc` headers from `gf180-pin-table.csv` and
`perdef.json` first, so the software's view of the peripherals cannot drift from the RTL's.

## Changing the clock frequency

Four constants track `flow/config.yaml`'s `CLOCK_PERIOD` and must move with it:

- `sw/bootrom/spi.c`'s `PERIPH_CLK_HZ`
- `sw/app/uart.c`'s `PERIPH_CLK_HZ`
- `sim/cocotb/tb_top_tb.py`'s `CLK_HZ`
- `sim/tb/tb_top.sv`'s `CLKS_PER_BIT`, the integer `PERIPH_CLK_HZ / 115200` the UART divider
  lands on (43 at 5 MHz)
