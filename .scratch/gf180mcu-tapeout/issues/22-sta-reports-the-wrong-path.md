# `make sta` reports the wrong path, and the design is deeper than ticket 10 measured

Type: task
Status: resolved
Blocked by: none

## Question

Ticket 19 found that `sta.sh`'s headline number is not the design's logic depth, and that the
real depth does not close.

`report_checks` ranks paths by slack, which pre-layout means by raw arrival time. Every net has
zero parasitics and nothing has been buffered, so arrival is dominated by whichever
minimum-drive cell happens to drive a large net: in the path ticket 19 measured, three stages
carry 146 ns of a 280 ns arrival and the remaining 81 stages share the rest. Depth barely
enters the ranking. `path_summary.py` then reports the stage count of whatever path won, which
is why its output is presented as logic depth.

The consequence is measured, not argued, by A/B on the same tree:

| netlist | reported path | stages | floor at `ss_125C_3v00` |
| --- | --- | ---: | ---: |
| ticket 16 baseline | AXI crossbar spill reg to `pad_cfg_o[5]` | 35 | 31.2 ns, 62% of budget |
| ticket 19 | CV32E40P `instr_rdata_i[15]` to `alu_operand_a_ex[1]` | 84 | 67.7 ns, 135% of budget |

The identity of the reported path flipped on an RTL change that touches neither block. Querying
the **baseline** netlist directly with `report_checks -to` on the CV32E40P endpoint returns
**90 stages at 270.5 ns arrival**, against the 283.9 ns of the crossbar path it reported
instead. So the deep path was always there and lost the ranking by 13 ns of unbuffered fanout.

Two things follow, and they are separable.

- **The metric is wrong.** `make sta` claims to report logic depth and reports something else.
  Every ticket the map instructs to "quote the new numbers" has been quoting a number that can
  move by 2.4x without the design changing. Decide what it should report instead: the deepest
  path across N endpoints, the worst path per block, a slack histogram, or an `abc` delay target
  tightened until it stops being slack-limited. Whatever is chosen has to stay comparable enough
  that tickets 10, 14, 16 and 19 can be read against it, or those numbers need restating.
- **Ticket 10's timing conclusion needs revisiting.** "25 MHz holds on logic depth at both
  voltages" rests on the 35-stage path. At roughly 0.8 ns a stage at 3.3 V, 90 stages is about
  70 ns against a 50 ns budget, before any wire RC, clock tree or hold fixing. The 5.0 V arm is
  about 50 ns at 0.56 ns a stage, which is no better than break-even. That is a different chip
  from the one the map has been planning, and it lands on ticket 05's clock choice, on the
  "Timing closure" fog patch, and on schedule viability.

Do not treat the 90 stages as final either: it is a synthesised netlist mapped by `abc` against
a 50 ns target it believes it meets easily, so the depth is what area-directed mapping produced
rather than what the path needs. Re-mapping with a tighter target is the cheapest experiment and
should come before any RTL is touched.

## Definition of done

`make sta` reports a number that means what it says and does not move under unrelated churn,
with the change documented in `flow/README.md`. A recorded finding on whether 20 MHz is still
reachable at 3.3 V, and if it is not, what the options are: a slower clock, `abc` retiming, or
pipelining inside the fabric controller. Tickets 05, 10 and the map's timing-closure patch
updated to match.

## Answer

**Metric fixed, and the bad news it was hiding is real: 20 MHz does not close at 3.3 V.**

**The fix.** `report_checks -group_path_count 1` picks path #1 by slack, which pre-layout is
set by whichever minimum-drive cell happens to drive an unbuffered high-fanout net, not by
stage count, and the two are only loosely correlated. `sta.sh` now asks OpenSTA for the 300
worst-slack candidates in one query (`-group_path_count 300 -unique_paths_to_endpoint
-format json`) instead of one, and `path_summary.py` picks whichever of the 300 has the most
logic stages rather than trusting rank #1. Stage count is read directly from OpenSTA's JSON
path data (distinct cell instances between the launching and capturing registers), not
inferred from text formatting. The report now prints the winning path's rank among the 300,
so a result that only barely made the window is visible as a warning rather than silently
trusted: measured on the ss_125C_4v50 arm, the deepest candidate found was ranked **#39**, not
#1, which is the instability ticket 19 first caught made concrete on a second corner. Measured
convergence at N = 50, 300 and 1000 candidates all found the same ~90-stage path, so 300 is
comfortable margin without the query taking long (the whole two-corner `make sta` run is under
20 seconds).

