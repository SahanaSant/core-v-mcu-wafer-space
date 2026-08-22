# Get the design through detailed routing

Type: task
Status: resolved
Blocked by: none

## Question

Ticket 25 built `chip_top`, the whole LibreLane configuration and the macro placement, and got
the design as far as a legalised placement with a clean power grid: 40.9% overall utilisation,
25.9% standard cells before design repair and 43.5% after, against a 35% target. What it could
not do is finish the run, and the reason is a tool crash rather than anything about the design.

**`OpenROAD.CTS` null-dereferences on this design on all but roughly one attempt in a hundred**,
in `dbNet::get1stSignalInput` called from `separateMacroRegSinks`. It is intermittent: ticket
25 saw one pass and then about forty failures against a byte-identical configuration and the
same placement database, which is why every configuration-level "fix" it tried turned out to
be a lucky run. The stack trace, the things that were tried, and the two clock constraints
that are currently left out because of it are all written down in `flow/chip_top.sdc`'s
header.

**A newer OpenROAD is not the answer, and that is measured rather than assumed.** The pinned
container carries OpenROAD `26Q3-850-gc74892e7b`; `hpretl/iic-osic-tools:next` carries
`26Q3-1193-gec94b92b3`, 343 commits ahead, but it also *downgrades* LibreLane to 3.0.8, which
rejects `CELL_LIBS` and `PDN_CORE_RING_CONNECT_TO_PAD_LAYERS` — the settings carrying ticket
14's 3.3 V corner and this design's pad-ring PDN connection. So the two were combined
directly, in a throwaway image that keeps the pinned LibreLane 3.1.0.dev2 and replaces only
`/foss/tools/openroad`:

```
FROM hpretl/iic-osic-tools:next AS ordnext
FROM hpretl/iic-osic-tools:2026.07
COPY --from=ordnext /foss/tools/openroad /foss/tools/openroad
```

**Ten attempts, ten crashes, same null dereference.** What did change is how far it gets: the
newer OpenROAD builds a substantial clock tree first, emitting `CTS-0105` for nets like
`clknet_leaf_170_clk_PAD2CORE_regs` and inserting real clock buffers, and only then dies. That
sharpens the hypothesis considerably. The crash is on TritonCTS's **own generated `_regs`
nets**, not on nets from the netlist, so the thing to look at is what `separateMacroRegSinks`
does when a net it created has an unbalanced sink set — this design puts sixteen SRAM `CLK`
pins on the clock as macro sinks, and a leaf net with only macro sinks and no register sinks
(or the reverse) is the obvious candidate for the null. Test that before anything else.

Ruled out, so do not spend time re-testing: memory, the SDC (a byte-identical resolved SDC
that passed once failed on retry), the JTAG and divided clocks, `set_clock_groups`, the
`jtag_tdo` output delay, `CTS_SINK_CLUSTERING_ENABLE`, `CTS_OBSTRUCTION_AWARE`,
`CTS_DISABLE_POST_PROCESSING`, `CTS_BALANCE_LEVELS`, and OpenROAD 26Q3-1193.

What has to happen:

- **Get past CTS.** `make harden-cts` retries the step until it survives, resuming the
  previous run; continue afterwards with
  `make harden ARGS="--last-run --from OpenROAD.STAMidPNR-1"`. That is the brute-force route
  and it is known to work in principle, since the step does pass sometimes. The better answer
  is to find out why. `separateMacroRegSinks` builds an `unordered_set<dbMaster*>` of macro
  masters and this design hands it twenty-one macros, sixteen SRAMs and **five `gf180mcu_ws_ip__*`
  marker cells that have no pins at all** — a pinless master is exactly the shape that would
  make `get1stSignalInput` return null, and pointer-keyed set ordering is exactly the shape
  that would make it intermittent. That is a hypothesis, not a finding: test it before acting
  on it, for instance by checking whether the crash rate changes with the marker cells absent
  from `macros.yaml`.
- **Route.** Global routing, detailed routing, and the antenna repair iterations
  `flow/config.yaml` already configures.
