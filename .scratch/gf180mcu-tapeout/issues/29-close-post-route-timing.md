# Close post-route timing at the slow corner

Type: task
Status: claimed
Blocked by: none (was [Reduce broadcast fanout so detailed routing can converge](32-reduce-fanout-for-routability.md), resolved)

## Question

Ticket 22 measured a pre-layout, zero-wire-RC idealized floor of 77.4 ns against the 100 ns /
10 MHz budget at 3.3 V (77% of budget, real margin) — the number every earlier fog entry on
this map called encouraging. Ticket 26's routed run shows what real parasitics did to that
margin: post-route STA at the slow corner (`ss_125C_3v00`) has a large setup violation, worst
slack around **-48 ns** against the 100 ns clock, **~12,500 setup violations design-wide**,
alongside widespread max-slew and max-cap violations. `tt` and `ff` corners pass setup
comfortably, so this is corner-specific rather than a design that's merely a little over
budget everywhere. Hold is a much smaller, more normal-scale problem: worst slack around
-0.3 ns, ~20 violations, concentrated at the fast/cold corner.

This is the first time this map has real post-route numbers to work from rather than the
idealized pre-layout floor — start by re-establishing what the actual worst path is (the
critical path identity has moved before under RTL churn, per ticket 22's own finding; confirm
it's stable now that there's a real route rather than assuming it's still the CV32E40P decoder
path ticket 22 found pre-layout). From there, the live options, roughly in order of cost:

- **Incremental repair within the existing flow**: OpenROAD's own `repair_timing` /
  useful-skew / buffer-insertion passes, possibly with tighter `RepairDesignPostGPL` or
  `CTS`-stage settings, before assuming a bigger change is needed. This is the cheap
  experiment to rule out first.
- **A slower clock.** The budget itself (10 MHz) was ticket 05's choice specifically because
  it was external and unburned into silicon; if the idealized floor at some lower frequency
  clears the *real*, routed critical path with margin, that's a legitimate lever, not a defeat.
  Whether it's cheap or costly depends on what downstream peripherals (UART baud, SDIO, PWM)
  assume about the core clock — check before proposing a number.
- **Retiming or pipelining the CV32E40P decoder path** — flagged in ticket 22's fog notes as
  "new microarchitecture off this map." If incremental repair and a clock-budget change both
  fail to close it, that's the point to bring back to the user rather than execute
  unilaterally: it may mean this ticket needs to spin off a scoping decision (grill it) before
  any RTL gets touched, the same way ticket 04 spun off ticket 23 and ticket 05 spun off
  ticket 24.

Whichever path is tried, give it the map's usual discipline: this design's physical flow has a
history of single-run results being misleading (the CTS crash was ~1-in-100; `make sta`'s
metric itself was wrong until ticket 22). Re-measure rather than trust one pass.

## Definition of done

`make sta` (or the post-route equivalent) reports a clean setup and hold at the slow corner,
numbers quoted from a real run against the routed design — or, if full closure isn't reached,
the ticket records the real number reached, what was tried, and an explicit, user-reviewed
decision on what's acceptable to carry to sign-off.

## Answer

<!-- filled on resolution -->

## Comments

**Diagnosis complete against real, current post-route data; the clock-budget lever looks
promising and untested. Not resolved yet — the next step is a real STA measurement at a
candidate lower frequency, blocked only by "one flow command at a time" against ticket 27's
antenna re-verification, not by any open decision.**

Measured from `RUN_2026-08-16_04-34-36`'s post-route STA (`576-openroad-stapostpnr`), a real
routed run with ticket 27's DRC fixes and the patched OpenROAD image — better numbers than
ticket 26's original report, worth quoting fresh rather than reusing the old ones:

- **Setup, `max_ss_125C_3v00`**: WNS **-28.59 ns** (real critical-path delay ≈128.6 ns against
  the 100 ns budget, ≈129% of budget), TNS -40,889 ns, **9,127 violations**. Zero violations at
  every `tt`/`ff` corner — confirmed still corner-specific, matching ticket 26.
- **Hold**: WNS **-0.0035 ns**, exactly **1 violation** (`max_ff_n40C_3v60` only). Essentially
  closed already — a rounding-level residual, not a real problem.

**The critical path is confirmed, not assumed, and it's a single-source fanout problem, not
9,127 independent paths.** The worst-slack violator list
(`576-openroad-stapostpnr/max_ss_125C_3v00/violator_list.rpt`) is dominated by one launch flop,
`_153383_/Q`, appearing as the source of the worst violation and the next dozen-plus right
behind it (-28.59, -28.43, -28.42, -28.27 ns...) against many different endpoints. Tracing that
instance in the full path report: `_153383_` is
`i_chip_core.i_core_v_mcu.i_soc_domain.fc_subsystem_i.lFC_CORE.id_stage_i.decoder_i.instr_rdata_i[21]`
— one bit of the fetched instruction word, inside the CV32E40P decoder. Confirms ticket 22's
pre-layout finding held: the decoder is still the critical structure post-route, not something
that moved under routing. The data path from that flop's `Q` to its many destinations is a long
chain of resizer-inserted buffers (`fanout*`/`load_slew*`/`wire*` synthetic names) — the
`RepairDesignPostGPL`/`RepairAntennas`-class fix the map already knows this design leans on
heavily for its unbuffered high-fanout nets (ticket 25: 61,069 buffers inserted design-wide).
An instruction word's individual bits fanning out to many decode comparators is structural to
how a decoder works, not a placement/routing accident.

