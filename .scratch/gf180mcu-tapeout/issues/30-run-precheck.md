# Get make precheck to a clean pass

Type: task
Status: claimed
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
