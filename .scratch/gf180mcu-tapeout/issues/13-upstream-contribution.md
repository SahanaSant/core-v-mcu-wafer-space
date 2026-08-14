# Contribute the portable technology cells upstream

Type: task
Status: open
Blocked by: 11, 12

## Question

**Do not start this before the GDS is signed off.** It sits past the destination, and the
December deadline comes first. It exists as a ticket so it is not forgotten, not so it
competes.

Which files go to `openhwgroup/core-v-mcu`, packaged how?

The repository was structured for this from the start. `rtl/gf180mcu/` mirrors upstream's
`emulation/xilinx/rtl/` file for file, and is a third sibling of the `rtl-simulation` and
`emulation-rtl` filesets in `core-v-mcu.core`. The technology cells go up; the pad ring,
floorplan and chip top stay here, because they are shuttle-specific.

Decide:

- Which files cross the boundary. The clock gate, SRAM wrapper and boot ROM are the obvious
  candidates. `gf180_pads.sv` is arguable, since pad choice is shuttle-specific but pad
  wrapping is not.
- Whether the fileset should be named for GF180 specifically or for ASIC targets generally,
  which is really a question about whether upstream wants one open-PDK target or a family.
- The `soc_domain.sv:101` `L2_BANK_SIZE` fix and the `perdef.json` regeneration, which are
  bug fixes and target-independent improvements. These could go upstream much earlier than
  the rest, and arguably should. Ticket 03 added a third to that list, already committed
  locally as submodule `a6b6fdc`: `i2c_peripheral_interface.v:51` guards an async-reset block
  with `if (rst == 1)`, which no strict front end can match back to the event list, so the
  file does not elaborate outside Synopsys. One line, target-independent, and it blocks
  anyone else trying to read the SoC with an open front end. Ticket 17 added a fourth:
  parameterising `N_EFPGA_TCDM_PORTS` to 0 (`efpga_subsystem.sv`, `soc_peripherals.sv`,
  `soc_domain.sv`, `soc_interconnect_wrap.sv`, `NR_TCDM_MASTER_PORTS` 9→5) instead of relying on
  flatten-time constant folding to remove the four dead eFPGA master ports. `make area`'s
  flattened total is expected to show no delta, since ticket 10 found the flow already folds
  this away for free; the only payoff is structural honesty for the PR.
- Process: the Eclipse Contributor Agreement, fork, branch, pull request, and whoever at
  OpenHW to talk to before opening it.

**Two preconditions from ticket 02, neither of which exists.** That ticket resolved to *no
fork* and *no ECA*: nothing from this effort is published until the dev decides to publish it,
so this ticket cannot open a PR from anywhere. When that changes, both are cheap but not
instant. The fork can go under `yusefkarim` or `riscv-ottawa` (the dev is an admin of the
latter); the ECA is free but slow, and it validates the **commit author email**, so
`yusefkarim@riseup.net` has to be registered on the Eclipse account or this port's history
needs rewriting first. PR branches follow upstream's `<org>_<userid>_yyyymmdd` convention,
which is what that convention is for; the port itself sits on plain local `master`.

## Definition of done

Pull requests opened against upstream, with the shuttle-specific parts correctly left behind.

## Answer

<!-- filled on resolution -->
