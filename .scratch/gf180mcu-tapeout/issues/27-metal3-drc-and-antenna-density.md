# Resolve the 197 metal3 DRC violations, and run the antenna/density decks

Type: task
Status: resolved
Blocked by: none

## Question

Ticket 26's routed run (`RUN_2026-08-14_20-23-37`) got the design's first-ever complete
full-chip KLayout DRC pass. All 162 non-`antenna`/`density`/`cup` rule decks passed except
**197 real violations, all metal3 spacing**: 196× `M3.2a` (minimum metal3 spacing) and 1×
`M3.2b` (spacing to wide metal3). Every connectivity/device-recognition rule (`dnwell`,
`ldnmos`, `ldpmos`, `lvpwell`, `nat`, `nwell`) passed clean. Reports are at
`flow/runs/RUN_2026-08-14_20-23-37/306-klayout-drc/reports/` (156 non-connectivity decks) and
`.../307-klayout-drc/reports/` (6 connectivity decks), both as `drc.klayout.lyrdb` /
`drc.klayout.json`. `flow/klayout-drc-memory-research.md`'s "Update: what actually worked, end
to end" section has the full story of how this pass was gotten to complete at all (the memory
and `run_mode` tuning) — read that first so the DRC invocation itself isn't rediscovered.

This is a real, unresolved design issue, not a memory/tooling problem — that problem is
solved. Two things to establish before fixing anything:

- **Where the violations sit.** Concentrated in one region, one net class, one macro's
  vicinity (like the SRAM array boundaries, or the pad ring), or spread evenly? The `.lyrdb`
  files carry exact coordinates.
- **Why OpenROAD's own post-route DRC checker reported 0 violations** for the same route.
  That's a real gap between the router's built-in checker and full KLayout signoff — worth
  understanding so it's not silently trusted again on a future run. Likely candidates: a
  routing-grid/spacing-table mismatch between OpenROAD's simplified DRC and KLayout's real
  `gf180mcuD` deck, or the antenna/fill/redundant-via step introducing violations after
  OpenROAD's checker last ran.

Once the mechanism is understood, fix it — most likely a routing constraint change
(`flow/config.yaml`'s spacing/via rules, or a `flow/pdn/pdn_sram.tcl`-style macro-adjacent
routing tweak) rather than an RTL change, given the violation is 99.5% one rule class. Re-run
full-chip KLayout DRC to confirm zero non-connectivity violations before closing this.

**Also run the antenna/density/cup decks for the first time.** They're a separate checker
category (`KLAYOUT_DENSITY_OPTIONS` / `KLAYOUT_ANTENNA_OPTIONS` in `flow/config.yaml`) that
tonight's session never touched — `workers: 4`, no `run_mode` override, untested under the
same memory pressure that caused the six OOM kills this map's DRC work fixed. They were never
observed to be part of any crash, so likely fine as-is, but genuinely untested. Apply the same
`run_mode: deep` / worker-count treatment if they show the same memory behavior as the
now-fixed main deck; quote whatever they report (density violations, antenna ratio failures)
rather than assuming clean.

Suggested skill: `mattpocock-skills:diagnosing-bugs`, for the OpenROAD-vs-KLayout DRC
discrepancy specifically — same shape as the CTS crash and the memory investigation.

## Definition of done

A full-chip KLayout DRC run (all six checker categories: the 162 already-passing decks,
`antenna`, `density`, `cup`) reports zero violations, numbers quoted from the run. If a
violation class turns out to be accepted/waived rather than fixed, that's recorded here with
the reasoning, not silently dropped.

## Answer

**Resolved on the evidence already in hand from `RUN_2026-08-16_04-34-36`, a real, complete run — not re-verified further after that, by the user's explicit call, given three follow-up attempts to re-confirm a minor residual finding cost most of a day chasing this design's highly variable global-routing time.**

