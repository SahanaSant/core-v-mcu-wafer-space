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

### 2026-08-22: first A/B, and the exclusion was too narrow

`RUN_2026-08-22_14-38-59`, `EXTRA_EXCLUDED_CELLS: [dlyb_*]`, stopped at
`OpenROAD.RepairDesignPostGPL`:

```
[INFO RSZ-0034] Found 18052 slew violations.
[INFO RSZ-0035] Found 2040 fanout violations.
[INFO RSZ-0036] Found 1326 capacitance violations.
[INFO RSZ-0038] Inserted 66240 buffers in 10022 nets.
```

66,240 against the previous run's 64,734, so the count went **up**. Attribution shows why:
every one of the 17,002 `fanout*` instances is now a `dlyc_1`. Excluding one delay family
promoted the next. This library has four of them, and sorted by drive resistance off the
`tt_025C_3v30` arcs they all sit at or above `buf_1`:

| cell | drive R (ns/pF) | intrinsic (ns) | area |
| --- | --- | --- | --- |
| `dlyc_1` | 13.53 | 2.284 | 54.88 |
| `dlyd_1` | 13.53 | 3.299 | 74.64 |
| `dlyb_1` | 13.52 | 1.229 | 35.12 |
| `dlya_1` | 13.48 | 0.528 | 24.15 |
| `buf_1` | 13.48 | 0.210 | 13.17 |
| `clkbuf_1` | 13.48 | 0.204 | 13.17 |

Six cells inside 0.4% of each other on the one number the selection uses, spanning 16x on
intrinsic delay and 5.7x on area. Note also that `dlyc_1` and `dlyd_1` rank *above* `dlyb_1`
here while the unexcluded run still picked `dlyb_1`, so drive resistance is not the whole
tie-break; what is not in doubt is the observed promotion when `dlyb_*` was removed.

**This result supports the cascade reading rather than undermining it.** The substitute cell
is slower than the one it replaced, 2.284 ns against 1.229 ns, and the buffer count rose by
1,506. A slower repair buffer buying more repair buffers is exactly what the JTAG TCK tree's
29 levels said was happening. The prediction is that a cell an order of magnitude faster
should move it the other way.

Widened to `dly*`, which leaves `buf_1`/`clkbuf_1` as the lowest-drive buffers, and re-running
the same stop-at-design-repair A/B.

One confound to record rather than hide: this run's netlist is 91,657 instances against the
previous 90,651, because it is the first to carry ticket 31's `L2_BANK_SIZE` fix, which widens
`L2_AWIDTH_NOAL` from 13 to 14 bits and with it every uDMA start-address register and counter.
The slew, fanout and capacitance violation counts moved by well under a percent, so the
netlist change is not what moved the buffer count, but the two runs are not bit-identical
inputs and the next comparison is against 66,240 on the identical netlist rather than against
the original 64,734.

### 2026-08-22: the cell was never the problem. Fanout repair is degenerate

`RUN_2026-08-22_16-12-09`, `EXTRA_EXCLUDED_CELLS: [dly*]`, same stop point:

```
[INFO RSZ-0034] Found 18051 slew violations.
[INFO RSZ-0035] Found 2040 fanout violations.
[INFO RSZ-0038] Inserted 66377 buffers in 10022 nets.
```

`buf_1` is now the fanout cell, as intended. The count did not move: 66,377 against 66,240,
and the `fanout*` instance count is **17,002 in both runs**, exactly. The JTAG TCK tree is
3,377 buffers with `buf_1` and was 3,377 with `dlyc_1`. Three different cells, three identical
structures. **The cascade hypothesis is dead**: cell speed sets area and delay, not tree size.

Tracing one path from the pad net to its deepest sink shows what fanout repair is actually
building. Fanout in brackets:

```
[   4]  (pad net)     i_dmi_jtag.i_dmi_cdc.i_cdc_req.i_src.clk_i
[   9]  buf_8         wire66377
[  29]  buf_8         max_cap66375
[   8]  buf_8         max_cap66374
[  24]  buf_8         max_cap66373
[  24]  buf_8         max_cap66372
[  24]  clkbuf_8      max_cap66371
[   1]  buf_1         fanout66319
[   1]  buf_1         fanout65898
...  eighteen more, every one of them fanout 1 ...
[   1]  buf_1         fanout64277
```

Across the 3,378 nets in that tree the **mean fanout is 1.1** and the deepest sink sits 24 nets
from the root. This is not a fanout tree. It is 258 private chains of single-load buffers,
thirteen to eighteen deep, hanging off one strongly driven pad net (the `in_c` pad's own
Liberty gives it 1.19 ns/pF, eleven times stronger than `buf_1`, so a weak source is not the
explanation either).

**And the constraint is not even met.** The `max_cap*` buffers higher up the same path carry
fanout 24 to 29 against a limit of 10. So the design pays 17,002 buffers for a limit the
result does not respect.

That reframes the ticket a third time. The lever is the constraint itself, not the cell and
not the RTL:

| `MAX_FANOUT_CONSTRAINT` | violating nets | excess loads |
| --- | --- | --- |
| 10 (PDK default) | 2,058 | 70,656 |
| 20 | 1,181 | 54,896 |
| 40 | 413 | 38,483 |
| 64 | 148 | 30,545 |
| 100 | 59 | 27,662 |

Set to 40, an 80% cut in violating nets, leaving `MAX_TRANSITION` and `MAX_CAPACITANCE` to
constrain the genuinely wide nets. Those two matter physically where a fanout count does not,
and their repair demonstrably works: the `wire*` and `load_slew*` buffers build real trees at
fanout 8 to 29 rather than chains.

