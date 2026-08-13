# Get upstream RTL through a SystemVerilog front end

Type: prototype
Status: resolved
Assignee: yusefkarim
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

**yosys-slang, first try, and the schedule risk this ticket was named for does not exist.**
The full SoC elaborates in about two seconds with one upstream source patch of one line. The
PULP chain was not needed and was not attempted.

Run it with `make elaborate`.

### The front end

Yosys 0.67 in the pinned container ships the slang plugin, so `plugin -i slang; read_slang`
is all it takes. Path 2 is not just unnecessary, it is unavailable: the container has bender
and sv2v but neither morty nor svase, so taking it would have meant installing tools before
reading a line of RTL.

The exact invocation, from `flow/synth/elaborate.sh`:

```
read_slang -F gf180.f -D SYNTHESIS --top core_v_mcu --keep-hierarchy --error-limit=0
hierarchy -check -top core_v_mcu
stat -top core_v_mcu
```

`hierarchy -check` passes. The design comes out at 81,414 word-level Yosys cells across 132k
wires, which is a pre-techmap number and not a gate count, but it is the first measurement of
the design that exists. Ticket 10 turns it into gates.

Three details that cost time and will cost it again:

- **`--ignore-unknown-modules` is gone.** Current yosys-slang refuses it and points at
  `sv-elab`'s "No unknown modules" page. Unresolved instances are now a hard error, so a
  design with technology cells missing does not elaborate at all until something declares
  them. `flow/synth/stubs.sv` is that something: an empty module per missing cell, carrying
  only the port list. It shrinks as `rtl/gf180mcu/` fills in.
- **`--error-limit=0`.** The default limit is 20, and the first run hit it before reaching
  half the missing modules. Without this you get a partial list and think it is the list.
- **The file list is generated, not written.** `fusesoc --cores-root core-v-mcu run --target
  default --tool verilator --setup` resolves upstream's own `default` target and emits a
  `.vc`; the script keeps its `+incdir+` and source lines, drops the eFPGA, and appends
  `rtl/gf180mcu/*.sv` and the stubs. Every IP is vendored inside the submodule, including all
  the PULP dependencies, so this needs no network access.

### What upstream RTL needed

**One patch, one line**, committed on the submodule's local `master` as `a6b6fdc`:
`rtl/apb_i2cs/rtl/i2c_peripheral_interface.v:51` guards an `always @(posedge rst or posedge
clk)` block with `if (rst == 1)`, and a strict front end cannot match a comparison back to
the event list, so the asynchronous reset is unmatched and the block is rejected. `if (rst)`
fixes it. That is target-independent and belongs upstream on its own; it has been added to
ticket 13's early-PR list.

This corrects ticket 09 in one direction and confirms it in another. Its "no source patches
at core scope" holds for the core and is false for the full SoC, by exactly one line. But its
**exclusion list turned out to be unnecessary**: fusesoc's own filesets already pick
`cv32e40p_register_file_ff` over the latch variant and already leave the SVA and
`core_log` files out, so nothing had to be filtered for the core. The eFPGA is the only
exclusion in the script.

Ticket 09's other free gift does not exist. **There is no `DISABLE_EFPGA` define anywhere in
upstream at this commit** (`grep` across all `.sv` and `.svh` finds zero hits). Whatever
carried that name, it was not here, so the eFPGA had to be removed structurally.

### How the eFPGA was removed

Without patching upstream, by name collision. `rtl/gf180mcu/gf180_efpga_stub.sv` defines
`efpga_subsystem` with upstream's exact port list and terminates every interface;
`soc_peripherals.sv` still instantiates it, unmodified, and the QuickLogic sources simply
never enter the file list. They could not be read anyway: `ql_fcb/rtl/fcb.sv` sits inside
`` `protect ``/`` `endprotect `` envelopes, which was the very first error of the very first
run.

The APB slot at `0x1A30_0000` **stays in the memory map**, decoded, answering every access
with zero and never asserting `pslverr`. Software that probes the FCB registers reads zeros
instead of stalling or trapping, which is the forgiving failure mode on a first tapeout, and
the memory map and the software headers generated from it do not have to change. The APB-T1
TCDM port answers through upstream's own `tcdm_error_slave`, returning `0xBADACCE5`, because
TCDM has no never-error idiom and that value is self-identifying in a trace. The four TCDM
master ports into L2 hold `req` low, so they should constant-fold away; ticket 10's
per-module breakdown is where to confirm they actually did.

### The definitive list of missing modules

This is the point of the ticket. Ten modules, with instance counts, and it is now a report
rather than a guess: `make elaborate` prints it and it moves as the design moves.

