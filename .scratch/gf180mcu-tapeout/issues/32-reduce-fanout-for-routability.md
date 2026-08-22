# Reduce broadcast fanout so detailed routing can converge

Type: grilling
Status: claimed
Blocked by: none

## Question

Detailed routing on this design does not converge, and ticket 29 now has the measurement
rather than the inference. The resumed 2026-08-20 route was the first to get past iteration
11, and two independent curves both say the step cannot finish.

Violations do keep falling, so this is not a hard floor: iterations 5 through 9 retired
between 465 and 1,702 each against a ~318K base, then iterations 10 and 11 retired 2,280 and
2,700, the best since iteration 4. What ends it is cost. Per-iteration wall time held near an
hour through iteration 7 (17, 17, 63, 58, 58, 57, 58 minutes), then broke upward to 76, 106,
176 and 220 minutes, roughly 1.4x per iteration. Iteration 11 alone burned 3h39m wall and
16h20m CPU across 8 threads.

With 52 iterations left to reach `droute_end_iter 64`, that is ~190 hours even holding cost
flat, and cost is compounding, not flat. Independently, 312,860 violations retiring at ~2,700
per iteration needs ~116 more iterations, nearly double the entire budget. Memory is not the
constraint and should not be chased: per-iteration peak RSS runs 4.2 to 5.7 GB with no trend,
far under the 12g container cap.

So the question is not how to route harder. It is what to change upstream so that the router
is handed something routable. The evidence points at fanout: global placement density is only
26.6%, well under the 35% target, so this is localized congestion rather than overpacking, and
`RepairDesignPostGPL` inserts 64,734 emergency buffers, 28% of the design's ~231K final
instances. Those buffers are the router's problem made visible — they exist because something
in the RTL drives far more load than the 10-fanout constraint allows, and they land wherever
the offending nets go. The 73 `delaynet_*_clk_PAD` hold-fix NDR nets are a second, smaller
version of the same story.

What to settle here:

- **Which nets actually cause it.** Identify the highest-fanout nets in the post-synthesis
  netlist and attribute the 64,734 buffers to them. This is the load-bearing step: everything
  below is guesswork until the top offenders are named. Reset distribution, the APB/peripheral
  address decode, and the uDMA channel-enable broadcasts are the obvious suspects, but they are
  suspects, not findings.
- **Whether the fix is RTL or synthesis.** Pipelining or explicitly buffering a broadcast
  signal in RTL is a real design change with real verification cost. A less-flattened synthesis,
  or per-module fanout constraints, might get most of the benefit for far less. Cost-order these
  before committing to the expensive one.
- **What "converged" has to mean for the deadline.** Run 3 is December 2026. A route that
  closes in 12 hours changes the schedule; one that closes in 120 does not. Whatever fix is
  chosen needs a target it is measured against.

Deliberately not in scope here: post-route timing closure itself. That is ticket 29, which
cannot proceed until a route completes, and is now blocked on this.

## Notes

Do not re-derive the convergence evidence — ticket 29's comments hold the full tables.

Any candidate fix has to be validated by a fresh route, and routes on this design are
expensive and, per the map's own fog, have unexplained multi-hour run-to-run variance in
global routing as well. Budget for that: this is not a ticket that closes in one session, and
the first session's honest output is probably the fanout attribution plus a cost-ordered
shortlist, not a fix.

Detailed routing is deterministic under `-or_seed 42`, so a re-route after an RTL change is a
genuine A/B against the numbers above rather than a fresh sample from a noisy distribution.
That makes the iteration-0 violation count (512,491 here) a cheap early signal: it lands in
well under an hour, so a candidate fix can be judged long before the full route would finish.

## Comments

### 2026-08-22: the fanout attribution, and it is not the RTL

Attributed every one of `RepairDesignPostGPL`'s 64,734 buffers to a root net, by parsing the
post-synthesis netlist (`RUN_2026-08-17_16-21-08/02-yosys-synthesis`) and the post-repair one
(`27-openroad-repairdesignpostgpl`), diffing the instance sets, and walking each inserted
instance backwards through other inserted instances until the walk reaches a net that existed
before the step. Pin directions come from the standard-cell LEF, so nothing here rests on
guessing which pin of a cell is an output. The walk attributes 64,734 of the 135,557 new
instances and leaves 70,823 unattributed; those 70,823 are exactly the connectionless physical
cells (`filltie`, `endcap`, IO fill) that tap insertion and PDN added, so the attribution
covers 100% of the actual buffers and the 64,734 it reaches matches `[INFO RSZ-0038]` exactly.

**The single largest cause is a wrong cell, not the RTL's fanout.** Grouping the inserted
buffers by the name OpenROAD gave them:

