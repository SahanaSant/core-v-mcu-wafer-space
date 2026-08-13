# `make sta` reports the wrong path, and the design is deeper than ticket 10 measured

Type: task
Status: open
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

<!-- filled on resolution -->
