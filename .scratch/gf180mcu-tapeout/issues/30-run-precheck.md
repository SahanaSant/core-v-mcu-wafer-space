# Get make precheck to a clean pass

Type: task
Status: resolved
Blocked by: 27, 28 (both resolved), and [Close post-route timing at the slow corner](29-close-post-route-timing.md) for the final GDS, which is itself now blocked on [fanout](32-reduce-fanout-for-routability.md)

## Question

`make precheck` — the actual [gf180mcu-precheck](https://github.com/wafer-space/gf180mcu-precheck)
submission-readiness gate this map's Notes already say sign-off means — has never been run
against a GDS from this or any prior session's work. Sign-off is a clean precheck, not a
clean `make harden`; this map's destination is explicitly "a GDS of `chip_top` that passes
`gf180mcu-precheck` for a 1x1 slot," so this ticket is the last physical-verification step
before that half of the destination is reached.

Blocked on ticket 27 (the 197 metal3 violations, plus the never-run antenna/density/cup decks)
and ticket 28 (LVS has never run) because precheck almost certainly re-checks DRC/LVS/density
class rules itself — running it against a GDS with 197 known violations and no LVS would
mostly just re-report what those tickets already know, rather than surface anything new.
Not blocked on ticket 29 (timing): precheck is a physical/structural submission checker, not a
timing signoff tool, so there's no reason to expect it cares about STA results — confirm that
assumption is actually true once `make precheck-image` and a real run exist, rather than
carrying it forward unchecked.

## Definition of done

`make precheck` reports a clean pass against `flow/final/gds/chip_top.gds` from a run that has
also cleared tickets 27 and 28, numbers/output quoted from the run. If precheck flags anything
beyond what 27/28 already cover, that's a new finding for this ticket to resolve or spin off,
not something to wave through.

## Answer

<!-- filled on resolution -->

## Comments

**Claimed. First real invocation found `make precheck` itself was broken, unrelated to the
GDS content — fixed, and a dry run against the existing (10 MHz-era, DRC/LVS-clean) GDS is
in flight now to validate the mechanics while ticket 29's fresh 6 MHz run is separately in
flight for global routing.**

The Makefile's `precheck` target passed `--top $(TOP) --slot $(SLOT) <gds path>` directly as
the image's command. That's not this image's real CLI: its entrypoint is `dev-shell`, a nix
wrapper that execs whatever command follows it inside `nix develop`, and the actual tool is
`python precheck.py --input <path> --top <cell> --dir <dir>` (confirmed from the precheck
repo's own Dockerfile usage label and README, not guessed). The old invocation made `dev-shell`
try to exec `--top` as a program, which failed inside the container with a nix-shell wrapper
error that looked unrelated to precheck entirely. Fixed in the Makefile: mount only
`flow/final/gds/` to `/data`, add `--network=none` (the image needs no network once built), and
call `python precheck.py --input /data/$(TOP).gds --top $(TOP) --slot $(SLOT) --dir /data`.
Confirmed this at least starts the real `PrecheckFlow` (KLayout.ReadLayout, top-level name
check, slot size check, ID generation, KLayout render) rather than erroring before it begins.

Not yet resolved: this dry run is against the 10 MHz-era GDS, which is DRC/LVS-clean per
tickets 27/28 but does not carry ticket 29's 6 MHz timing fix. Once ticket 29's fresh run
produces a new `flow/final/gds/chip_top.gds`, rerun precheck against that GDS for the number
this ticket's DoD actually requires. The dry run's value is purely mechanical: proving the
image/Makefile invocation itself works, so that rerun isn't spent rediscovering this bug.

## Comments (dry-run stopped)

**Killed the dry run partway through the antenna DRC decks (`ANT.16_i_ANT.5`, klayout RSS
climbing past 2.5 GB with no forward log progress for ~12 minutes) to free memory for ticket
29's routing run, which is the more critical path tonight.** The dry run had already delivered
its real purpose: confirming the Makefile invocation fix works and the flow runs real
KLayout DRC/antenna checks against a real GDS, well past the point of proving the mechanics.
Since this ticket's DoD needs precheck run against the *new* 6 MHz GDS once ticket 29 finishes
anyway, grinding this particular (10 MHz-era) dry run out further wasn't buying the number this
ticket actually needs. Rerun `make precheck` fresh once `flow/final/gds/chip_top.gds` is the new
6 MHz build.

## Comments (thirteen of sixteen stages pass on a real GDS, and the fossil is explained)

First run of `make precheck` against a GDS this effort actually produced, rather
than against whatever `flow/final` happened to be holding. Input was
`RUN_2026-08-23_09-43-11`'s `chip_top.gds`, 267 MB, the 200 ns / 5 MHz run.

`PrecheckFlow` has sixteen stages. Thirteen passed:

| stage | result |
|---|---|
| CheckTopLevel | pass, `chip_top` |
| CheckSize | pass, slot `1x1` |
| GenerateID | pass, `die_id FFFFFFFF` |
| Render | pass |
| Density | **clear** |
| ZeroAreaPolygons | **clear** |
| Antenna | **clear** |
| Magic DRC | **COUNT: 0** |

Stage 14, the KLayout DRC deck, was killed deliberately at 2h09m into it, and
the run therefore reports a failure. That failure is mine, not the design's:
the log shows `SignalException: SIGTERM`, nothing else. Reasoning for stopping
it is in the next section.

The reason this ticket's earlier attempt read as a "dry run against the
10 MHz-era GDS" is now known and is not a precheck problem at all. `make harden`
chains `sync-final` after LibreLane; LibreLane exits non-zero whenever any
checker defers an error; a non-zero exit aborts the chain. So `flow/final` kept
pointing at the previous run, and `FINAL_GDS` resolves through `flow/final`.
Recorded in full on ticket 31 and on the map.

One incidental finding worth keeping: precheck writes its run directory into
`$(dir $(FINAL_GDS))`, which is `flow/final/gds/`, because that is what the
Makefile mounts as `/data`. So precheck output accumulates *inside* the
directory the next precheck will mount. `sync-final`'s `rm -rf` clears it, but
anything reading `flow/final/gds/` should expect a `runs/` subdirectory beside
the GDS rather than a lone file.

## Comments (why stage 14 was stopped rather than waited out)

The KLayout deck precheck runs is byte-identical to the one the harden already
ran: `decks=all,-antenna,-density,-cup`, `variant=gf180mcuD`. The harden's own
KLayout DRC on the same geometry reported **738 rules, every one zero**. The
only real difference is the input, since precheck checks the layout after
`GenerateID` has stamped a die identifier into it.

Waiting it out would have cost roughly two more hours to re-validate geometry
that had already passed, on a GDS that was about to be replaced by the hold-fix
harden. A precheck against the *final* GDS is mandatory either way, and it will
cover the ID-stamped question then. The purpose of running precheck before the
harden was to catch a structural failure before spending seven hours on a
route, and every structural check precheck uniquely offers had passed by then.
So the critical path was handed back to the harden.

What this does **not** establish: that the full DRC deck passes on an
ID-stamped layout. That is still open and is what the final run has to show.

## Answer

**`make precheck` passes, all sixteen stages, on the final GDS.**

```
[17:34:02] INFO  Precheck successfully completed.
PrecheckFlow - Stage 16 - Write the Layout  16/16  5:37:59
```

Input was `flow/final/gds/chip_top.gds`, 268.8 MB, from
`RUN_2026-08-24_02-03-47`, the run that closes setup and hold at all nine
corners. Every stage:

| stage | result |
|---|---|
| ReadLayout, CheckTopLevel | pass, `chip_top` |
| CheckSize | pass, slot `1x1` |
| GenerateID, Render | pass, `die_id FFFFFFFF` |
| Density | clear |
| ZeroAreaPolygons | clear |
| Antenna | clear |
| Magic DRC | COUNT: 0 |
| **KLayout DRC** | **738 rules, every one zero** |
| WriteLayout | pass |

That last row is the one this ticket existed for, and it is the first time the
full deck has run against the **die-ID-stamped** layout rather than the
pre-stamp geometry the harden checks. The stamp introduces no violations.

### The failure that came first, and why it was not the design

The run before this one died at stage 14 after four hours and twelve minutes.
The precheck log said only `Interrupted (SIGKILL)`, which reads like a tool
crash. It was the kernel:

```
Out of memory: Killed process 2556885 (.klayout-wrappe)
total-vm:17730676kB, anon-rss:9151644kB
```

`precheck.py` defaults `--threads` to `"max"`, which resolves to
`os.cpu_count()`, 20 on this host. KLayout's DRC holds per-thread copies of the
intermediate layers, so the thread count multiplies peak memory rather than
buying throughput. `PRECHECK_THREADS ?= 1` in the Makefile pins it, chosen
because the harden runs the byte-identical deck at `threads=1` and completes,
so it is the setting with direct evidence rather than an interpolation.

Two things worth keeping. The 20-thread run had executed 283 rules at the point
where the 1-thread run had executed 615, so on this layout the parallelism was
**losing** on both memory and speed. And a `SIGKILL` in a tool log is worth
checking `dmesg` for before treating it as a tool or design defect; it took one
kernel line to separate a resource limit from a real failure.

### Standing trap this ticket confirmed

`FINAL_GDS` resolves through `flow/final`, and `flow/final` is only refreshed by
`sync-final`, which `make harden` chains **after** LibreLane and therefore skips
whenever LibreLane exits non-zero on a deferred error. Run `make sync-final` by
hand after any non-zero harden, or precheck silently grades the previous run.
Precheck also writes its own `runs/` tree into `$(dir $(FINAL_GDS))`, so that
directory accumulates output beside the GDS.

Status: resolved.
