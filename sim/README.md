# Simulation

cocotb testbenches driving `chip_top`, run with `make sim` (RTL) and `make sim-gl`
(gate level) from the repository root.

RTL runs use Verilator with `--timing`; gate level uses Icarus, which is roughly twelve
times slower on this design. The harness was seeded from `cocotb/` in the
[wafer.space project template](https://github.com/wafer-space/gf180mcu-project-template).

## What each level is for

Upstream's own verification stays where it is. Run it in the submodule with its existing
Verilator and Questa targets (`make model-lib`, `make lint`, `make buildsim sim`); there is
no reason to duplicate functional regression here.

This directory covers what upstream cannot see:

- **RTL simulation** of `chip_top`, confirming the pad ring, pad multiplexer and reduced
  memory map behave once upstream is instantiated with GF180 configuration.
- **Gate-level simulation** of the hardened netlist. This is the only practical check that
  the SRAM wrappers, clock gates and pad cells survived synthesis and place-and-route. Run it
  before every submission.

## What the harness does (ticket 31)

`tb_top.sv` instantiates `chip_top` with behavioural pad models, hangs upstream's
`GD25Q128B` QSPI flash model off the SPI pads, and decodes UART0 with `uart_rx.sv`. The
cocotb test in `cocotb/tb_top_tb.py` drives reset and the reference clock and waits for two
strings out of the UART.

`sw/app/` is what produces those strings. It is a small RV32IMC program that walks every L2
bank read-write-read with individual byte enables, then prints over UART; `sw/app/gen_flash_image.py` wraps it in the `boot_header_t` (size, CRC-32) the boot ROM expects and
writes both a raw image and a `$readmemh` file for the flash model. So a passing run
exercises the whole chain: reset release, clock reaching the core, the boot ROM fetching from
its own ROM, the uDMA/QSPI path pulling the image off flash, the CRC matching, the jump into
L2, the SRAM walk, and one peripheral talking to a pad.

Reset needs a real falling edge on the internal synchronized reset, not a level held low from
time zero. `udma_ctrl` gates the uDMA core clock off until software enables a peripheral, so
those flops see no clock during reset and depend entirely on that edge; `rstgen_bypass` in
`safe_domain` is four flops deep, so its output can only fall after it has first risen. The
harness therefore holds `rst_n_PAD` high for twelve clocks before pulsing it low.

The PDK SRAM model is replaced by `tb/gf180mcu_ocd_ip_sram_behav.sv` at both RTL and gate
level. The vendor model commits in `always @(posedge clk_dly)` with `clk_dly` 100 ps behind
`CLK`, sampling its own control inputs at that later moment; without clock-to-Q delay every
input has already moved on, so it silently discards every access. A gate-level run without
SDF has the same problem, which is why the substitution is unconditional.

Gate-level runs set `GL_SIM`, because synthesis flattens hierarchy and any probe reaching
into the design has to be guarded or rewritten as an escaped flat identifier.

Waveforms are written as FST. Open them with GTKWave or Surfer inside the container.