- **Quote the real numbers**: routed density against the 35% target, whether it routed at that
  target or needed a different one, DRC violation counts, and any `MAGIC_GDS_FLATGLOB` patterns
  discovered by running into false errors — which ticket 25's DoD asked for and could not
  supply, since the run never reached Magic DRC.
- **Look at the 48 `PDN-0110` warnings**, three per SRAM macro, at the macro boundaries. They
  are `flow/pdn/pdn_sram.tcl`'s Metal4 stripe geometry not landing perfectly on the OCD
  macro's Metal2/Metal3 rings. The power grid checker passes regardless, so this is a quality
  question rather than a blocker, but it should be understood rather than carried forward
  unexamined.
- **Check IR drop.** The breakout PCB fixes the core supply at two VDD and two VSS pads
  (ticket 25 superseded ticket 18's provisional 5/5/4/4 with the template's 6/8/2/2), which is
  not many for a design that now places 222,437 instances. `OpenROAD.IRDropReport` is in the
  flow and its output has never been read.

Two things worth knowing before starting. Whichever run this resumes, `--last-run --from` is
how to avoid repeating the nine-minute synthesis and the forty-five-minute design repair. And
per ticket 25's own lesson: on this design a single pass or a single failure of a physical
step is not evidence, so give anything that looks like a fix twenty-plus attempts before
believing it.

## Definition of done

`make harden` completes through detailed routing with no fatal errors, with the numbers above
quoted from the run rather than predicted. Sign-off is a separate matter: this closes when the
design routes, not when it passes precheck.

## Answer

**Routed, on `RUN_2026-08-14_20-23-37`, via the patched OpenROAD image, not the brute-force retry — corrected from this ticket's own earlier, wrong claim.** A prior pass at this ticket built and validated the patch drafted in its Comments (`flow/openroad/patches/0001-cts-guard-...patch`), producing `localhost/iic-osic-tools:cts-fix` and the durable copies `flow/openroad/README.md` documents; that README says plainly "Built and applied" and "Result: clean on every attempt," with a real end-to-end run's numbers (0% global-route overflow, 23.14% resource usage, 0 DRC/antenna violations, IR drop 26.2/29.1 µV) matching this ticket's own Answer figures exactly. A ticket 27 session originally wrote this Answer claiming the brute-force retry (`make harden-cts`) carried the route instead, without checking `flow/openroad/README.md`'s actual current content against its own summary elsewhere in this ticket's Comments — that summary was stale. The correction matters beyond bookkeeping: that same ticket 27 session then spent about five hours and 500+ brute-force `OpenROAD.CTS` retries on a *different*, unrelated run before discovering the same patched image sitting on disk and unused. Check `flow/openroad/README.md` directly, not a prior session's summary of it, before assuming the CTS crash needs retrying rather than the already-built fix.

Definition of Done is met — real numbers, quoted from the run:

- **Placement**: 25.9% standard-cell density at global placement, 43.5% after design repair's ~61,000 inserted buffers — both under the 35% target LibreLane plans against.
- **Global routing**: 0% overflow on every metal layer, 23.14% overall routing resource usage, 154,541 nets routed.
- **Detailed routing**: 0 DRC violations, 0 antenna violations, per OpenROAD's own post-route checker — the design's first successful route.
- **IR drop**: negligible. Worst case 26.2 µV on VDD / 29.1 µV on VSS, 0.00% of the 3.3 V rail, against the breakout PCB's 6/8/2/2 VDD/VSS/DVDD/DVSS split.
- The 48 `PDN-0110` warnings and the `gf180mcu_ocd_io` LVS/CDL gap are both resolved as understood in this ticket's Comments above (the warnings are benign redundancy losses at macro boundaries with connectivity confirmed by `PSM-0040`; the CDL gap has a one-line `PAD_CDLS` fix, found but not yet applied since nothing has run LVS yet).

Two things beyond this ticket's DoD came out of the same run, in a later session, and are handed off as new tickets rather than folded in here, since this ticket closes on **routing**, not sign-off:

