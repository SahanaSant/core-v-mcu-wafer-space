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
