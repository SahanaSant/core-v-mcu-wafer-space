# Measure the real logic area

Type: task
Status: open
Blocked by: 03

## Question

How large is the SoC's logic, actually?

`docs/porting-analysis.md` estimates 200 to 300 kGE for the full SoC, roughly 3 to 5 mm²
placed at 35% density, leaving 7 to 9 mm² of the 12.92 mm² core for SRAM. That estimate is
the weakest number in the entire plan, and tickets 11 and 12 both depend on it. Replace it
with a measurement.

Synthesise with memories black-boxed and technology cells stubbed, against
`gf180mcu_fd_sc_mcu7t5v0`. This does not need real SRAM wrappers, real pads or a floorplan;
it needs a cell count.

**Ticket 03 has resolved and left most of the setup behind.** `make elaborate` runs
`flow/synth/elaborate.sh`, which generates the file list from the submodule with fusesoc,
excludes the eFPGA, adds `rtl/gf180mcu/` and the black boxes in `flow/synth/stubs.sv`, and
reads the design through yosys-slang. Extend that script rather than starting a new one: the
committed, repeatable synthesis script this ticket asks for is that file plus `synth` and
`abc`. Elaboration currently reports 81,414 word-level Yosys cells, which is pre-techmap and
not a gate count, but it is the number this ticket has to replace.

Two things to watch that ticket 03 surfaced:

- The eFPGA is gone, replaced by a tie-off stub whose four TCDM master ports hold `req` low.
  They should constant-fold the interconnect ports feeding them away. Check whether they did,
  because if they did not, `soc_interconnect` is carrying four dead master ports.
- The I2C slave brings two 256×8 behavioural RAMs, 4,096 memory bits with no macro behind
  them. Expect roughly 2,048 flip-flops in `apb_i2cs` unless they are cut. Break `apb_i2cs`
  out separately in the per-module table so ticket 12 sees the cost.

**Read the Basilisk paper here** (arXiv:2405.04257, with arXiv:2406.15107 and
arXiv:2505.10060), not for the front end, which is settled. ETH Zürich and Bologna document
the custom Yosys and ABC scripting behind a 1.8 MGE to 1.1 MGE reduction on a PULP-ecosystem
SoC in an open flow. That is a quality-of-results question and this is the quality-of-results
ticket, and a third off the gate count is the difference between fitting and not.

## Definition of done

A report containing:

- Total cell count and total cell area in µm².
- Gate-equivalent count, using the GF180 7T NAND2 at roughly 6.6 µm².
- Placed area at `PL_TARGET_DENSITY_PCT: 35`, and the implied SRAM budget once subtracted
  from 12.92 mm².
- **A per-module breakdown**, so ticket 12 can cut peripherals with data rather than
  intuition. The uDMA subsystem in particular should be broken out per peripheral.
- A first look at the critical path, feeding the frequency question in ticket 05.

Commit the synthesis script so the measurement is repeatable after every RTL change. The
number will move, and re-measuring should be one command.

## Answer

<!-- filled on resolution -->