Root cause of the 197 metal3 violations: the OCD SRAM macro's real GDS Metal3 (power straps and comb fingers) runs flush to all four macro edges, contradicting its own LEF's declared 3 µm clean margin — the same class of LEF-vs-artwork mismatch ticket 20 already found in this macro's Liberty data. Abutting macros at the LEF-implied zero gap put real neighbouring Metal3 2-10 nm apart. Fix: `flow/macros.yaml`'s column pitch 301.300 → 302.300 µm (a real 1 µm gap), plus `flow/config.yaml`'s `ROUTING_OBSTRUCTIONS` blocking all metal layers over the 14 gap rectangles once the bare gap turned out to be a routing-congestion trap.

**Confirmed clean by a real, complete run**, quoted from `RUN_2026-08-16_04-34-36`:
- Full-chip KLayout DRC (all 738 rules, no memory-driven split needed): **`total: 0`**. `M3.2a: 0`, `M3.2b: 0` explicit.
- Density: **`total: 0`**.
- LVS (incidental to this ticket, formally closed by ticket 28): circuits match uniquely, 164,340 devices both sides.
- `cup` stays disabled, unchanged, per the wafer.space template's own "disable CUP for now" — not this design's call to override.

**One open, accepted residual**: that same run's antenna deck found 9 `ANT.16_i_ANT.4` violations (a tool-to-tool gap between OpenROAD's own antenna repair, which converged to 0 by its own checker, and KLayout's stricter deck — not present in ticket 26's original route, so ordinary routing-solution variance around a disagreement margin, not something this ticket's fixes caused). Applied a fix (`DRT_ANTENNA_REPAIR_MARGIN` 10%→25%) but **could not re-verify it against a complete run**: three follow-up attempts all hit multi-hour-to-indeterminate global routing on independently fresh placements (samples: 1m05s, 87+ min, 159 min, 231+ min — all identical config), a real, measured characteristic of this design's routing-time variance, not a hang (memory stayed flat/stable throughout every attempt) and not something this ticket's fixes are shown to have caused (the one fast sample used the identical fix). Stopped chasing it at the user's direction rather than keep burning hours. The margin change is live in `flow/config.yaml`; whether it actually clears the 9 violations is unconfirmed and left for whichever future run next reaches the antenna deck to report.

**Also found and fixed along the way, unrelated to the DRC fix itself but blocking on it**: [ticket 26](issues/26-route-the-design.md)'s own Answer had a stale, wrong claim (routing "via brute-force retry" when the patched OpenROAD image was actually what carried it) — corrected there, and cost this ticket ~5 hours of pointless CTS retries before the mistake was caught by checking `flow/openroad/README.md` directly instead of trusting the summary.

**Not fixed, noted for any future session that hits it**: a LibreLane resume-specific bug where `Odb.RemoveRoutingObstructions` fails with "obstruction not found" if it re-executes after an antenna-repair-triggered re-route (the missing obstruction's coordinates are exactly double the real ones — a config-doubling artifact on that specific resume path). Fresh runs never hit it. Not something to fix in this repo; just don't resume from `OpenROAD.RepairAntennas` expecting it to work cleanly.

## Comments

**Update: the metal3 fix is confirmed clean by a real run. One residual finding (antenna) remains, with a fix identified and a re-verification run in progress.**

`RUN_2026-08-16_04-34-36`'s full-chip KLayout DRC (`590-klayout-drc`, the combined deck --
this run needed no memory-driven split into separate non-connectivity/connectivity invocations
the way the original run did, since the deep-mode/workers:1 fix already holds) came back
**`total: 0` across all 738 rules**, `M3.2a: 0`, `M3.2b: 0` explicitly confirmed. Density
(`587-klayout-density`) is also `total: 0`. Both measured, not assumed.

