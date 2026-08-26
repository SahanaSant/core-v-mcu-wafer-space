# sw/

Two RV32IMC images, both built by the flow rather than by hand.

- `bootrom/` — the boot ROM. `make bootrom` compiles it and regenerates
  `rtl/gf180mcu/gf180_bootrom.sv` from the result, then checks the generated module against
  the compiled image under Icarus. The RTL is stale until you re-run that.
- `app/` — the payload the boot ROM copies from flash and jumps to: an SRAM walk and a UART
  print, which is what makes a simulation run pass or fail. Built automatically by
  `make sim` and `make sim-gl`.

Both builds regenerate the `core-v-mcu/sw/inc` headers from `gf180-pin-table.csv` and
`perdef.json` first, so the software's view of the peripherals cannot drift from the RTL's.

See [docs/how-to/simulate.md](../docs/how-to/simulate.md).