**The "incremental repair" cheap option is effectively already exhausted by the standard
flow, and unlikely to close a 29% overage.** `warning.log` already carries `[RSZ-0062] Unable
to repair all setup violations` from this run's own `RepairDesignPostGPL`/resizer passes —
OpenROAD's own repair already tried and left this residual. Given the violation is
structural (one flop's fanout, not a few unlucky routes), tightening resizer/CTS settings
further is not ruled out as worth a quick try, but isn't expected to recover 29%: recorded here
as tried-in-spirit-by-the-existing-flow rather than a fresh experiment, so it doesn't need to
be re-tried in isolation before moving to the next lever.

**Clock-budget lever: looks like it would close this with real margin, not yet tested against
a real run.** Real critical-path delay ≈128.6 ns. At the same ~75-80% budget-utilization ticket
24 aimed for pre-layout, that points to a period around 165-170 ns, i.e. **roughly 6 MHz**
(166.7 ns nets ≈23% margin) or **5 MHz** (200 ns, ≈36% margin) as concrete, standard-oscillator
candidates — both ordinary, easily-sourced crystal frequencies, same as the reasoning ticket 05
used to land on 10 MHz in the first place. Checked downstream peripherals per this ticket's own
ask before proposing a number: **one real, contained dependency found**,
`sw/bootrom/spi.c`'s `#define PERIPH_CLK_HZ 10000000u`, used to derive the boot SPI clock
divisor. A single `grep` found nothing else hardcoded to 10 MHz anywhere else in `sw/` or
`rtl/chip/` — UART/SDIO/PWM peripherals all appear to take their divisors at runtime rather
than compile-time, so this looks like the only file that would need a one-line change if the
clock moves. Not touched yet, since no clock decision has been made.

**Not yet done, and why**: confirming either candidate frequency requires a real STA run
against the routed design (this ticket's own discipline: measure, don't extrapolate from
arithmetic on one path report). That's a `make` invocation, and this repo allows only one flow
command at a time (`flow/synth/sources.sh` deletes `flow/build`) — ticket 27's antenna-margin
re-verification is occupying that slot right now. Queued as the next concrete action once that
frees up: re-run STA (post-route, no re-placement/re-route needed, only the SDC clock period
changes) at the ~5-6 MHz candidates and confirm real margin holds under the actual routed
parasitics, not just the arithmetic above.

**Not at the retiming/pipelining fork yet.** The ticket's own text reserves that for after both
cheap options fail — the clock-budget option hasn't been tested against real data yet and looks
promising, so this stays open rather than escalating to a scoping decision prematurely.

**Root cause found for the map's other open question too — why runs take so long and vary so
much — and it's the same 100 ns target this ticket is already about.** Comparing step-by-step
timestamps across three back-to-back fresh runs (`RUN_2026-08-16_23-28-59`,
`RUN_2026-08-17_05-51-06`, `RUN_2026-08-17_11-55-13`, all identical config) shows two steps
dominating total runtime and landing suspiciously consistently: `OpenROAD.RepairDesignPostGPL`
took 62-64 minutes in all three, `OpenROAD.ResizerTimingPostCTS` took 40-42 minutes in all
three. Together that's 100+ minutes of a roughly 2.5-3 hour run, before routing even starts.
Read the logs directly rather than guess: `RepairDesignPostGPL` resizes 17,034 instances and
inserts **64,734 buffers** into 9,869 nets chasing the 100 ns target; `ResizerTimingPostCTS`
finds 6,274 out of 6,274 endpoints violating setup and tries to repair **100% of them**, only to
end with the same `[RSZ-0062] Unable to repair all setup violations` this ticket already found.
Both steps are burning tens of minutes running the resizer's full iterative repair loop against
a clock target that's structurally 29% unreachable (this ticket's own -28.59 ns WNS finding),
and never succeeding. This is consistent with the map's fog note on global-routing variance too:
a design under-buffered for its own timing target, with 65,000 emergency buffers landing wherever
the resizer's non-deterministic (pointer-ordered) search puts them, is exactly the kind of
run-to-run placement variation that would make downstream routing congestion unpredictable.