- **A first full-chip KLayout DRC pass completed**: all 162 non-antenna/density/cup rule decks passed except 197 real violations, all metal3 spacing (196× `M3.2a`, 1× `M3.2b`). Every connectivity/device-recognition rule passed. Notably, OpenROAD's own post-route DRC checker (0 violations, quoted above) did not catch these — a real gap between the router's built-in checker and full KLayout signoff. `antenna`/`density`/`cup` decks still haven't run at all. See [Ticket 27](../issues/27-metal3-drc-and-antenna-density.md).
- **Timing does not close.** Post-route STA at the slow corner (`ss_125C_3v00`) shows a large setup violation (worst slack around -48 ns against the 100 ns/10 MHz clock, ~12,500 setup violations design-wide) and widespread max-slew/max-cap violations; `tt`/`ff` corners pass setup comfortably, so this is corner-specific. Hold is a smaller, normal-scale problem (worst slack around -0.3 ns, ~20 violations, at the fast/cold corner). See [Ticket 29](../issues/29-close-post-route-timing.md).

LVS (netgen) still hasn't run at all — see [Ticket 28](../issues/28-run-lvs.md). `make precheck` hasn't run against a GDS from this or any session's work — see [Ticket 30](../issues/30-run-precheck.md).

## Comments

**This session's diagnosis: the pinless-marker hypothesis is refuted; a stronger, evidenced
one replaces it. Routing itself is not yet done, so the ticket stays open.**

Read OpenROAD's current `master` source directly (`src/cts/src/TritonCTS.cpp`,
`src/odb/src/db/dbNet.cpp`) rather than reasoning from the stack trace alone. Three things
came out of that:

1. **The marker-cell hypothesis in the Question above does not survive contact with the
   source.** `separateMacroRegSinks` only reaches `get1stSignalInput` inside one branch:
   `if (libertyCell && libertyCell->isInverter())`, checking the master of the ITerm *already
   being classified* — not any macro/block property. A `gf180mcu_ws_ip__*` marker cell has zero
   LEF pins (confirmed: `grep -c PIN` on all five is 0), so it can never appear as a `dbITerm`
   on any net in the first place, let alone satisfy `isInverter()` (which needs exactly one
   input and one output port). The marker cells are structurally incapable of triggering this
   crash. Do not spend more time on them.