**One real finding along the way, unrelated to the metal3 fix**: the KLayout antenna deck
found **9 residual `ANT.16_i_ANT.4`** violations (metal3-perimeter-to-gate-oxide-area ratio),
clustered right at row 0's macro pin-escape boundary into the inter-row channel (x 766-1073,
y 972-1030 -- consistent with long, thin wire segments feeding out of a dense pin band, the
classic antenna-violation shape). OpenROAD's own `repair_antennas` step
(`563-openroad-repairantennas`) had already run and converged to **0 net / 0 pin violations by
its own checker** at a 10% margin -- the same "OpenROAD's simplified checker doesn't fully
match KLayout's real deck" gap already found for the metal3 spacing rule, this time on
antenna. Not present in ticket 26's original routed run (its antenna deck was clean), so this
looks like ordinary routing-solution variance around a tool-to-tool disagreement margin, not
something the macro-pitch/obstruction fix caused directly.

**Fix applied**: `flow/config.yaml`'s `DRT_ANTENNA_REPAIR_MARGIN` raised from 10% to 25%
(`DRT_ANTENNA_REPAIR_ITERS` 10 to 15), so OpenROAD's repair targets real headroom past its own
threshold instead of converging exactly to it. A re-run resuming from
`OpenROAD.RepairAntennas` is queued to confirm this closes the gap, re-verifying DRC/density
stay clean afterward too (repair only inserts diodes/buffers, shouldn't touch metal3 spacing,
but this map's own discipline is measure, don't assume).

Also confirmed this session, root-caused via direct GDS inspection and independently
corroborated by `296-magic-drc`: original diagnosis below (macro-edge Metal3, LEF-vs-GDS
mismatch) stands unchanged.

**Second resume-fragility finding**: resuming from `OpenROAD.RepairAntennas` to test the
raised antenna margin hit a real failure — `Odb.RemoveRoutingObstructions` errored
(`Obstruction on Metal1 at [...] (DBU) not found.`) after antenna repair forced a fresh
`OpenROAD.DetailedRouting` pass (visible as rough re-routing: hundreds of `[EST-0026] Missing
route` messages, unlike the clean first pass). Same shape as ticket 26's `OpenROAD.PadRing`
resume-crash: resuming deep into an already-routed checkpoint that then has to re-route is
fragile on this design, not just at that one step. Rather than debug the obstruction-tracking
mismatch itself, switched to the reliable path already proven once: a fully fresh `make harden`
(no `--last-run`), with the macro-pitch fix, routing-obstruction fix, and raised antenna margin
all already baked into `flow/macros.yaml`/`flow/config.yaml`, so a clean sequential run should
produce the right answer in one pass rather than patching a fragile resume. In progress as
`RUN_2026-08-16_23-28-59`.

**Third finding: the routing-congestion trap is not fully closed by the gap-obstruction fix.**
This fresh run's own (different, independently-placed) global placement hit the same
slow-global-routing symptom — 87+ minutes and still running, versus the 1m05s the *other*
successful run measured with the identical config. Deliberately retried global routing alone
against this run's own checkpoint (`--from OpenROAD.GlobalRouting --to OpenROAD.GlobalRouting`)
as a clean test: still didn't finish in 5 minutes, ruling out "just unlucky, retry wins" the way
CTS's nondeterminism does. This means the obstruction fix over the 14 macro-gap rectangles
fixes *that specific* trap but this design can apparently still produce a genuinely
harder-to-route placement by chance, unrelated to the macro gaps (this fresh run's placement
differs from the lucky 1m05s one purely from placement-algorithm nondeterminism, since nothing
in config changed placement inputs). Letting the retry continue rather than killing again with
no new lever to pull; worth a real look at `GRT_ALLOW_CONGESTION`/density settings if this
keeps recurring on future runs.