| name prefix | count | cell |
| --- | --- | --- |
| `fanout*` | 16,518 | `dlyb_1` |
| `wire*` | 24,908 | `buf_1/2/4/8`, `clkbuf_1/2` |
| `load_slew*` | 22,802 | `buf_1/2/4`, `clkbuf_1/2` |

Every single max-fanout repair buffer is `dlyb_1`, a **delay** cell. Wire-length and slew
repair pick sensible buffers; fanout repair picks the one cell in the library that exists to
add delay on purpose. The reason is a rounding error. OpenROAD's fanout repair uses the
lowest-drive buffer in the library, and drive resistance computed off the `tt_025C_3v30`
timing arcs is 13.52 ns/pF for `dlyb_1` against 13.48 for `buf_1` and `clkbuf_1`. A 0.3%
difference selects a cell that costs **2.67x the area** (35.12 against 13.17) and **1.02 ns
more intrinsic delay per stage** (1.229 ns against 0.210 ns). Synthesis emits zero `dlyb`
instances; all 16,595 in the design arrive in this one step.

**What that does to a net.** The worst case is
`i_dmi_jtag.i_dmi_cdc.i_cdc_req.i_src.clk_i`, the JTAG TCK domain's source clock, and its
matching `rst_ni`. Between them they absorb 6,479 buffers, 10% of everything the step
inserted. Walking the TCK tree level by level: 258 original loads are reached through **3,259
inserted buffers across 29 levels**, of which 3,247 are `dlyb_1`. A balanced tree at the
enforced fanout limit of 10 needs about 30 buffers, so this is roughly 100x over. The tree
also does not respect its own constraint, carrying up to 30 loads on internal nets. The shape
says cascade: each weak, slow `dlyb_1` re-violates slew at its own output and spawns another
level. At 1.02 ns of avoidable intrinsic delay per stage, 29 levels is about 30 ns of pure
inserted delay on one path, 18% of the whole 166.67 ns budget.

**The RTL's own broadcast fanout is real but second.** The top offender is the SoC reset,
which appears in both polarities: `_050217_` (4,222 loads, driven by
`or2_1` from `i_dm_top.i_dm_csrs.dmcontrol_q[1]`, the debug module's ndmreset, OR'd with
`apb_soc_ctrl`'s soft reset) and `apb_fll_if_i.HRESETn` (4,256 loads, its inversion). About
8,500 sinks on one logical reset, charged 4,124 buffers between them. After that the list
falls off fast: the two `spim_gen[*]` synchroniser resets at 1,578 and 1,579 loads, an
`sdio_gen[0]` reset at 865, `rstgen_bypass.init_no` at 801. `clk_PAD2CORE` tops the raw
fanout table at 5,773 but is the real clock, which CTS handles.

**Cost-ordered shortlist.**

1. Keep `dlyb_*` out of the resizer's hands. One config line, no RTL change, no design change.
   It targets 25.5% of all inserted buffers directly and probably far more indirectly, since
   the cascade above is what turns a 30-buffer tree into a 3,259-buffer one. The obvious
   objection is hold fixing, which legitimately wants delay cells, and the measurement answers
   it: `ResizerTimingPostCTS` *removed* `dlyb` instances (16,595 down to 16,539) rather than
   adding any, and the 73 `delaynet_*_clk_PAD` hold-fix nets are driven by `clkbuf_8` and
   `clkbuf_16`, not by delay cells. Nothing in this design is using `dlyb` for what it is for.
2. Constrain the JTAG TCK domain. `flow/chip_top.sdc` already documents that `jtag_tck` and
   `ref_clk_div40` are deliberately undeclared, and that the cost is losing a balanced tree
   while `repair_design` buffers them as ordinary high-fanout nets. This is the measurement of
   that cost: 6,479 buffers and a 29-level mesh where a CTS tree belongs. The reason they were
   left out (each extra clock is another chance to hit the CTS crash) is gone now that ticket
   26's patched OpenROAD exists. Deferred until lever 1 is measured, because it needs
   `set_clock_groups` alongside it and because two changes at once would spoil the A/B.
3. Distribute the SoC reset in RTL. This is the expensive one, a real design change with real
   verification cost, and it is what the ticket was originally written to chase. It stays third
   until the two flow-level levers above are measured, since 8,500 sinks buffered by a sensible
   cell is a very different problem from 8,500 sinks buffered by a delay cell.

Applied lever 1 only, as `EXTRA_EXCLUDED_CELLS` in `flow/config.yaml`. The A/B is the
iteration-0 detailed-routing violation count against the recorded 512,491.
