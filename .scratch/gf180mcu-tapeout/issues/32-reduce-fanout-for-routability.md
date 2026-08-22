# Reduce broadcast fanout so detailed routing can converge

Type: grilling
Status: open
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