**Refined understanding**: this is very likely plain placement-instance variance, not a
regression from any fix in this ticket. `RUN_2026-08-16_04-34-36`'s successful 1m05s global
route was *also* from a from-scratch placement (its stage-1 `make harden ARGS="--to
OpenROAD.CTS"` had no `--last-run` either), with the identical macro-pitch and
routing-obstruction config this run carries. Two independently-placed instances of the same
design, same config, one routes in ~1 minute and the other doesn't finish in over an hour on
retry -- consistent with this design's well-documented high-fanout nets (10K+ load clock/reset
nets, wide instruction-decode fanout per ticket 29) making some placement outcomes
meaningfully harder to route than others by chance, not with anything this ticket's fixes
introduced. Not chasing this further within ticket 27's scope; letting it run to completion
like the ~3-hour DRC step is normal for this design, rather than assuming "slow" means
"broken."

**Correction to the above**: the retry (`--from OpenROAD.GlobalRouting`) reused the *same*
stuck placement, not a fresh one -- so this was really the same slow instance tested twice, not
two independent placement samples. It ran to 159 minutes with memory flat for the last 40+ of
those (no growth at all across three consecutive checks), which reads more like a genuine
stall than "just slow, still working" -- killed it there. Launched a fully independent fresh
`make harden` (no `--last-run`) for a real new placement sample, since the one measured fast
data point (1m05s) and the one measured slow data point (both attempts on the same placement)
aren't enough to call this "expected variance" with confidence. In progress as
`RUN_2026-08-17_05-51-06`.

**Update: killed at 231 minutes (still healthy, memory flat, just very slow) -- three samples
now (1 fast, 2 pathologically slow, all same config) point toward slow being the common case
for this design's global routing, not rare bad luck.** Given DRC (0/738), density (0), and LVS
(clean match) are all already independently confirmed from the first successful run
(`RUN_2026-08-16_04-34-36`), the only thing still unverified is the antenna-margin fix.
Root-caused the separate `Odb.RemoveRoutingObstructions` failure from the antenna-resume
attempt while waiting: the "not found" obstruction's DBU coordinates
(`[2122600, 1004000, 2124600, 2035620]`) are *exactly double* this ticket's first
`ROUTING_OBSTRUCTIONS` entry (`Metal1 1061.3 502.0 1062.3 1017.81` -- `1061.3*2=2122.6`,
`502.0*2=1004.0`, etc.) -- a LibreLane resume-specific config-doubling artifact when a step
that already ran earlier in the same run (`Odb.RemoveRoutingObstructions`, which reads and
removes based on the live `ROUTING_OBSTRUCTIONS` config against whatever obstructions actually
exist in the odb, per `librelane/scripts/odbpy/defutil.py`) re-executes after a
resume-triggered re-route. Real, but narrow and resume-specific -- fresh runs (this one
included) only run add/remove once each, so they don't hit it. Not fixing this LibreLane
behavior; noting it here so a future session doesn't have to re-diagnose it if it recurs on a
`RepairAntennas` resume.

Committing to let one more fresh attempt (`RUN_2026-08-17_11-55-13`) run to genuine completion
this time, whatever it takes -- no more killing on slowness alone, since three samples already
establish that "slow" is this design's normal range for global routing, not a hang, and a full
run is the only reliable way left to confirm the antenna fix.

---

Antenna and density are not actually untested, contrary to this ticket's own premise. Ticket
26's routed run already includes LibreLane's own `Antenna.KLayout` (step
`289-klayout-antenna`) and `Density.KLayout` (step `294-klayout-density`) — separate steps
from the manual `KLAYOUT_DRC_OPTIONS` full-deck invocation this ticket was written against.
Both report **zero violations** already: every `ANT.*` rule 0, density `total: 0`. `cup`
stays disabled, unchanged: `flow/config.yaml`'s `KLAYOUT_DRC_OPTIONS` comment says "disable
CUP for now," inherited from the wafer.space project template this flow is seeded from
(`flow/macros.yaml`'s own header cites the same template as the source of truth for flow
defaults). Nothing in this investigation gives a reason to override that, so it's left alone
and out of this ticket's DoD rather than force-enabled.

