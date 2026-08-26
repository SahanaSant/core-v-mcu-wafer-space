# sim/

cocotb testbenches driving `chip_top`, at RTL (`make sim`, Verilator) and gate level
(`make sim-gl`, Icarus) from the repository root.

Upstream's own functional verification stays in the submodule. This directory covers what
upstream cannot see: the pad ring, the pad multiplexer, the reduced memory map, and whether
the hardened netlist still works.

How to run it and what a pass proves: [docs/how-to/simulate.md](../docs/how-to/simulate.md).