Keeping the `dly*` exclusion regardless. It does not change the buffer count, but at identical
count it swaps a 54.88-area, 2.284 ns cell for a 13.17-area, 0.210 ns one across 17,002
instances, which is real area and real delay off the critical paths whatever happens to
routability.

### 2026-08-22: `MAX_FANOUT_CONSTRAINT: 40` cuts 28.5%, and the pad table names the next lever

`RUN_2026-08-22_17-27-47`, `dly*` excluded and the fanout limit at 40:

```
[INFO RSZ-0034] Found 18260 slew violations.
[INFO RSZ-0035] Found 400 fanout violations.
[INFO RSZ-0036] Found 2754 capacitance violations.
[INFO RSZ-0038] Inserted 47478 buffers in 10035 nets.
```

47,478 against 66,377, so **18,899 fewer buffers, a 28.5% cut**, and the design lands at
209,852 instances instead of 228,751. Fanout violations came in at 400 against the 413 the
static prediction gave. Capacitance violations roughly doubled, 1,327 to 2,754, which is the
expected trade: fewer fanout buffers means more load per driver, and cap repair is the checker
that should be catching that because it is the one measuring something physical.

**It did not touch the pad-driven nets.** JTAG TCK is still 3,377 buffers, its neighbour still
3,352, `stm_i` still 739. Charging every buffer to the pad net it descends from:

| buffers | fanout | per load | pad cell | instance |
| --- | --- | --- | --- | --- |
| 3,377 | 258 | 13.1 | `in_c` | `inputs[0].pad` |
| 3,352 | 257 | 13.0 | `in_c` | `inputs[3].pad` |
| 739 | 54 | 13.7 | `in_c` | `inputs[4].pad` |
| 81 | 13 | 6.2 | `in_c` | `inputs[1].pad` |
| 8 | 5 | 1.6 | `in_c` | `rst_n_pad` |
| **0** | **5,780** | **0.0** | `in_s` | **`clk_pad`** |

The last row is the whole answer. `clk_pad` drives **5,780** loads, twenty-two times the JTAG
pad's 258, and takes **zero** repair buffers, because `flow/chip_top.sdc` puts a `create_clock`
on it and `repair_design` leaves clock nets to CTS. The JTAG pad has no `create_clock`, so it
is repaired as data and costs 3,377 buffers to reach a twenty-second of the loads. Nothing
else distinguishes the two rows: same pad family, same die, same run.

So the SDC's own note was right about the mechanism and understated the price. It says the
unconstrained domains "are still buffered by `repair_design` as ordinary high-fanout nets" and
that the cost is losing a balanced tree. The cost is 7% of every buffer in the design on one
net, plus whatever the neighbouring 3,352 turn out to be worth once the domain has a clock at
all. This is no longer a judgement call about whether an extra CTS tree is worth the crash
risk: ticket 26's patched OpenROAD removes the crash, and this run is already using it.

Holding the SDC change until the current route reports, so the 28.5% cut gets a clean reading
against the recorded 512,491 iteration-0 violations before a second variable moves.

### 2026-08-22: the route converges. The premise of this ticket was wrong

`RUN_2026-08-22_17-27-47` carried through to detailed routing, patched OpenROAD image, same
`-or_seed 42`, so this is the A/B the Notes asked for.

**Global routing.** One pass, not the three the previous run needed, and it disabled NDR on
two `delaynet_*` nets rather than grinding through them. Total wirelength **20,850,118 um to
14,035,366 um, down 32.7%**. That is the routability result: congestion is wire demand against
supply, and a third of the demand is gone.

**Detailed routing**, against the recorded baseline:

| iteration | before | now |
| --- | --- | --- |
| 0 | 512,491 | **61,300** |
| 1 | | 22,535 |
| 2 | | 21,079 |
| 3 | ~326,000 | **1,433** |

The old route spent three iterations getting from 512K to 326K and then flattened, gaining
under 1% per iteration at one to three hours each, which is what convinced ticket 29 the step
could not finish. This one is at 1,433 by iteration 3.

**So the ticket's premise was wrong, and worth stating plainly.** The title says "reduce
broadcast fanout", and the Question argues from 64,734 emergency buffers and 26.6% placement
density that the congestion is structural to the RTL's broadcast and control fanout, fixable
only by pipelining or buffering signals in RTL. No RTL changed. The SoC reset still drives
about 8,500 sinks in two polarities. What changed is two lines of flow configuration, and the
fanout constraint was not a victim of the RTL's fanout, it was the cause of the congestion:

- `MAX_FANOUT_CONSTRAINT` 10 to 40. This is the one that matters. Its repair degenerates into
  single-load buffer chains averaging 1.1 fanout, thirteen to eighteen deep, and the netlist it
  produces does not satisfy the limit anyway.
- `EXTRA_EXCLUDED_CELLS: dly*`. Neutral on count, but 17,002 instances at 13.17 area and
  0.210 ns instead of 54.88 and 2.284 ns.

The 64,734 buffers were real and the density measurement was real. The inference from them to
"the RTL is at fault" is what did not hold, and it held up ticket 29 and everything behind it
for two days. The lesson worth keeping is that the buffers a resizer inserts are evidence
about the resizer's constraints first and about the netlist second.

Still outstanding and now measurable on a converging route: the JTAG `create_clock`, worth
3,377 buffers on one net by the pad table above.
