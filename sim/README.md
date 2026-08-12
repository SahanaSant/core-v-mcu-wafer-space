# Simulation

cocotb testbenches driving `chip_top`, run with `make sim` (RTL) and `make sim-gl`
(gate level) from the repository root.

Seed the harness from `cocotb/` in the
[wafer.space project template](https://github.com/wafer-space/gf180mcu-project-template),
which already wires up Icarus, the pad-level top, and waveform output.

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

## First tests worth writing

Cheap, and they catch the failure modes that actually bite:

1. Reset release and clock reaching the core from `ref_clk_i` with the FLL bypassed.
2. A read-write-read walk across every SRAM bank, checking byte enables individually. Byte
   lane and depth-mux errors in the SRAM wrapper are the most likely silent bug.
3. Boot from reset to the first instruction fetch.
4. UART character out, which proves clock, memory, core and one peripheral together.

Waveforms are written as FST. Open them with GTKWave or Surfer inside the container.