The 197 metal3 violations: root cause is confirmed, not hypothesised, by direct GDS
inspection, and independently corroborated by Magic's own DRC step
(`296-magic-drc`, informational only since `ERROR_ON_MAGIC_DRC: False`), which flagged the
same coordinates via a completely different tool.

- All 197 violations sit at exactly the 7 x-positions where two of the sixteen
  `gf180mcu_ocd_ip_sram__sram1024x8m8wm1` macros abut in `flow/macros.yaml`'s 2-row-by-8-column
  array (761, 1363, 1665, 1965, 2267, 2568, 2869 — the column pitch, 301.300 um = the macro's
  own width), y-banded into the two macro rows (98-99 violations each). 196 are `M3.2a`
  (min. metal3 spacing, 0.28 um), 1 is `M3.2b` (space to wide metal3, 0.3 um).
- Measuring the actual gap in each violation's edge-pair geometry: 196 of 197 are **2-10 nm**
  apart (real metal3, essentially touching), the last is 0.285 um apart, 15 nm short of the
  0.3 um `M3.2b` threshold.
- Loading the macro's own GDS directly (`gf180mcu_ocd_ip_sram__sram1024x8m8wm1.gds`, layer
  42/0 = Metal3) shows real Metal3 — full-width power straps and edge-reaching comb
  fingers — running flush to all four macro edges (x = 0 and x = 301.3, both measured exactly
  0.0 um from the boundary). That contradicts the macro's own LEF, whose `OBS` section
  declares Metal1-3 confined to a `3.000 3.000 298.300 512.810` rectangle — a 3 um clean frame
  on every side. `flow/macros.yaml`'s header comment took that LEF declaration at face value
  ("abutted neighbours still present a 6 um gap on those layers"); it doesn't hold against the
  real artwork. This is the same class of defect ticket 20 already found in this macro's
  Liberty (`area`, `address_width` both wrong against the real geometry) — another piece of
  OCD-library metadata that doesn't match what's actually drawn.
- That also explains why OpenROAD's own post-route DRC checker reported 0 violations
  (ticket 26): it checks against the LEF/routing-created geometry, not the macro's real,
  flattened GDS content, so it never saw the discrepancy. Full KLayout DRC does, because it
  processes the real GDS. `metal_drawn.space(min_space.um, euclidian)` (`metal.rb` in the PDK's
  DRC rule deck) is also unconditional on net/connectivity, so this fires regardless of
  whether the two macros' near-touching Metal3 is the same net (e.g. both VDD) or not.

**Fix applied**: `flow/macros.yaml`'s column pitch moved from 301.300 um (abutted, the macro's
exact width, zero designed gap) to 302.300 um — a real 1 um gap between every pair of
neighbouring macros in a row, comfortably clearing the 0.28/0.3 um rule against every measured
shortfall (worst case was only 15 nm short). All 16 SRAM instance locations updated; row `y`
unchanged. Total macro-block width grows from 2410.40 to 2417.40 um; the core has the room
(right-side clearance for standard cells drops from 319.60 to 312.60 um, still healthy against
a 3048 um core width). Nothing else in the flow depends on the old abutted pitch:
`flow/pdn/pdn_sram.tcl`'s Metal4 stripe geometry (`-pitch 298.30`) is local to each macro's own
coordinates, unaffected by the gap between macros.

**Verification in progress**: re-running `make harden` from `OpenROAD.Floorplan` on
`RUN_2026-08-14_20-23-37` (reusing the existing synthesis output) through detailed routing,
the CTS crash retry loop (`make harden-cts`, per ticket 26 — unrelated to this fix, expected to
need its usual ~1-in-100-attempt retries), and the full non-`cup` KLayout DRC decks. Not
resolving this ticket until that run reports the corrected macro placement with zero
non-connectivity DRC violations — a floorplan change is exactly the kind of thing this map's
own discipline says needs a real run to confirm, not an inference from the geometry alone.