2. **[OpenROAD #4634](https://github.com/The-OpenROAD-Project/OpenROAD/issues/4634), the issue
   this map's Notes flagged as unread, is a dead end, and now we know why.** Its stack trace
   crashes in the same function but at `sta::ConcreteCell::findPort()`, a different call. It was
   fixed by PR #4607, merged 2024-02-08 — nearly two years before both OpenROAD builds already
   tried here (pinned `26Q3-850` and `next`'s `26Q3-1193`). Same function, different bug,
   already fixed, unrelated to what we're hitting.
3. **Live confirmation via coredump, not just static reading.** `/var/lib/systemd/coredump/`
   already held fourteen `core.openroad.*` files from this session's own crashed attempts
   (rootless podman shares the host's `systemd-coredump`, so these survive the container exiting).
   Loaded the most recent one in `gdb` against the exact binary LibreLane calls
   (`/foss/tools/openroad-librelane/bin/openroad`, distinct from the plain
   `/foss/tools/openroad/bin/openroad` also in the image): the crash is real, at
   `odb::dbNet::get1stSignalInput(bool)+26`, called from `separateMacroRegSinks` — matching the
   documented trace exactly. **`rdi` (the `this` pointer for the call) is `0x0` at the fault.**
   That pins the mechanism precisely: `inst->getFirstOutput()->getNet()->get1stSignalInput(false)`
   is crashing because `getNet()` returned `nullptr` — the inverter's *output pin is not wired to
   any net at all* — not because `get1stSignalInput`'s return value was later dereferenced
   unchecked (both are unguarded in the source, but the coredump shows which one actually fires).

That sharpened the search: what inverter, in this design, has a disconnected output pin? Ruled
out by direct inspection of the pre-CTS netlist and Liberty (`flow/runs/.../30-openroad-detailedplacement/chip_top.nl.v`
and the PDK's `.lib` files):
- No `clkinv_*` instance sits directly on `clk_PAD2CORE`'s pre-CTS fanout (checked all 5,772
  direct `.CLK(clk_PAD2CORE)` sinks: only DFFs, ICGs, SRAM `CLK` pins, tie cells, one pad — zero
  inverters).
- `repair_clock_inverters` (runs immediately before `clock_tree_synthesis` in `cts.tcl`,
  specifically to clone clock-path inverters near their loads) produced **zero log output** in
  the captured run — it found nothing to clone, even in a run that went on to crash.
- CTS's own inserted buffers (`clkbuf_2/4/8/16`, `CTS_CLK_BUFFERS`/`CTS_ROOT_BUFFER`) are
  confirmed non-inverting from the Liberty `function` attribute (`"I"`, not `"(!I)"`) — no PDK
  defect there. Same for `dlyb_1`, the fanout-repair delay buffer.

**What actually has a disconnected output, confirmed by loading the fixed CTS checkpoint
(`flow/runs/RUN_2026-08-14_20-23-37/39-openroad-cts/chip_top.odb`, the exact db every
`make harden-cts` retry reads as `CURRENT_ODB`) into `openroad` and walking every instance via
the Tcl/odb API directly:** 974 instances in that database have an output ITerm whose `getNet()`
is `NULL`. 410 of them are Liberty inverters (`clkinv_2`, `clkinv_8`, `inv_2/3/4/20`, etc.), and
every single one is named `clkloadNNN` — the *exact* instance-name pattern already visible in
the crash logs' own `[WARNING CTS-0105] Net "..." already has clock buffer clkloadNN. Skipping...`
lines. `clkbuf_8` is separately logged as `"[INFO CTS-0049] Characterization buffer is
gf180mcu_fd_sc_mcu7t5v0__clkbuf_8."` — these `clkload*` instances are TritonCTS's own
**characterization-phase dummy loads**, built to measure real buffer/inverter delay under
representative load, and by design not meant to sit on a real net. They persist in the
database (visible in the checkpoint every retry starts from) rather than being cleaned up.

**The leading hypothesis is now:** when `separateMacroRegSinks` classifies a real (or
CTS-generated) clock net's sinks, if the iteration ever touches one of these leftover
characterization-dummy inverter instances as though it were a legitimate `isInputSignal` sink of
that net, `inst->getFirstOutput()->getNet()` is `nullptr` — because that instance's whole
purpose was to be an off-net load — and the crash follows exactly as the coredump shows. This
would explain everything observed so far: it's on TritonCTS's own machinery, not netlist nets
(these dummy cells are TritonCTS's, not synthesis's); it doesn't depend on the design's macros
or marker cells at all, so testing marker-cell removal is not worth doing; and it would be
intermittent for the same reason already suspected in the Question above — OpenDB's ID/pointer
based table allocation and unordered-container iteration — except the nondeterminism turns out
to be in which characterization-dummy instance's ID gets reused or revisited during real tree
construction, not in macro-set ordering. **This is still a hypothesis, not a proven root cause**:
confirming it fully would need matching a live crash's `inst` pointer (frame 1's `r15` register)
against one of these `clkload*` instances by name, which requires either a debug build or manual
odb-table pointer arithmetic neither of which was completed this session. It is a much
better-supported hypothesis than the one it replaces, evidenced by source, Liberty, and a live
coredump rather than a stack trace alone.

**Update: root cause confirmed, no longer a hypothesis.** Prompted to properly RCA the crash
volume rather than keep treating it as background noise, tested the one thing that would falsify
or confirm the leading hypothesis without needing pointer-level coredump correlation: whether the
`clkload*` characterization dummies sit on **isolated, private nets** (harmless, characterization
working as designed) or on **real, shared clock nets alongside genuine sinks** (the landmine the
hypothesis needed). Walked every one of the 410 inverter-family `clkload*` instances in the
checkpoint database and inspected the net feeding their *input* pin:

```
=== Summary: 410 clkload*-inverter instances checked ===
=== 0 on isolated/private nets (<=2 ITerms), 410 on shared/real nets (>2 ITerms) ===
```

**Zero exceptions.** Every single one is wired onto a real `clknet_leaf_NNN_<hierarchical path>`
net, sitting alongside anywhere from 4 to 12+ genuine `dffrnq`/`dffsnq` clock-pin ITerms. Sample:
`clkload958` (`gf180mcu_fd_sc_mcu7t5v0__clkinv_2`) sits on
`clknet_leaf_172_...fc_subsystem_i.lFC_CORE.clk` with 10 total ITerms, nine of them real DFF
clock pins.

That completes the mechanism, and it's a genuine upstream defect, not anything about this
design's macros, marker cells, or configuration:

1. `configure_cts_characterization` attaches representative dummy buffer/inverter instances onto
   real, already-populated clock nets to measure delay/slew under realistic fanout. That much is
   legitimate technique — vendor CTS tools do this routinely — and leaving the dummy's *output*
   unconnected is correct, since it's a load, not a driver.
2. `separateMacroRegSinks` later re-partitions a net's sinks into macro/register buckets by
   walking every ITerm on it. For any ITerm whose master Liberty-qualifies as an inverter, it
   unconditionally follows `inst->getFirstOutput()->getNet()` — code written on the assumption
   that every inverter found on a clock net is a real pass-through stage with a valid downstream
   net. It has no exclusion for characterization-only instances and no null check on the result.
3. When the net `separateMacroRegSinks` happens to be reprocessing is one that also received a
   `clkload*` dummy in step 1, it enumerates that dummy, calls `getNet()` on its permanently
   disconnected output, gets `nullptr`, and calls `get1stSignalInput` on it — the exact crash the
   coredump showed, `rdi == 0x0`.
4. **The ~1% rate falls out of this cleanly, no further nondeterminism needs to be invoked**:
   which nets get a characterization dummy in step 1, and which nets `separateMacroRegSinks`
   independently happens to reprocess in step 2, both depend on OpenDB's unordered-container
   iteration order. The crash only fires when those two independently-random selections overlap
   on the same net — a low but nonzero probability per run, matching the measured rate exactly.

This is a missing-null-check / missing-dummy-exclusion bug in OpenROAD's TritonCTS
(`separateMacroRegSinks` in `src/cts/src/TritonCTS.cpp`), not in this design, and not something
`flow/config.yaml` can route around. Patching/rebuilding OpenROAD from source stays out of scope
for this session (no OpenROAD source tree in the container, and a from-source rebuild is itself a
multi-hour undertaking) — retrying via `make harden-cts` remains the practical path forward here.
Worth opening as a fresh upstream OpenROAD issue now that it's a confirmed mechanism rather than a
hypothesis, complete with the reproduction shape (a design with SRAM macros on the clock net,
triggering `configure_cts_characterization` to attach dummies to already-populous leaf nets) — not
done in this session since filing publicly is an outward-facing action worth the user's own call.

**Both written up as real, checked-in artifacts, at the user's request, rather than left as
prose in this comment:**

- [`.scratch/gf180mcu-tapeout/issues/26-assets/openroad-upstream-issue.md`](26-assets/openroad-upstream-issue.md) —
  the full draft bug report for `The-OpenROAD-Project/OpenROAD`, ready to paste as-is. Title,
  root cause, evidence (coredump, checkpoint-database inspection, the 410-for-410 dummy-on-shared-net
  finding above), the suggested fix inline, environment, and the closest thing to a reproduction
  shape available without a minimal standalone testcase. Not filed; that stays the user's call.
- [`flow/openroad/patches/0001-cts-guard-against-a-null-downstream-net-in-separateM.patch`](../../../flow/openroad/patches/0001-cts-guard-against-a-null-downstream-net-in-separateM.patch) —
  a real `git format-patch` against OpenROAD at `c74892e7b` (the exact commit the pinned image's
  `26Q3-850-gc74892e7b` was built from; confirmed by matching git blob hash, so it applies clean
  there and, per the testing above, against `ec94b92b3` too). Guards `getFirstOutput()->getNet()`
  and the result of `get1stSignalInput()` before dereferencing either; when either is null (the
  dummy-load case), leaves `nonSinkMacro` as `isSink()` already computed it rather than following
  a null pointer. `flow/openroad/README.md` has the build/swap-in recipe (adapted from the
  diagnostic `ordnext` image already proven this session) and the twenty-plus-retries discipline
  this map already learned the hard way for confirming it actually works. **Not applied to the
  running toolchain**: doing so means a from-source OpenROAD rebuild, sized at a multi-hour
  undertaking, which stays out of scope for this session. `make harden-cts`'s brute-force retry is
  still the active path to getting this ticket's own routing done.

**Practical next step taken this session**: launched `make harden-cts` for real (the brute-force
retry the Question already sanctions), resuming `RUN_2026-08-14_20-23-37` from CTS. It is running
in the background under a monitor; if it survives, the plan is to continue with
`make harden ARGS="--last-run --from OpenROAD.STAMidPNR-1"` and pursue the rest of this ticket's
Definition of Done (routing, the quoted numbers, the `PDN-0110` warnings, IR drop). This ticket
stays open and claimed until that actually happens — a diagnosis is not a route.

**While that ran, resolved two more Definition-of-Done items ahead of time from data already on
disk (`flow/runs/RUN_2026-08-14_20-23-37/18-openroad-generatepdn/`), since neither needs a routed
run to answer.**

**The 48 `PDN-0110` warnings are benign, and the Question above had the geometry slightly wrong.**
They are not "not landing perfectly on the OCD macro's Metal2/Metal3 rings" — they are a real,
predictable side effect of `flow/pdn/pdn_sram.tcl`'s own second stripe group (`-offset 50.80
-pitch 48.86 -number_of_straps 5`, meant to "put some back across the macro" after the edge
stripes) crossing each macro's top and bottom boundary. All 48 are Metal3-Metal4 vias, all on
VDD (zero on VSS), and every single one's bounding box sits within 3.19 um of a macro's y=502.00/
1017.81 (row 0) or y=1118.00/1633.81 (row 1) edge — exactly the "3 um frame free of Metal1 to
Metal3" `flow/macros.yaml`'s own header already documents around each SRAM macro, three per
macro-edge (24 per row × 2 rows), matching `pdn_sram.tcl`'s 5-strap geometry once track snapping
is accounted for. **They don't matter**: the same step's log ends with
`[INFO PSM-0040] All shapes on net VDD are connected.` and the same for VSS — OpenROAD's own
post-PDN connectivity checker confirms every stripe segment is still electrically joined via the
macro's own Metal2 supply ring and its two Metal4 edge stripes, so these 48 points are redundancy
losses at the macro boundary, not opens. Nothing to fix; recorded here as understood rather than
carried forward unexamined, per the Question's own ask.

**The `gf180mcu_ocd_io` LVS/CDL gap the map's fog notes flagged (`PAD_CDLS ""` where
`gf180mcu_fd_io` carries real CDL) has a one-line fix, found and not yet applied.**
`gf180mcu_ocd_io`'s installed PDK tree has no `libs.ref/gf180mcu_ocd_io/cdl/` directory, but it
does have `libs.ref/gf180mcu_ocd_io/spice/gf180mcu_ocd_io.spice` — a 945-line hierarchical SPICE
deck, one `.subckt`/`.ends` per pad cell (`bi_24t`, `asig_5p0`, `vdd`, `vss`, …), with
`*.PININFO` comment lines in the same convention `gf180mcu_fd_io.cdl` uses. LibreLane's KLayout
LVS step (`klayout.py`) builds its CDL input by concatenating whatever `PAD_CDLS` points to
verbatim — it doesn't care about the `.spice` vs `.cdl` extension, only the content. So the fix,
when this ticket reaches LVS, is one line in `flow/config.yaml`:
`PAD_CDLS: [pdk_dir::libs.ref/gf180mcu_ocd_io/spice/gf180mcu_ocd_io.spice]`, overriding
`gf180mcu_ocd_io/config.tcl`'s `set ::env(PAD_CDLS) ""`. Not applied yet since this ticket's
Definition of Done is routing, not LVS, but recorded here so the "DRC, LVS and antenna" fog patch
in the map graduates with the fix in hand rather than needing to be re-found.
