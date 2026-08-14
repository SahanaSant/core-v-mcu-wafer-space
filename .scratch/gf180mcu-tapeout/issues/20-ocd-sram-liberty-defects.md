# Correct the OCD SRAM Liberty and gate-level model

Type: task
Status: resolved
Blocked by: none

## Question

Ticket 11 established that no timing, power or area data anywhere in `gf180mcu_ocd_ip_sram`
was derived from the OCD layout. Every Liberty file is a foundry Liberty file with the header
swapped and the address bus resized. The design is now committed to sixteen of these macros, so
the defects have to be handled rather than noted.

Four things to fix or consciously accept, in descending order of consequence.

- **The gate-level model is optimistic by about 2x.** `sram1024x8m8wm1.v`'s specify block was
  re-derived in May 2026 from `specs/5_AC_Characteristics2.csv`, whose `Tah`/`Tal` rows are
  corrupted: column 1 carries column 5's value, duplicating 13.974 at both ends. The
  recharacteriser dropped the true worst corner and promoted the typical 25 C figure, so `ta`
  reads `4230 : 6215 : 7177` ps where the SNSP 3.0 V 125 C value is about 13.97 ns. The 5.0 V
  and 1.8 V tables in the same file are clean and the 64/256 tables are clean, which is what
  makes the shift unambiguous. Ticket 16 pinned Icarus for gate-level simulation; this is the
  number it will use.
- **Liberty `area` is the foundry macro's area**, 209,400 declared against a real 155,414 um2 for
  the 1024x8. Either patch it or make sure nothing reads it.
- **`memory() { address_width }` is 9 against ten address pins** on the 1024x8. The pin bus is
  correct, so this bites memory-aware tools rather than STA.
- **The Liberty timing itself is the foundry 512x8's**, which is the part that cannot be fixed
  locally, only bounded. Decide whether to sign off against it as a pessimistic proxy, which is
  what quoting 15.87 ns at `ss_125C_3v00` amounts to, or to characterise the macro.

Then decide what goes upstream. These are defects in a library the project depends on and the
author is responsive, so a report is cheap. Note ticket 02: nothing is published from this
effort, so an upstream issue is a separate act from publishing this work, and needs the dev's
call.

## Definition of done

A local patch under `flow/` or `pdk/` that corrects what can be corrected, applied by
`make pdk` or documented as a post-build step, plus a recorded decision on the timing proxy and
on whether to report upstream.

## Answer

**Two of the four defects are patched and reproducible; the timing defect is not locally
fixable and is signed off as an accepted, documented gap rather than patched with fabricated
data.**

Scoped to `sram1024x8m8wm1` only, the one OCD SRAM size this design instantiates (ticket 19);
the 64x8, 256x8 and 512x8 sibling libraries are untouched since nothing here uses them.

**Fixed, mechanically, in all ten corners.** `flow/pdk/patch_ocd_sram.sh`, called from
`flow/pdk/build.sh` right after staging and before the copy to `versions/`, so `make pdk`
reproduces the fix on every rebuild rather than a one-time hand edit a rebuild would discard.
It corrects two fields that were leftovers from `gf180mcu_fd_ip_sram__sram512x8m8wm1`, the part
this OCD library was derived from:

- Liberty `area` was the foundry 512x8 macro's area, `209400.2768`. The script computes the
  real number from the LEF `SIZE` line rather than hardcoding it, so a future PDK rebuild that
  changes the layout is reflected automatically: currently `301.300 x 515.810 = 155413.553`
  um2, matching this map's own Notes to the last digit.
- `memory() { address_width }` read `9` against a real 10-bit `bus(A)` (1024 = 2^10). Now `10`.

Applied now to both the `build/` and `versions/` trees so the fix is live without a ~10 to 30
minute rebuild. `make area` and `make sta` reproduce ticket 06's and ticket 22's numbers
exactly unchanged — 82,209 cells / 2,281,302 um2 flattened, 72.0% occupancy, 89 stages / 62.3 ns
/ 125% of budget at 3.3 V — confirming the patch moves nothing, which is expected: `area.sh`
already takes macro area from LEF and excludes it from `stat -liberty` by construction (ticket
19), so the stale Liberty area was already dead code, not a live error. The `address_width` fix
touches nothing STA or synthesis reads; it only stops future memory-aware tooling from
inheriting a wrong bus width. One more `area : 1.7` in the same files, in a `wire_load
("Estimate")` block, is unrelated boilerplate and was confirmed not to be this bug before being
left alone.

**Not fixed: the Verilog specify block's `ta` (CLK->Q delay).** This is the consequential one,
and it stays as shipped. The file's own header comment already documents the compromise: the
CSV row that would give the true worst corner (`ss_n40C`) is corrupted, reporting the identical
value as `ff_n40C` (13.974 ns both), which is monotonically impossible, so the recharacteriser
fell back to `ss_125C_3v00` (7.177 ns) as the "max" bound. That is the 2x-optimistic number this
ticket was opened to fix, and there is no local way to fix it: the only number that would move
it is the corrupted one, and patching it in with a number already known to be untrustworthy
would be fabrication, not correction, and would violate this map's own "measure, don't guess"
rule as much as leaving it alone with the risk undocumented would.

**Decision: sign off against the Liberty timing arcs as the pessimistic proxy, not against
this specify block, and not by attempting local characterisation.** This was already the
practical state of affairs, not a new call: `make sta` (ticket 11, ticket 19, ticket 22) never
reads this Verilog file, it signs off against the foundry 512x8 part's own characterised Liberty
arcs (13.46 to 15.87 ns at `ss_125C_3v00`), which are already well above this file's optimistic
7.177 ns and already the basis for the 89-stage, 62.3 ns, 125%-of-budget finding that stands.
Local characterisation (building a test chip, measuring real silicon) is out of this map's
reach and out of scope regardless. What this specify block's optimism affects is gate-level
*simulation* delay-annotation only, a functional/soak concern for the destination's "boots and
prints over UART" check, not the timing sign-off gate. The map's fog already carries this as a
precondition on the GLS harness; it now carries forward as a caveat instead of a blocker (see
below).

**Decision: no upstream report for now.** Grilled live with the dev: hold off filing against
Open Circuit Design until after the ORConf talk on 11 to 13 September 2026, where real silicon
characterisation for this macro is presented. That talk may supersede this finding outright (if
it ships corrected data) or confirm it (in which case the report is more useful with a citation
attached than without one). Filing now would be premature either way. This is unrelated to
ticket 02's publishing rule — filing an issue against a third-party repo doesn't publish this
one — it's purely a "wait for better information" call.
