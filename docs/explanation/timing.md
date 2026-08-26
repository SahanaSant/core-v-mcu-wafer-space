# Timing closure

The design closes at 5 MHz with zero setup and zero hold violations at all nine corners. It
took three clock targets and two failed hold strategies to get there, and both lessons
generalise well beyond this design.

## Getting the clock target right

The original budget was 100 ns / 10 MHz, picked before there was anything routed to measure
against. Three post-route STA results at `ss_125C_3v00`, each from a real run:

| Period | Frequency | WNS | Setup violations |
| --- | --- | ---: | ---: |
| 100 ns | 10 MHz | -28.59 ns | 9,127 |
| 166.67 ns | 6 MHz | -7.72 ns | 162 |
| 200 ns | 5 MHz | +25.61 ns | 0 |

At 100 ns, OpenROAD's own resizer gave up: `[RSZ-0062] Unable to repair all setup violations`
against every one of its 6,274 violating endpoints. It was not leaving slack on the table, it
was chasing a target the design could not reach.

At 166.67 ns, every one of the 162 remaining violations launches from the **same flop**:
`instr_rdata_i[17]` in the CV32E40P decoder, fanning out to 162 endpoints. That path runs
from the decoder, through the ID stage's controller, and across the die into the SoC
interconnect's AXI crossbar arbiter — 176 stages, 169.6 ns of data path. Attributing the
delay by cell class splits it almost exactly in half: 85.4 ns across 71 real logic stages and
84.2 ns across 80 resizer repair buffers, averaging 1.05 ns per buffer.

Those buffers are not waste. The path is physically long, and a long wire at 3.0 V and 125 °C
genuinely needs them. Closing this at 6 MHz would mean pipelining the decode-to-interconnect
request path, which is new microarchitecture, not a flow setting.

The third number is arithmetic on a fixed netlist rather than a fresh run, and it is exact
for that reason: arrival time is a property of the routed netlist (188.56 ns), and only the
required time moves with the period, so +33.33 ns of period is +33.33 ns of slack. A
re-harden at 200 ns can only improve on it, because the resizer then chases a reachable
target and inserts fewer buffers.

5 MHz costs nothing this project is trying to buy. The clock is external, so the frequency is
a crystal choice on the bring-up board. It is at least as ordinary a crystal to source, and
it divides more cleanly: 1e9 / 5e6 is exactly 200 ns, where 6 MHz left the cocotb driver
truncating 166.67 to 166.

### Which stages actually respond to the clock

Measured across back-to-back runs with byte-identical configuration:

| Step | Clock-dependent? | at 10 MHz | at 6 MHz |
| --- | --- | --- | --- |
| `RepairDesignPostGPL` | **No** — this is electrical DRC repair, not setup repair | 62-64 min, 64,734 buffers | 63 min, 64,734 buffers |
| `ResizerTimingPostCTS` | **Yes** | 40-42 min, 6,274 endpoints, ends `RSZ-0062` | 9.5 min, 1,203 endpoints, closes |

So do not expect a lower clock to shrink the whole run. `RepairDesignPostGPL`'s cost is
structural — it comes from the RTL's own unbuffered fanout — and stays fixed regardless of
frequency.

## Hold: the stage matters more than the margin

This is the more generalisable lesson.

The Chip flow resolves `RUN_POST_GRT_RESIZER_TIMING` to False by default, so hold is repaired
exactly once, in `ResizerTimingPostCTS`, against **estimated** parasitics — and nothing
revisits it after RCX extracts the real ones. The gap between the two is measurable: a design
fixed to +0.35 ns post-CTS came out of routing with 88 violations at up to -0.359 ns.

The obvious response is to buy more margin at that same stage. **It was tried at 1.0 ns and
made hold dramatically worse.**

| | margin 0.35 | margin 1.0 |
| --- | --- | --- |
| hold WNS | -0.359 ns | **-9.616 ns** |
| hold violations | 88 | 382 |
| setup WNS | +25.6 (predicted) | +0.666 ns |
| hold buffers inserted | 1,333 | **33,152** |
| violating endpoints found | 1,394 | 14,640 |

Both columns moved the wrong way, for one reason. A buffer is about 1 ns in this library at
these corners, so a 1 ns margin costs one to two buffers per path — and applied blind across
14,640 endpoints that is a 16% instance-count increase, 210,182 to 242,358.