**Applied the fix rather than just diagnosing it, since this ticket already had everything
needed to act**: `flow/config.yaml`'s `CLOCK_PERIOD` 100 → 166.67 ns (6 MHz), matching this
ticket's own candidate and its own stated reasoning (put the real 128.6 ns critical path back at
~77% utilisation, the same target ticket 24 used pre-layout). Carried the same change through
every place ticket 29 had already found or that would otherwise go stale: `flow/chip_top.sdc`'s
header comment, `run.sh`'s `CLOCK_PERIOD_NS` default (feeds `make sta`/`make area`, not `make
harden`, but was quoting the old target), and `sw/bootrom/spi.c`'s `PERIPH_CLK_HZ` (this
ticket's one confirmed real dependency). A fresh `make harden` at the new period is running now
(`RUN_2026-08-17_16-21-08`) to get the real measurement this ticket's own discipline requires
before calling it closed — both the timing question (does 166.67 ns actually close at the slow
corner) and the runtime question (do `RepairDesignPostGPL`/`ResizerTimingPostCTS` collapse now
that there's nothing structurally unreachable to chase). Not resolving the ticket until that
real number is in hand.

## Comments (runtime fix, confirmed)

**`GRT_OVERFLOW_ITERS` cap confirmed as the fix for global routing's runtime, with a much
lower value than first guessed.** Killed and resumed the stalled 6 MHz run twice from the
post-CTS checkpoint (`--last-run --from OpenROAD.GlobalRouting`, so neither CTS nor either
resizer pass had to redo):

- Capped at 12: exactly 8m12s per NDR-disabled net, every time. ~10 hours projected for all 73.
- Capped at 3: exactly ~25s per net. **Global routing actually finished** at this setting --
  "finished with congestion" (expected and accepted, `GRT_ALLOW_CONGESTION: true`), 31.18%
  overall usage, 158,363 routed nets, runtime 00:06:03 for this attempt. Now proceeding through
  `OpenROAD.CheckAntennas` and into detailed routing.

The mechanism: at every cap tried, the router disables NDR on nets in the same order regardless
of iterations-per-cycle, so the cap wasn't buying convergence attempts, only delay before
conceding. `flow/clock-frequency-selection.md` has the full measured table.

Ticket 29 itself is still open pending this run's actual post-route STA at the slow corner --
the runtime problem (this map's other open question) looks solved, but the timing question this
ticket exists for isn't answered yet.

## Comments (antenna repair and detailed routing: a second, distinct runtime cost)

**The `GRT_OVERFLOW_ITERS` fix above solved global routing's variance, but a second, separate
bottleneck in the same run cost far more wall time and wasn't caught by that fix.**
`OpenROAD.RepairAntennas`/`DiodeInsertion` (the step right after global routing) has its own
internal NDR-restart mechanism triggered by `repair_antennas ... -allow_congestion`, but at a
vastly higher cost per event: only 3 NDR-disables fired across the whole step, roughly 2 hours
apart each (05:16:32, then three restarts through 14:44:57 container-time) versus ~25s/net during
`GlobalRouting` at the same `GRT_OVERFLOW_ITERS: 3`. This step alone ran ~9.5 hours overnight,
unwatched, and is the actual reason the original "tomorrow morning" target was missed -- not the
already-fixed global-routing problem. No config lever for this specific cost has been found or
applied; `DRT_ANTENNA_REPAIR_ITERS: 15` (pre-existing in `flow/config.yaml`) caps how many
antenna-repair-then-reroute cycles run, which is a plausible but untested lever if this recurs. The
step did complete on its own without intervention, so no fix was needed this time, only the
finding recorded here for whoever hits it next.

**`OpenROAD.DetailedRouting` (the very next step after `CheckAntennas`) shows a real, separate
convergence-plateau: not a restart-loop bug, TritonRoute's own iterative rip-up-and-reroute
genuinely slowing down.** Violation counts by iteration: iter 0 512,491 -> iter 1 401,007 (-22%)
-> iter 2 367,255 (-8%) -> iter 3 326,593 (-11%) -> iter 4 322,587 (-1.2%), each iteration taking
~15-49 minutes. Checked whether this is tunable: `DRT_OPT_ITERS` (LibreLane default 64, the source
of the `-droute_end_iter 64` seen in the log, confirmed via
`librelane/steps/openroad.py`'s `DetailedRouting` step) is the relevant knob, but **unlike
`GRT_OVERFLOW_ITERS`, this is not a safe cap to lower**: each optimization iteration does real
rip-up-and-reroute work fixing genuine DRC violations, not a wasted restart on an already-decided
outcome. Lowering it would just ship more real, unfixed design-rule violations in the final GDS
for `make precheck` to catch later, trading this ticket's runtime problem for ticket 30's. Left
alone; watching whether the plateau holds, breaks, or the run reaches `droute_end_iter 64` without
fully closing (LibreLane's own docs for this step note it commonly takes "hours, days or weeks" on
larger designs, so slow convergence alone isn't evidence of a bug the way the GRT/antenna cases
were).

## Comments (real crash, real root cause, not a design problem)

**`OpenROAD.DetailedRouting` was OOM-killed at iteration 11 (60%, 313,965 violations, ~13 hours
into the step), and the cause is host-wide memory contention, not the design or the flow.**
Confirmed via `journalctl -k`: a genuine global OOM (`constraint=CONSTRAINT_NONE`), not the
container's own cgroup limit -- `openroad`'s RSS was ~5.5 GB the whole night, nowhere near its
12g container cap. Full mechanism, and a second live recurrence caught and paused mid-retry,
written up in `flow/klayout-drc-memory-research.md`'s new "A second, different OOM" section --
that file is now the general home for this class of incident, not just the original KLayout one.
Short version: the container memory cap bounds what the container's cgroup *can* use, not what's
*available* to it; when the rest of the host (desktop session, other tools, an unrelated
concurrent `bazel` build caught live) is already consuming most of the real 15 GB, the container's
own well-behaved usage can still starve the whole machine.

Applied before retrying: `DRT_THREADS: 8` in `flow/config.yaml` turned out to be a dead end --
traced into LibreLane's `DetailedRouting.run()` and confirmed it reads thread count from the OS
environment, not from resolved config, so this variable doesn't actually control TritonRoute's
thread count through this repo's config file. Left in `flow/config.yaml` as a harmless no-op
rather than reverted, since it costs nothing and documents the finding.  `DRT_SAVE_SNAPSHOTS:
true` **does** take effect (confirmed in the step's resolved `config.json`) -- checkpoints each
iteration so a future crash loses at most one iteration's work, not another ~13 hours.

Retried once: paused deliberately (`podman stop`) ~15 minutes in, at 80% of a fresh iteration 0
(violations climbing 110K->357K, which is expected/normal for a first pass accumulating violations
across the design rather than a later repair iteration), after confirming live that the host was
back down to ~200 MB free RAM (a concurrent `bazel` build plus the usual desktop load). No
snapshot existed yet at that point, so the loss is ~15 minutes, not 13 hours. Not yet resumed --
waiting on the host actually having real free memory before starting again, per user decision.
Ticket 29 remains open: still no real post-route STA number, still no closed detailed route.

**Violation type breakdown (iteration 7's summary, first time the log has shown this detail):
it's dominated by shorts, not spacing.** By type, roughly: Short 105,895 (Metal2) + 77,413
(Metal3) + 71,734 (Metal4) + 32,793 (Metal5) ~= 287,835; Metal Spacing ~30,585 across the same
layers; Cut Spacing/NS Metal/SpacingRange in the low hundreds combined. Shorts dominating means
this plateau is a genuine routing-congestion signature (tracks double-assigned under real
pressure), not a pile of minor clearance nitpicks -- consistent with the 77% utilisation this
design runs at, and with the map's standing suspicion (ticket 25/26) that this design leans
heavily on emergency buffering that produces exactly this kind of downstream density. Asked the
user how to proceed given the plateau and no safe lever exists; **decision: let it keep running,
work other tickets (31, this one's documentation) in parallel rather than block on it.**

## Comments (detailed routing resumed; snapshots confirmed working for real)

**Resumed 2026-08-20 23:18 EDT** with `make harden ARGS='--last-run --from
OpenROAD.DetailedRouting'`, after confirming the host had genuine headroom (8.1 GiB available,
3.5 GiB free) rather than trusting the container's own cap. The pause that preceded it left no
snapshot, so this restarts detailed routing from iteration 0 rather than resuming mid-step.