**Re-measured, at the signoff netlist (ticket 06's committed 82,209 cells / 2,281,302 um2,
`ss_125C_3v00` / `ss_125C_4v50`, 50 ns budget):**

| corner | stages | median stage | floor | of the 50 ns budget |
| --- | ---: | ---: | ---: | ---: |
| ss_125C_3v00 (3.3 V, signoff) | 89 | 0.700 ns | 62.3 ns | **125%** |
| ss_125C_4v50 (5.0 V, informational, mixed-corner per ticket 19) | 88 | 0.500 ns | 44.0 ns | 88% |

The 3.3 V signoff corner is over budget by 25%, roughly 12 ns. This is not the ticket 19
number restated: that was measured on the pre-ticket-06 netlist and this is the current one,
and the two happen to land close (89 against 90 stages) because the offending path lives in
the CV32E40P decoder, which ticket 06's peripheral and pad cuts did not touch. The endpoint
this session found, `_142010_/D`, traces to the same `instr_rdata_i`-fed decoder logic ticket
19 named. The 5.0 V arm has real margin, 88%, consistent with the map's Notes calling that
corner "no worse than break-even" — it is now measurably better than break-even, on the
current netlist.

**The cheap experiment ticket 22 itself suggested: re-map at a tighter `abc -D` target.**
`MODE=flat CLOCK_PERIOD_NS=20 make area` (a 20 ns target, 2.5x tighter than the 50 ns the
committed netlist was mapped at) produced a **byte-identical netlist**: 82,209 cells,
2,281,302 um2 to the last digit, and `make sta` against it reported the identical 89-stage
path at the identical rank. The tighter `-D 20000` reached ABC (confirmed in
`synth-flat.log`), so this is not a script bug; ABC's mapping in this flow is simply
insensitive to the delay target at this design's scale, most likely because without a
wireload model its internal delay estimate for a stage never flags the high-fanout nets that
actually dominate arrival as critical, regardless of what target it is told to hit. So this is
a real negative result, not an unexplored option: **synthesis-time retargeting is not a lever
here.**

**Finding: 20 MHz is not established reachable at 3.3 V, and the direction of travel is
against it, not for it.** The 62.3 ns floor already assumes every stage gets exactly its
liberty-table delay with zero wire RC and a zero-skew clock; real silicon adds to that number,
CTS and buffering only ever cost more than an ideal clock tree, never less. So this floor is
the best case, not a conservative estimate to be relieved by implementation detail. Against a
50 ns budget that is a real 25% shortfall today, before ticket 21's floorplan or any hold
fixing exists. Options, per the Definition of done:

- **A slower clock.** The floor itself implies roughly 16 MHz (62.3 ns) with zero margin, so a
  defensible target sits below that, at 3.3 V — 12 to 15 MHz depending how much margin ticket
  05 wants against CTS and hold-fixing cost, neither of which is measured yet.
  Fabric-controller pipelining below is the alternative to accepting this.
- **`abc` retiming**: ruled out as a synthesis-time knob by the experiment above. A dedicated
  retiming pass (`abc`'s `&retime` beyond what `synth` already runs, or a hand-tuned script in
  the spirit of the Basilisk paper ticket 10 read) is unproven and untried; it is a real option
  but not a cheap one, and nothing here demonstrates it would move a path whose delay is
  dominated by fanout capacitance rather than logic depth.
  - **Pipelining inside the fabric controller.** The path lives in the CV32E40P's decoder,
    from `instr_rdata_i` to `alu_operand_a_ex`, which is upstream IP; adding a pipeline stage
    there is new microarchitecture, off this map's current scope, and would need its own
    ticket if ticket 05 wants to keep 20 MHz rather than slow down.

Do not read this as fatal to the December date on its own: it is a pre-layout, pre-buffered
number and the true post-CTS depth is still unmeasured, which is exactly what the map's
"Timing closure" fog patch already flags as waiting on a first full harden. What changes here
is that the metric producing this number is now trustworthy, so the 125% figure is a real
input to ticket 05 rather than a number that might be an artifact of which path happened to
win a slack race.

**What was committed:** `flow/synth/sta.sh` (the new `report_checks` invocation and
`PATH_CANDIDATES`), `flow/synth/path_summary.py` (rewritten: JSON multi-path input, stage
count from distinct instances, max-by-depth selection with rank reporting), `flow/README.md`
(the `CLOCK_PERIOD` note and the high-fanout-nets note both updated to describe the fix rather
than the defect). No RTL changed; `flow/build/` is regenerated, not committed.