What that cost: the added buffers sit in data paths, so they delayed every path they touched
and ate essentially the whole setup margin the 200 ns period had just bought. And the
placement churn needed to fit them (detailed placement mirrored 83,015 instances) moved clock
sinks, which is what actually broke hold. The surviving violations are not ordinary short
paths; they are paths with about **18 ns of clock skew** between the main tree and the uDMA
peripheral sub-trees. The worst launches at 5.1 ns off `clkbuf_leaf_3_clk_PAD2CORE` and
captures at 22.96 ns inside a uDMA SPI end-of-transfer register.

No amount of data-path delay fixes a skew problem, which is why buying more of it made things
worse.

The fix was to repair at the right stage instead. Turning `RUN_POST_GRT_RESIZER_TIMING` on
runs the repair after global routing, when parasitics are close to final, so it lands on the
paths that are actually violating rather than on 14,640 that mostly are not. At a margin of
0.3 it took register-to-register hold violations from 57 to 19 **while inserting a single
buffer**. The margin then went to 0.6, which covers the remaining violations (all inside
0.204 ns) with room to spare.

Same goal, right stage: 33,152 buffers and a worse result, against one buffer and a better
one.

## Classify violations before touching any margin

A headline violation count conflates unrelated problems. One run's "66 hold violations" was
28 from asynchronous input pads and 14 real register-to-register paths, which need opposite
treatments.

Hold checks on asynchronous inputs that are synchronised in RTL are fictitious, and worse
than harmless. With `set_input_delay -min 0` against a clock network of zero propagated delay
the requirement cannot be satisfied at any corner, so the resizer chases it without bound:
`bidir_PAD[27]` accumulated **eight series hold buffers** and still reported -0.416 ns. Every
one of those buffers is area and leakage spent on nothing.

`flow/chip_top.sdc` therefore declares `set_false_path -hold` on `bidir_PAD` and `rst_n_PAD`.
Both are genuinely asynchronous to `clk_PAD` and both are synchronised in RTL before anything
acts on them — `apb_gpio` shifts `gpio_in` through `r_gpio_sync0`, `r_gpio_sync1` and
`r_gpio_in`, and `rst_n` reaches the SoC through `rstgen_bypass`, whose `synch_regs_q` chain
asserts asynchronously and releases synchronously. Those synchronisers are exactly what makes
the pad-to-first-flop arrival time not matter, which is precisely what a hold check on it
would be asserting.

That is a design fact the tool cannot infer, stated in the only place it can be stated. The
line worth holding is between stating such a fact (legitimate signoff practice) and relaxing
uncertainty so that a real violation disappears (hiding risk). The scope is `-hold` only, so
the setup constraints stay exactly as they were and the ports are not left unconstrained.

The other asynchronous inputs (`input_PAD`, carrying `stm_i`, the JTAG inputs and the spares)
very likely deserve the same treatment. They are not violating and their consumers have not
been traced, so they are left alone rather than false-pathed on an assumption.

## Change one variable per run

A run here is hours. Moving the clock period and the hold margin together once made a
seven-hour run's result unattributable, and re-running was the only remedy.

## What the pre-layout `make sta` number is worth

`report_checks -group_path_count 1` ranks by slack, which pre-layout means by raw arrival
time. Every net has zero parasitics and nothing is buffered, so arrival is dominated by
whichever minimum-drive cell happens to drive a large net, not by how many gates the path
passes through. The path that wins that ranking can flip identity by 2.4x under an RTL change
that touches neither block: the same netlist reported a 35-stage AXI crossbar path in one
measurement and a 90-stage CV32E40P path in the next.

So `sta.sh` asks OpenSTA for the 300 worst-slack candidates in one query and
`path_summary.py` reports whichever is actually deepest, with its rank among the 300 printed
alongside so a candidate that only barely made the window is visible as such. N=50, 300 and
1000 all converge on the same path.

Even then, read the output as **logic depth, not as a frequency**. The delay floor it reports
assumes every stage gets its Liberty-table delay with no wire RC, so real silicon cannot do
better, only worse. It is useful for tracking whether an RTL change moved the critical path,
and useless for predicting closure.

## Residual gaps

Max slew (457) and max cap (291) are not closed. LibreLane defers them as warnings and the
precheck does not examine them. They live in the repair buffering, and many likely sit on
macro pins whose Liberty is uncharacterised — so tightening against those numbers would
optimise against fiction. See [known-issues.md](known-issues.md).