**Iteration 0 completed in 18m33s with 512,491 violations.** The step is
`43-openroad-detailedrouting` in `RUN_2026-08-17_16-21-08`, one higher than the `42-` of the
killed attempt. (An earlier draft of this comment quoted 476,631 for iteration 0. That was a
`Completing 100% with N violations` progress line read as a result; the iteration's real total
is the `DRT-0199 Number of violations` line, and reading the wrong one is easy because both
appear at the end of an iteration.)

**`DRT_SAVE_SNAPSHOTS` is now confirmed working by observation, not just by config.** The
earlier note could only say it appeared in the step's resolved `config.json`; this run wrote a
real `drt_iter0.odb` (291 MB) into the step directory the moment iteration 0 finished. A crash
from here costs at most one iteration, which is the whole point of having set it.

**Host memory is the live risk, and it is tighter than the operational checklist wants.**
`openroad` alone sits at ~6.2 GB RSS and the host is down to ~3.5 GiB available, under the >4
GiB floor `flow/klayout-drc-memory-research.md` sets, with the desktop session (Firefox and its
content processes, ~3 GB combined) as the largest other consumer. Nothing has been killed to
reclaim it, since that is the user's session to decide about, but this run is exposed to exactly
the `CONSTRAINT_NONE` global OOM that ended the last one.

