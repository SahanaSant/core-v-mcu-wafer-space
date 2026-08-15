# Write chip_top.sv and route the design against ticket 21's floorplan

Type: task
Status: resolved
Blocked by: 23, 24

## Question

Ticket 21 decided the shape (2 rows x 8 columns), placement (south edge, private banks then
interleaved channels) and power domain (single 3.3 V rail, no split) for the sixteen SRAM
macros, but stopped short of building any of it: `rtl/chip/chip_top.sv` doesn't exist, and the
SoC can't even elaborate end to end until tickets 23 and 24 land (`a2_bootrom` and `apb_pll` are
still black boxes). This ticket is the build: write the top level, seed the LibreLane
configuration from the wafer.space template, and get a run through detailed routing.

What has to happen:

- **`rtl/chip/chip_top.sv`**, seeded from `src/chip_top.sv` in the
  [wafer.space project template](https://github.com/wafer-space/gf180mcu-project-template), not
  written from scratch. One instance of `core_v_mcu`, the pad ring (`gf180mcu_ocd_io` per ticket
  18, 40 bidirectional + jtag + ref_clk_i/rstn_i/stm_i per ticket 06's pin table), and the five
  wafer.space marker cells (`qrcode_id`, `shuttle_id`, `project_id`, `marker`, `logo`) each
  present exactly once. `PAD_SOUTH`/`EAST`/`NORTH`/`WEST` side assignment is new work here, not
  fixed by any prior ticket.
- **`flow/config.yaml`**, `flow/chip_top.sdc`, `flow/pdn/pdn_cfg.tcl`, `flow/macros.yaml`,
  `flow/macro_placement.cfg`, `flow/gf180mcu_render.lyp`, per `flow/README.md`'s table. Seed
  from the template's `librelane/` directory and diff, per the map's Notes. The template's own
  `macros.yaml` folds instance placement into the macro definition (no separate
  `macro_placement.cfg`); check whether that structure or the two-file split `flow/README.md`
  describes is what the LibreLane version in this container actually wants before committing to
  one.
- Sixteen macro instances placed per ticket 21's decision: 2 rows x 8 columns, south edge,
  private bank 0/1 then interleaved channel 0/1 left to right. Compute exact coordinates from
  the macro LEF `SIZE` and the `slot_1x1` core area, the way `patch_ocd_sram.sh` already computes
  area from LEF rather than hardcoding it.
- PDN: single 3.3 V core ring (ticket 21), macro perimeter grids on Metal2/Metal3, Metal4/Metal5
  free over the macros, following the template's `pdn_3v3_sram.tcl` pattern rather than writing
  the stripe geometry from scratch.
- `MAGIC_GDS_FLATGLOB` entries for the OCD SRAM macros, discovered by running into false DRC
  errors, added to `flow/config.yaml`'s list.
- Four LibreLane settings moved together for the 3.3 V corner, per `flow/README.md`:
  `VDD_PIN_VOLTAGE: 3.30`, `CELL_LIBS`, `STA_CORNERS`, `DEFAULT_CORNER` from `tt_025C_3v30`,
  `ff_n40C_3v60`, `ss_125C_3v00`.

## Definition of done

`make harden` completes through detailed routing with no fatal errors. Quote the real numbers:
final density against the 35% target, whether the design actually placed and routed at that
density or needed a different target, and any `MAGIC_GDS_FLATGLOB` patterns discovered along the
way. Sign-off (a clean `make precheck`) is not required to close this ticket, matching ticket
21's own DoD language: this closes when the design places and routes, not when it passes
precheck.

## Answer

**Built the top level and the whole LibreLane configuration, and the design places, legalises
and passes the power grid check with real margin. It does not route yet, and the reason is not
the design: `OpenROAD.CTS` null-dereferences on it on all but roughly one attempt in a hundred.**
The Definition of Done asked for a completed run through detailed routing, so this ticket does
not meet it; the routed run is spun off as ticket 26, the same shape as tickets 04 and 05
spinning off 23 and 24, and 21 spinning off this one.

### What was built

`rtl/chip/chip_top.sv` and `rtl/chip/chip_core.sv`, seeded from the template's pair and split
the same way: `chip_top` holds pad cells and the five marker cells and nothing else, so its
instance names stay a one-to-one match for `PAD_SOUTH`/`EAST`/`NORTH`/`WEST`; `chip_core`
holds one `core_v_mcu` and the `pad_cfg_o` fan-out. Three deliberate departures from the
template, each with a reason in the file headers: no `gf180mcu_xxx_io__*` indirection (ticket
18 fixed the ring at `gf180mcu_ocd_io` and the foundry alternative is not buildable here at
all), no `slot_defines.svh` (one slot, so the pad counts are parameters), and one retyped pad,
below.

`flow/config.yaml`, `flow/slot_1x1.yaml`, `flow/macros.yaml`, `flow/chip_top.sdc`,
`flow/pdn/pdn_cfg.tcl`, `flow/pdn/pdn_sram.tcl` and `flow/gf180mcu_render.lyp`, all seeded
from `librelane/` in the template and diffed against it. `ip/` vendors the five
`gf180mcu_ws_ip__*` marker cells (Apache-2.0). There is no `macro_placement.cfg`: the template
folds instance placement into the macro definition and that is what
`Odb.ManualMacroPlacement` reads here, so `flow/README.md`'s table is corrected rather than
satisfied.

The file list is **not** written into the flow config. `flow/synth/sources.sh` regenerates it
from fusesoc into `flow/build/sources.yaml` on every fresh `make harden`, reusing the same
`filelist.sh` that `make elaborate` and `make area` already use, so the design's sources have
one source of truth instead of two that drift.

### The pad assignment, which was the one real decision left

The ticket said side assignment was "new work here, not fixed by any prior ticket". It turned
out to be **fixed by the template's README**, which is explicit that the default bonding setup
and the breakout PCB are drawn against the pad positions: do not change the number of pads, do
not change any power or ground pad, and only a signal pad's *type* may change. So all 58
positions are the template's, in the template's order, and:

- **Ticket 18's provisional 5/5/4/4 power-pad split is superseded.** It is 6 `dvdd`, 8 `dvss`,
  2 `vdd`, 2 `vss`, because that is what the breakout PCB expects. Two core supply pads for a
  design this size is worth watching in `OpenROAD.IRDropReport` rather than assuming.
- **One pad changed type**: the template's `inputs[11]` position, at the head of the west
  signal run, is a `bi_24t` rather than an `in_c`. `jtag_tdo_o` is the only signal outside the
  io array that drives, and the input pads have no output driver. The alternative was to spend
  a bidirectional pad from the io array, which would have cost ticket 06's spare at `io_num`
  39 for nothing. All five JTAG signals now sit in one contiguous west run just below the core
  VDD/VSS pair.
- `bidir[n]` carries `io_num` n directly, so ticket 06's table lands GPIO 0-13 on the south
  edge (the quietest functions on the edge ticket 21 gave the SRAM array), GPIO 14/15 with PWM
  and i2cm0 east, uart0/qspim1/sdio0/qspim0 north.
- **`pad_cfg_o`'s bit mapping is defined here and nowhere else**, because upstream never
  defines it ("electrical configuration, which is not implemented in the current design"). Bit
  0 to CS, 1 to SL, 2 to IE, 3 to PU, 4 to PD, 5 reserved. The register resets to all ones and
  that is the safe state under this mapping — Schmitt inputs, slow slew, input buffer on, no
  pull — because the pad's pull devices are `~OE && PU && ~PD` and `~OE && ~PU && PD`, so both
  bits high is "neither" rather than contention.

### Macro placement, computed rather than carried over

Two rows of eight along the south edge, columns abutted at `760.00 + n * 301.300`, rows at
y 502.00 and y 1118.00, all sixteen placed **FS** rather than the template's N. FS mirrors in
y only, which turns the 3 um pin band upwards: row 1's interface then faces the standard-cell
region directly and needs no channel above the array, and row 0's faces the 100.19 um channel
between the rows. Placing them N would have put row 0's whole interface against the core's
south boundary with nowhere to escape but back over the array. The array is 2410.40 um of
macro centred in 3048 um of core, 318.00 um free on the left and 319.60 on the right.
Verified in the run: all sixteen, plus the five marker cells, placed at exactly these
coordinates.

`pdn_sram.tcl` selects the grid by `-cells` rather than by instance name, so it does not
repeat the sixteen paths `macros.yaml` already carries. The template's stripe geometry
transfers unchanged and this is worth knowing: the 512x8 and the 1024x8 are **both 301.300 um
wide** and differ only in height, so the 298.30 um perimeter pitch still lands the power strap
of each pair on the macro's own Metal2 supply ring.

### Measured

- **Synthesis.** `chip_top` is 4,304,230 um2 of which 1,942,500 is the 74 pad cells, so
  2,361,730 um2 of standard cells against ticket 24's 2,334,966 for `core_v_mcu` alone. 25.06%
  of it is sequential.
- **Floorplan.** DIE 3932 x 5122, CORE 442..3490 x 442..4680, the core's lower left snapped by
  OpenROAD to (442.400, 442.960). 74 pad cells: 56 signal (41 `bi_24t`, 12 `in_c`, 1 `in_s`, 2
  `asig_5p0`) and 18 power, exactly the 1x1 slot's budget.
- **Global placement: 40.9% overall utilisation, 25.9% standard cells**, against a
  `PL_TARGET_DENSITY_PCT` of 35. The design places with real headroom and did not need a
  different target. That answers ticket 21's "density headroom" question and the
  schedule-viability fog patch's "does it place cleanly at 35% density".
- **Design repair is the surprise, and it is a big number.** `RepairDesignPostGPL` found
  17,730 slew, 2,037 fanout and 1,225 capacitance violations and fixed them with **61,069
  buffers in 9,724 nets** plus 16,821 resized instances. Standard-cell area goes from
  2,667,750 to **4,476,590 um2** and utilisation from 25.9% to **43.5%**; instance count goes
  from 161,368 to 222,437. This is the first time the map has measured what
  `flow/README.md`'s "no buffering at all on its highest-fanout nets" actually costs, and the
  answer is a two-thirds increase in cell area. It fits, but nothing before this run had
  priced it.
- **`PL_MAX_DISPLACEMENT_X/Y` had to go from the template's 500 x 200 to 1000 x 1000.** Those
  61,000 buffers land on a placement that had already spread to the density target, and at the
  template's search distance `detailed_placement` could not find room for 425 of them and
  failed outright (`DPL-0036`). The core is only a quarter full at that point, so the space
  exists; it is further away than the default will look.
- **PDN passes.** `Checker.PowerGridViolations` is clean. 48 `PDN-0110` "no via inserted
  between Metal3 and Metal4" warnings, three per macro, at the macro boundaries — this is
  `pdn_sram.tcl`'s stripe geometry not landing perfectly on the OCD macro's own rings, and it
  is worth revisiting in ticket 26 rather than left unexamined.
- **No `MAGIC_GDS_FLATGLOB` patterns discovered**, because the run never reached Magic DRC.
  The list is still the template's. That part of the DoD travels to ticket 26.

### Four bugs found, all fixed

1. **`PAD` still defaulted to the foundry `gf180mcu_fd_io`** in both `Makefile` and `run.sh`,
   despite ticket 18. Exactly the shadowing trap the map's Notes warn about, and ticket 24 hit
   the same one with `CLOCK_PERIOD_NS`. It failed loudly here only because the `ocd_io` cell
   names do not exist in the foundry library; a subtler mismatch would have passed silently.
2. **`VDD_PIN_VOLTAGE` is a removed variable in LibreLane 3.1** ("Information should be
   obtained from dotlib files", `config/removals.py`). It was accepted in silence and never
   reached `resolved.json`. `flow/README.md`'s "four settings have to move together" is now
   three; check `resolved.json` rather than the config when a corner override looks like it
   did not take.
3. **LibreLane's gf180mcu compatibility shim deletes `SYNTH_LATCH_MAP`** from the PDK
   configuration (`config/pdk_compat.py`), so the netlist carried two unmapped `$_DLATCH_P_`
   cells (`apb_soc_ctrl`'s `reset_reason[1:0]`; ticket 06's `bootsel` removal took the other
   two). Set explicitly in `flow/config.yaml`.
4. **`soc_domain.sv`'s `edge_propagator_rx ep_pf_evt_i` had two undriven implicit nets.**
   `pf_evt_valid_i` and `pf_evt_ack_o` are not ports of the module and were never declared, so
   `pf_evt_valid_i` had no driver at all, which LibreLane's Yosys synthesis check reports as
   an error. Declared and tied off. **The instance itself is left in place on purpose**, and
   that is a finding worth carrying: deleting it and driving `s_pf_evt` to 0 directly is the
   obvious simplification (the block is held in permanent reset by a hardcoded `rstn_i(1'b0)`
   and feeds an input `soc_peripherals` comments out as "unused core-v-mcu"), and it moves ten
   cells in a 118,730-cell netlist, and that was enough to push ABC's technology mapping from
   four minutes to over eighty without finishing. The cells fold away either way, so the
   tidier version buys nothing and costs an hour a run.

### Why it does not route: the CTS crash

`OpenROAD.CTS` dies on a signal, silently, about a minute in and immediately after it finishes
enumerating clock nets. The stack trace is a null dereference:

```
odb::dbNet::get1stSignalInput(bool)
cts::TritonCTS::separateMacroRegSinks(...)
cts::TritonCTS::initClockTreeForMacrosAndRegs(...)
cts::TritonCTS::initClock(...)
cts::TritonCTS::initOneClockTree(...)   x11, recursing
```

**It is intermittent, not configuration-dependent, and that is what made it expensive to
characterise.** One attempt passed. Re-running the same step later against the byte-identical
resolved SDC that pass had emitted, from the same placement database, failed — and then failed
about forty more times. Every apparent fix along the way was a lucky run misread as a result:
removing the JTAG clock, removing the `/40` generated clock, `set_clock_groups`, the
`jtag_tdo` output delay, `CTS_SINK_CLUSTERING_ENABLE`, `CTS_OBSTRUCTION_AWARE`,
`CTS_DISABLE_POST_PROCESSING`, `CTS_BALANCE_LEVELS`, singly and combined. Memory is not the
cause either: 5.3 GB free at the low-water mark, nothing in the kernel log.
`separateMacroRegSinks` iterates an `unordered_set<dbMaster*>`, keyed on pointers and so
ordered differently in every process, which is a plausible mechanism for the variance.

The lesson generalises past this bug and belongs in the map's Notes: **on this design a single
pass or a single failure of a physical step is not evidence.** Anything that looks like a fix
here needs twenty-plus attempts before it counts.

Two things follow. `make harden-cts` retries the step until it survives, the same shape as
`flow/pdk/build.sh` retrying magic (ticket 15). And `chip_top.sdc` declares **one** clock
rather than three, because each extra clock is another tree to build and another chance to hit
the crash. The two left out are written down in that file in full, ready to paste back: the
TAP's `jtag_tck` on `inputs[0].pad/Y`, and `ref_clk_div40`, a `create_generated_clock
-divide_by 40` off net `*apb_fll_if_i.ref_clk_o` (the outer port, not `clkdv`'s internal
`clkout`, which folds away at a constant divisor). Both resolve and both are accepted by
`CheckSDCFiles` and `STAPrePNR`. What the two domains lose is a *balanced* tree, not
buffering; for the 250 kHz divided clock that is close to immaterial against a 4000 ns period,
but for the TAP it is a real gap and a gate-level JTAG timing result from this netlist should
not be trusted until it is closed.
