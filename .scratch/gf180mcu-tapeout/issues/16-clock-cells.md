# Write the GF180MCU clock cells

Type: task
Status: open
Blocked by: none

## Question

Graduated from ticket 03, which measured what the SoC actually instantiates. Six module
names, 70 instances, three technology cells behind them:

| Module | Instances | Cell behind it |
| --- | --- | --- |
| `pulp_clock_gating` | 55 | integrated clock gate |
| `cluster_clock_gating` | 1 | the same integrated clock gate |
| `cv32e40p_clock_gate` | 1 | the same integrated clock gate |
| `pulp_clock_mux2` | 8 | glitch-free clock mux |
| `pulp_clock_inverter` | 4 | clock inverter |
| `cluster_clock_inverter` | 1 | the same clock inverter |

They all live in one file, `rtl/gf180mcu/gf180_clk_gate.sv`, following upstream's
`pulp_clock_gating_xilinx.sv` in structure. Ports are in `flow/synth/stubs.sv`, taken from
the instantiation sites; delete each stub as its real module lands.

This is the one piece of technology-cell work that nothing blocks. It does not wait on the
memory architecture, the boot decision or the supply voltage, and it takes 70 instances out
of the black-box list, which makes ticket 10's synthesis measurement that much less
synthetic.

Decide, with evidence rather than by inspection of the cell name:

- **Which ICG cell.** `gf180mcu_fd_sc_mcu7t5v0__icgtp_*` is the candidate named in
  `rtl/gf180mcu/README.md`. Confirm it exists in the pinned PDK, at which drive strengths,
  and check its Liberty for a test-enable pin, because all three module families pass one
  (`test_en_i` / `scan_cg_en_i`) and a cell without it needs the enable ORing in RTL instead.
- **Whether to instantiate the cell or infer it.** Yosys can map `$dlatch`-based gating
  itself, and LibreLane's flow has its own clock-gating handling. An explicit instance is
  predictable and keeps the cell name in the netlist; inference risks the tool producing a
  latch plus AND that never becomes an ICG. Pick one deliberately and say why.
- **The clock mux.** GF180MCU may have no glitch-free mux cell. If it does not, this is
  ordinary RTL (a synchronised, break-before-make mux) rather than a cell instance, and it
  needs to be written rather than bound. Check before assuming a cell exists.
- **Whether the file is variant-neutral.** It instantiates cells by name only, so it should
  be, but state it: nothing here may hardcode a path into `pdk/`, and a cell name is not a
  variant assertion.

Upstream style applies, since this file is a ticket 13 candidate: `snake_case`, `_i` / `_o`
suffixes, and the SPDX header from `rtl/gf180mcu/README.md`.

## Definition of done

`make elaborate` reports the six modules gone from the missing list with no new errors, and
the stubs for them are deleted from `flow/synth/stubs.sv`. The answer records the cell chosen,
its drive strength, whether the test-enable pin exists, and what the clock mux turned out to
need.

## Answer

<!-- filled on resolution -->