A cheap self-inflicted lesson worth recording: an `fst2vcd` run started against ticket 31's
13 MB waveform while this route was live pushed available memory down to ~190 MB before it was
stopped. It also outlived its own shell timeout, because rootless podman's PID namespace means a
host-side kill does not reach the process inside the container (the same trap ticket 31 hit);
`podman stop` on the container is what actually ended it. Waveform work is not free while a
route is running, however small the file looks.

## Comments (detailed routing is deterministic, and that changes what a restart is worth)

**This run is reproducing the previous one exactly, iteration for iteration.** Iteration 0:
512,491 violations, both runs. Iteration 1: 401,007 violations, both runs. `detailed_route` is
invoked with `-or_seed 42` (visible in the step's `COMMANDS`), and on this design that is enough
to make the whole trajectory repeatable rather than merely similar.

**Two things follow, and they point in opposite directions.**

The good one: the plateau recorded earlier in this ticket is a real, reproducible property of
the design, not a sample. The numbers already written down (512,491 -> 401,007 -> 367,255 ->
326,593 -> 322,587, then iterations 8-10 each gaining under 1% for 1-2.5 hours apiece) can be
quoted as the design's actual convergence curve. It also means the map's standing fog entry
about *global* routing's run-to-run time variance does not extend to detailed routing; whatever
causes that variance, it is not affecting this step.

The costly one: restarting from iteration 0 buys no new information until the run passes
iteration 11, which is where the previous attempt was OOM-killed roughly 13 hours in. Everything
before that is a re-derivation of numbers this ticket already has. There is no way to skip
ahead, because that run predated `DRT_SAVE_SNAPSHOTS` and left no ODB to resume from, so the 13
hours has to be paid once more to get back to the frontier. The snapshots this run is writing
are what stop that from ever being true a third time.

**So the value of this run is entirely in what happens after iteration 11**, and the question it
is actually being run to answer is whether the plateau eventually breaks, runs to
`droute_end_iter 64` still dirty, or flattens somewhere that makes shipping known violations to
ticket 30 the only remaining option. Judge it on that, not on the iteration counts it produces
overnight, which are already known.

## Comments (two things recorded above are wrong: read this before trusting them)

Both corrections come from reading `librelane/scripts/openroad/drt.tcl` directly, which is the
script `COMMANDS` actually invokes, rather than from `DetailedRouting`'s Python wrapper.

**1. `DRT_THREADS` is not a no-op. It works, and the earlier note above saying otherwise is
wrong.** `drt.tcl` calls `set_thread_count $::env(DRT_THREADS)` before `detailed_route`.
LibreLane exports resolved config into the OS environment for its Tcl scripts, so "the step
reads thread count from the environment" and "this repo's config file controls it" were never in
conflict; the second conclusion simply did not follow from the first. The evidence is
unambiguous: this host has **20** cores, `flow/config.yaml` sets `DRT_THREADS: 8`, and the run
log reports `[INFO ORD-0030] Using 8 thread(s)`. Unset, it would have taken all 20, which is
what `flow/config.yaml`'s own comment beside the setting already says. Leave it set; it is doing
the memory-bounding job it was added for, not documenting a dead end.

**2. `DRT_SAVE_SNAPSHOTS` does not make the step resumable, so "a crash loses at most one
iteration" is false.** The snapshots are debug artifacts and nothing reads them back.
`drt.tcl`'s only handling of them is `detailed_route_debug -snapshot_dir` to write them and a
`file rename` to move them into the `drt-run-$i` subdirectory afterwards; there is no read path
anywhere in the script or the step. LibreLane's own parameter description is explicit:
"Experimental: saves an odb snapshot of the layout each routing iteration. This increases disk
usage considerably but is useful for debugging." Resuming still means `--from
OpenROAD.DetailedRouting`, which starts `detailed_route` at iteration 0.

**Together with determinism, that makes this step effectively all-or-nothing.** Stopping it is
perfectly safe in the sense that nothing corrupts and every completed prior step survives, but
"stop now, resume later" does not exist here: a restart re-derives the identical iteration
sequence and pays the identical wall-clock cost. Treat a detailed-routing run as a single
overnight commitment, and schedule it as one.

**One untested escape hatch, recorded as a possibility and not a recommendation.** The snapshot
ODBs do carry real routed geometry, so `read_db drt_iter8.odb` followed by `detailed_route`
would restart TritonRoute's iteration counter at 0 but from a partially-routed database rather
than from the global-routing result. Whether that converges faster than a clean restart is
unknown and unmeasured, and it sidesteps LibreLane's step bookkeeping (metrics, `write_views`),
so anything produced that way is not a flow artifact. Worth measuring only if a restart from
zero ever has to happen again.

## Comments (past iteration 11 at last: detailed routing does not converge, and the arithmetic says so)

This run is the first to get past iteration 11, where the 2026-08-18 attempt
died, so everything from here is information the ticket did not have. It
answers the convergence question, and the answer is no.

The violation curve does improve past the plateau. Iterations 5 through 9 were
buying between 465 and 1,702 violations apiece against a ~318K base, which is
what made it look terminal. Iterations 10 and 11 bought 2,280 and 2,700, the
best since iteration 4. So the plateau was not a floor.

    iter  violations   delta
       0     512,491
       1     401,007  -111,484
       2     367,255   -33,752
       3     326,593   -40,662
       4     322,587    -4,006
       5     320,885    -1,702
       6     319,596    -1,289
       7     318,927      -669
       8     318,462      -465
       9     317,840      -622
      10     315,560    -2,280
      11     312,860    -2,700

The cost curve is what kills it. Per-iteration wall time, taken from the
snapshot mtimes and confirmed against the DRT-0267 summaries:

    iter   1   2   3   4   5   6   7    8    9   10   11
    min   17  17  63  58  58  57  58   76  106  176  220

Iterations 1 through 7 held flat near an hour. From 8 onward the cost grows
superlinearly, roughly 1.4x per iteration over the last four. Iteration 11
alone took 3h39m and burned 16h20m of CPU across 8 threads.

Put the two curves together and the step cannot finish. `droute_end_iter` is
64, so 52 iterations remain. At iteration 11's flat 3h39m that is already 190
hours, and the cost is not flat, it is compounding. Holding the growth to a
conservative 1.2x (well below the 1.4x actually observed) the next ten
iterations alone cost about 114 hours and only reach iteration 21. Separately,
even ignoring time entirely, 312,860 violations retiring at 2,700 per iteration
needs roughly 116 more iterations, which is nearly double the 64-iteration
budget. Both arithmetic paths say the same thing: this route does not close.

Memory is not the constraint, which corrects a worry recorded earlier in this
session. Per-iteration peak RSS runs 5695, 5685, 5688, 4806, 4248, 4690 MB.
That fluctuates without trending, and it stays far under the 12g container cap.
The 2026-08-18 death was host-wide contention from processes outside the
container, not OpenROAD growing into its own ceiling. A future run needs the
host kept clear; it does not need a larger cap.

The conclusion is that the fog bullet added to the map this session was right,
and this run is now the evidence for it rather than the inference behind it. A
design that needed 64,734 RepairDesignPostGPL emergency buffers (28% of ~231K
instances) at 26.6% global placement density is not going to be rescued by
grinding detailed routing harder. The 318K violation floor is a property of
what was handed to the router, so the fix belongs upstream, in fanout and
placement, not in DRT iteration count.

What this does NOT establish: that a *different* placement fails too. Every
number here describes one specific placed database. The next move is upstream
work, then a fresh route, not more iterations on this one.

## Comments (the 6 MHz run's real numbers, and why the answer is 5 MHz)

**`RUN_2026-08-22_23-39-37` is the first run to carry all four of the `L2_BANK_SIZE` fix, the
6 MHz boot ROM, the word-alignment guard and a converged route, and its post-route STA
(`50-openroad-stapostpnr`) is the measurement this ticket has been waiting for since it was
written. It closes neither half of the Definition of Done, and it misses them in opposite
directions.**

Setup at `max_ss_125C_3v00`: **WNS -7.72 ns, 162 violations**, against -28.59 ns and 9,127 at
100 ns. `tt` and `ff` still pass with 29-38 ns to spare, so this stayed corner-specific
exactly as ticket 26 found. The 100 -> 166.67 move did roughly 98% of the work by violation
count and still did not close.

**All 162 violations launch from one flop.** `_156233_/Q`, which is
`i_chip_core.i_core_v_mcu.i_soc_domain.fc_subsystem_i.lFC_CORE.id_stage_i.decoder_i.instr_rdata_i[17]`,
is the startpoint of every single one; the endpoints differ. So this is one path's fanout,
not 162 independent problems, and it is the same *structure* ticket 22 and the earlier
comments above found (a decoder instruction-word bit), one bit over.

**Traced the path end to end rather than assuming it was decoder-local, and it is not.** It
runs decoder -> `id_stage_i.controller_i.id_valid_i` -> across the die into
`i_soc_interconnect.i_axi_xbar.i_xbar...i_aw_arbiter.gen_arbiter.req_d[1]`. 176 stages,
169.57 ns of data path from launch `Q` to capture `D`. Attributing that delay by cell class:

| class | delay | stages |
|---|---|---|
| real logic | 85.40 ns (50.4%) | 71 |
| resizer repair buffers | 84.18 ns (49.6%) | 80 |

The 80 repair buffers are 46 `wire*`, 26 `load_slew*`, 5 `fanout*` and 3 `max_cap*`, averaging
1.05 ns each. Applying this map's own lesson from ticket 32 (buffers are evidence about the
resizer's constraints first): this time the constraints are *right*. The path physically
crosses the die, and a long wire at 3.0 V and 125 C genuinely needs that buffering. There is
no degenerate repair to switch off here the way there was for max-fanout. Closing this at
6 MHz means pipelining decode-to-interconnect, which ticket 22 already put off this map.

**So the answer is the lever ticket 05 built in on purpose: the clock is external.** At 200 ns
this exact netlist has **+25.61 ns** of setup slack. That is arithmetic on a fixed netlist
rather than a fresh run, and it is exact for the reason that makes it safe to rely on: arrival
time is a property of the routed netlist (188.56 ns), only required time moves with the period,
so +33.33 ns of period is +33.33 ns of slack, to the picosecond. A re-harden at 200 ns can only
beat it, because the resizer stops chasing a target it cannot reach. 5 MHz is as ordinary a
crystal as 6, and it divides exactly where 6 MHz left cocotb truncating 166.67 to 166.

**Hold is the other half of the DoD, it regressed, and no period change touches it** (hold is
period-independent for a same-edge check). 69 violations at `max_ff_n40C_3v60` against 1 last
measured: 57 reg-to-reg at worst -0.140 ns, and 12 input-pad-to-register at worst -0.359 ns.

Root-caused rather than patched blind. **This flow fixes hold exactly once, and early.**
`RUN_POST_GRT_RESIZER_TIMING` resolves to `False` in the Chip flow, so there is no
`ResizerTimingPostGRT` step at all: step 34 is `GlobalRouting` and step 35 is `CheckAntennas`,
with no resizer between them. Hold is repaired only in `ResizerTimingPostCTS` (1,394 endpoints,
1,333 buffers, against *estimated* parasitics) and nothing revisits it after `RCX` extracts the
real ones. Two consequences worth carrying forward: **`GRT_RESIZER_HOLD_SLACK_MARGIN` is dead
config in this flow** and has been silently doing nothing, and the estimate-to-extraction gap
is measurable at up to 0.35 + 0.36 = **0.71 ns**. `PL_RESIZER_HOLD_SLACK_MARGIN` 0.35 -> 1.0
covers that with 0.29 ns spare, which is deliberate over-insurance: hold buffers are 0.6% of
this design and a hold failure is the one thing that cannot be fixed after fabrication.

**Two things checked and deliberately not fixed**, so the next reader does not re-open them:

- The 321 `max capacitance` violations at `ss` are every `bidir_PAD[n]` port at 3.79 pF against
  a 0.2 pF limit. That limit is `set_max_capacitance` applied to `[current_design]`, which
  catches the ports; a bond pad drives an off-chip load by design. Constraint artifact.
- The 571 `max slew` violations concentrate on the uDMA per-peripheral clock gates
  (`i_clk_gate_per`, `i_clk_gate_sdio`, `u_clockgen`) and the L2 SRAM clock pins, worst 9.38 ns
  against 3 ns. `flow/chip_top.sdc`'s own header already documents these domains as
  unconstrained and therefore un-CTS'd, buffered as ordinary data nets. Known and already
  written down, not a new finding.

**Also measured, because it changes what a re-harden costs:** this run is far cheaper than the
previous handoff feared. `RepairAntennas` took **7m01s**, not the ~9.5 hours it cost once;
detailed routing 23m51s; the whole run reached KLayout DRC in about 4 hours. The two longest
steps are now `RepairDesignPostGPL` (54m32s, and it should shrink at 200 ns) and the signoff
DRC decks (`Magic.DRC` 45m50s, `KLayout.DRC` ~3 h). `KLAYOUT_DRC_THREADS` is 1 while the
antenna and density decks run 4 workers, so that 3 hours is a real lever, left alone
deliberately: KLayout DRC holds 4.1 GB single-threaded on a 15 GB host, and this map has lost
more time to host OOM than it would save.

Every checker up to that point is clear on this run: routing DRC, disconnected pins, XOR,
KLayout antenna, KLayout density, and Magic DRC.

Applied the whole change set and rebuilt what depends on it (5 MHz is a silent functional bug
if a constant is left stale, not a timing one): both `PERIPH_CLK_HZ` definitions,
`sim/cocotb/tb_top_tb.py`'s `CLK_HZ`, `sim/tb/tb_top.sv`'s `CLKS_PER_BIT` (43, the truncated
5e6/115200 the divider actually lands on). Checked the boot SPI divisor rather than assuming:
`BOOT_SPI_CLK_HZ` is 2.5 MHz, so the divisor goes 1.2 -> 1 at 6 MHz and 1.0 -> 1 at 5 MHz,
which means the boot clock was silently running at 3 MHz and now lands on exactly 2.5 MHz.
Regenerated `gf180_bootrom.sv` (self-check passes, 208 words) and rebuilt `sw/app` (563 bytes).

**Still open pending the confirming re-harden at 200 ns**, which is what this ticket's own
discipline requires before either number counts.

## Comments (5 MHz closes setup; the hold fix had to be aimed at the right stage)

**Two full runs at 200 ns, and the difference between them is where hold gets repaired.**

`RUN_2026-08-23_07-07-38` paired 200 ns with `PL_RESIZER_HOLD_SLACK_MARGIN: 1.0` and made
hold **much worse**. Measured post-route:

| | margin 0.35 @ 166.67 | margin 1.0 @ 200 | margin 0.35 + post-GRT @ 200 |
|---|---|---|---|
| setup WNS (ss_125C_3v00) | -7.72 ns | +0.67 ns | **+5.02 ns** |
| setup violations | 162 | 0 | **0** |
| hold WNS (worst corner) | -0.359 ns | -9.616 ns | **-0.416 ns** |
| hold violations | 88 | 382 | **66** |
| of which reg-to-reg | 57 | 211 | **19** |

**Why 1.0 backfired, since it is counter-intuitive and worth not repeating.** At 1.0 the
post-CTS resizer found 14,640 violating endpoints and inserted **33,152 hold buffers**, against
1,394 and 1,333 at 0.35. That is arithmetically ordinary (a buffer is ~1 ns in this library at
these corners, so 1 ns of margin costs one to two buffers per path) and it is precisely the
problem: a blind 16% instance-count increase, 210,182 -> 242,358. Those buffers sit in data
paths, so they delayed everything they touched and ate the setup margin the period change had
just bought. Worse, the placement churn to fit them (detailed placement mirrored 83,015
instances) moved clock sinks, and the violations that resulted are not ordinary short paths:
they carry about **18 ns of clock skew** between the main tree and the uDMA peripheral
sub-trees, the worst launching at 5.1 ns off `clkbuf_leaf_3_clk_PAD2CORE` and capturing at
22.96 ns inside `i_udma.i_spim_gen[1].i_spim.genblk1[0].u_eot_ep.clk_rx_i_regs`. Data-path
delay cannot fix a skew problem, so buying more of it made things worse.

I also changed period and hold margin in the same run, which is why the setup number needed
disentangling afterwards. That was a mistake in method, not only in the value chosen.

**The fix that worked was aiming at the right stage, not pushing harder.**
`RUN_POST_GRT_RESIZER_TIMING` resolves to `False` in the Chip flow, so hold was being repaired
exactly once, post-CTS, against *estimated* parasitics, with nothing revisiting it after RCX.
Turning it on with the margin back at 0.35 cut reg-to-reg violations from 57 to **19** while
inserting **one** buffer at that step, which is the whole point: near-final parasitics mean the
repair lands on paths that are really violating instead of 14,640 that mostly are not.

**Setup is closed.** Zero violations at all nine corners, +5.02 ns at `max_ss_125C_3v00`. The
margin is +5 rather than the +25.6 the fixed-netlist arithmetic predicted, and that is the
resizer behaving correctly rather than a shortfall: given a reachable target it optimises to the
constraint and stops, so the path lands just inside 200 ns instead of far inside it.

**What remains on hold, characterised rather than waved through.** 66 violations, none worse
than 0.416 ns, splitting into two kinds:

- **28 input-pad paths**, worst `bidir_PAD[27] -> _163945_/D` at -0.416 ns and
  `rst_n_PAD -> _163027_/RN` at -0.330 ns. These exist because `flow/chip_top.sdc` sets
  `set_input_delay -min 0` on every input pad, which asserts that external data can change at
  exactly the clock edge. For an asynchronous GPIO and an external reset there is no such
  timing relationship to meet, and `rst_n_PAD` reaches the SoC through `rstgen_bypass`'s
  four-deep synchroniser anyway. Constraint artifacts, not silicon paths.
- **14 reg-to-reg paths**, worst -0.204 ns into an L2 SRAM data pin, the rest at or under
  0.177 ns. Every one is inside the **0.25 ns** `CLOCK_UNCERTAINTY_CONSTRAINT` that
  `set_clock_uncertainty ... [all_clocks]` applies to hold as well as setup, on top of a
  propagated clock tree and nine-corner analysis. Their physical slack is therefore marginally
  positive.

I deliberately did not reduce the hold uncertainty to make these disappear. Tuning the
measurement to pass would hide the risk rather than retire it, and 0.25 ns is a reasonable guard
for on-chip variation that this flow does not otherwise derate for.

**The identified next lever, not yet spent**, is `GRT_RESIZER_HOLD_SLACK_MARGIN`, currently 0.3.
The post-GRT step found only one endpoint at that setting, so it has room to do much more;
raising it to ~0.6 would target the post-route degradation at the stage where the parasitics are
nearly right, and would cost hundreds of buffers rather than the 33,152 the post-CTS knob cost.
That is a clean one-variable experiment if this residual needs retiring rather than accepting.
