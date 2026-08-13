# Get upstream RTL through a SystemVerilog front end

Type: prototype
Status: open
Blocked by: 01, 02

## Question

Which SystemVerilog front end reads the CORE-V MCU, and what does it take to get a clean
elaboration with the eFPGA removed?

This is the schedule risk. Yosys alone will not read upstream's RTL: it uses interfaces,
packages and packed structs across more than fifty files. Two paths, in order of preference
from `flow/README.md`:

1. `USE_SLANG: True` with `SLANG_ARGUMENTS: ['--keep-hierarchy']`. Both appear commented out
   in the wafer.space template config. yosys-slang elaborates PULP Platform designs including
   Snitch-Cluster and Cheshire, so this is the most likely path to work.
2. The PULP chain: Bender, then Morty, then SVase, then sv2v down to Verilog-2005. Ticket 09
   strengthened the case for this path considerably: Basilisk took it all the way to silicon
   on a multi-million-gate PULP-ecosystem SoC. Yosys-slang remains listed first because it is
   far less machinery, but path 2 is the one with a tapeout behind it.

**Ticket 09 has resolved. Read its answer before starting.** It did not collapse this
ticket, but it changed what you should read and it hands you some free starting material:

- Upstream RTL needed **no source patches** at core scope in the one prior attempt. All
  workarounds were file-level exclusions.
- Starting exclusion list: `cv32e40p_register_file_latch` (use the flip-flop variant
  instead), `cv32e40p_prefetch_controller_sva` and other SVA, `cv32e40p_core_log`. Scaling
  to the full SoC, also drop `fpga`, `_latch`, `simulation` and `deprecated` paths and
  `apb_efpga_demux`.
- Defines: `TOVERILOG`, `SYNTHESIS`, `DISABLE_EFPGA`. That last one means upstream already
  has a supported way to compile the eFPGA out, which is worth finding before hand-editing
  `core-v-mcu.core`.
- Nothing from `lip6/core-v-180-mcu` may be copied. It has no LICENSE file.

**Required reading: the Basilisk paper** (arXiv:2405.04257, with arXiv:2406.15107 and
arXiv:2505.10060). ETH Zürich and Bologna drove Cheshire through exactly path 2 below to a
real tapeout with zero DRC violations. It is the strongest evidence any of our candidate
paths has, it documents the custom Yosys and ABC scripting the QoR actually needed, and its
1.8 MGE to 1.1 MGE reduction is directly relevant to ticket 10.

Getting there also means defining the GF180 target: remove the `quicklogic.com:ip:efpga`
dependency from `files_rtl_generic`, add a `gf180mcu` fileset as a third sibling of
`rtl-simulation` and `emulation-rtl`, and decide what the eFPGA's APB slot at `0x1A30_0000`
becomes (tied-off decode, or removed from the map).

## Definition of done

Yosys reads and elaborates the full SoC with memories and technology cells as black boxes,
and reports no unresolved syntax or hierarchy errors.

The answer records three things: the front end chosen and why, the exact invocation and any
patches upstream RTL needed, and **the definitive list of modules reported missing**. That
last item is the point of this ticket. `rtl/gf180mcu/README.md` has a first guess at the
list, but it is a hypothesis; the real list is what graduates the technology-cell RTL work
out of the fog.

## Answer

<!-- filled on resolution -->