| Module | Instances | Where it goes |
| --- | --- | --- |
| `pulp_clock_gating` | 55 | `gf180_clk_gate.sv` |
| `pulp_clock_mux2` | 8 | `gf180_clk_gate.sv` |
| `pulp_clock_inverter` | 4 | `gf180_clk_gate.sv` |
| `cluster_clock_gating` | 1 | `gf180_clk_gate.sv` |
| `cluster_clock_inverter` | 1 | `gf180_clk_gate.sv` |
| `cv32e40p_clock_gate` | 1 | `gf180_clk_gate.sv` |
| `core_v_mcu_interleaved_ram` | 4 | `gf180_interleaved_ram.sv` |
| `core_v_mcu_private_ram` | 2 | `gf180_private_ram.sv` |
| `a2_bootrom` | 1 | `gf180_bootrom.sv` |
| `apb_pll` | 1 | `gf180_clk_gen.sv` |

Four things in that table differ from `rtl/gf180mcu/README.md`'s hypothesis, and each one
moves another ticket:

- **The clock cells are six modules in three naming families, not one.** `pulp_*`,
  `cluster_*` and `cv32e40p_clock_gate` all want the same integrated clock gate, and there
  are a clock mux and a clock inverter besides. 70 instances in total. This is now ticket 16
  and it is the only piece of technology-cell work that can start immediately.
- **`apb_pll` is the entire clock generator, not a PLL cell inside one.** Upstream's ASIC
  build wraps a `PLL18_TOP` hard macro; its FPGA build replaces the whole module through
  `fpga_pll.sv`, and GF180MCU has to do the same. So `gf180_clk_gen.sv` provides the APB
  register file, the dividers and the clock source together. Its five analog supply ports
  (`AVDD`, `AVDD2`, `AVSS`, `VDDC`, `VSSC`) are connected in `soc_peripherals.sv` to
  identifiers that are declared nowhere, so they are implicit wires going nowhere and **no
  analog supply reaches the SoC boundary today**. Noted on ticket 05.
- **No pad wrappers.** `pad_functional_pd` and `pad_functional_pu` are defined in
  `tech_cells_generic` and in upstream's Xilinx directory but are never instantiated
  anywhere; `core_v_mcu.sv` exposes plain `io_in_i` / `io_out_o` / `io_oe_o` ports. Pads are
  entirely a `chip_top` concern, so `gf180_pads.sv` belongs in `rtl/chip/`, not
  `rtl/gf180mcu/`, and it is not a prerequisite for synthesis.
- **No `sram512x64` and no `bw_mac`.** Both appear in the Xilinx fileset and neither is
  reachable from `core_v_mcu`.

### One finding that is not about the front end

The design elaborates with **two inferred memories, 4,096 memory bits**, and both of them are
inside the I2C slave: `FIFO_sync_256x8_apb_to_i2c` and `FIFO_sync_256x8_i2c_to_apb`, each a
`RAM_256x8_behavioral`. There is no macro behind them, so at 256 bytes each they synthesise
to roughly 2,048 flip-flops plus address decoding, for a peripheral nothing in the bring-up
plan uses. Recorded on ticket 12, which is where it gets cut or kept.

### On the required reading

The Basilisk paper was not read. This ticket named it required because it is the strongest
evidence for path 2, and path 1 worked on the first attempt, so it has no bearing on the
decision this ticket had to make. Its value was never really the front end: it is the custom
Yosys and ABC scripting behind a 1.8 MGE to 1.1 MGE reduction, which is a quality-of-results
question. That has been moved to ticket 10, where it belongs.

### Repository changes made

- `flow/synth/elaborate.sh` and a `make elaborate` target. Regenerates the file list from
  scratch every run, so it cannot drift from the submodule.
- `flow/synth/stubs.sv`, black boxes for the ten missing modules, deleted entry by entry as
  real cells land.
- `rtl/gf180mcu/gf180_efpga_stub.sv`, described above.
- `rtl/gf180mcu/README.md`: the hypothesis table replaced by the measured one, plus the pad
  and `apb_pll` corrections and a section on the eFPGA slot.
- `flow/README.md`: the front-end section now records the decision rather than the options,
  including the `SYNTHESIS` and `PULP_FPGA_EMUL` define policy. `PULP_FPGA_EMUL` must stay
  undefined, and fusesoc's `default` target declares it as a parameter defaulting to true, so
  a backend that passes parameters through would silently build the FPGA branches.
- `flow/build/` added to `.gitignore` and to `make clean`.
