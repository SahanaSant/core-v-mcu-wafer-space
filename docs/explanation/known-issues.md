# Known issues and gotchas

Things in the tools, the PDK and the macros that cost real time to find. Each one is
root-caused rather than worked around blindly, and each has a live mitigation somewhere in
the repository.

## OpenROAD's TritonCTS crashes on this design

**Symptom.** `OpenROAD.CTS` segfaults on all but roughly one attempt in a hundred. Stack
trace:

```
odb::dbNet::get1stSignalInput(bool)
cts::TritonCTS::separateMacroRegSinks(...)
cts::TritonCTS::initClockTreeForMacrosAndRegs(...)
cts::TritonCTS::initClock(...)
cts::TritonCTS::initOneClockTree(...)   x11, recursing
```

**Root cause**, confirmed from a live coredump and by walking every instance in the pre-CTS
`.odb` through the Tcl/odb API, not hypothesised. TritonCTS's own
`configure_cts_characterization` phase places dummy load instances on real, already-populated
clock nets to measure delay and slew under representative fanout, deliberately leaving those
instances' output pins unconnected. `separateMacroRegSinks` later walks every sink on a net
and, for any Liberty inverter it finds, unconditionally follows the inverter's output net
without a null check. That segfaults when the inverter is one of those dummy loads. The
checkpoint-database walk found all 410 characterisation dummy loads sitting on real, shared
clock nets rather than isolated ones.

The intermittency comes from `separateMacroRegSinks` iterating an `unordered_set<dbMaster*>`,
keyed on pointers and therefore ordered differently in every process.

**Why single experiments are worthless here.** One attempt passed, and re-running the same
step later against the byte-identical resolved SDC that pass had emitted, from the same
placement database, failed. Every reported "fix" has to survive twenty-plus attempts before
it means anything. These were all tried and none changed the rate: adding or removing the
JTAG clock, adding or removing the divided clock, `set_clock_groups`, the `jtag_tdo` output
delay, and `CTS_SINK_CLUSTERING_ENABLE`, `CTS_OBSTRUCTION_AWARE`,
`CTS_DISABLE_POST_PROCESSING` and `CTS_BALANCE_LEVELS`, singly and in combination. Memory is
not the cause either: 5.3 GB free at the low-water mark and nothing in the kernel log.

**A newer OpenROAD is not the fix.** A build 343 commits ahead (`26Q3-1193-gec94b92b3`, from
`hpretl/iic-osic-tools:next`) crashed ten times out of ten with the identical dereference.

**Mitigations.** `make harden-cts` retries the step; the one-line source patch in
`flow/openroad/patches/` removes the crash outright. See
[how-to/patched-openroad.md](../how-to/patched-openroad.md).

**Consequence for the SDC.** Because each declared clock is another tree for CTS to build and
another chance to hit this, `flow/chip_top.sdc` declares two clocks rather than three. The
`/40` divided clock is left out; at 125 kHz what it loses is a balanced tree, which is close
to immaterial when skew that would matter against 200 ns is nothing against 8000 ns.

## The OCD SRAM's Liberty describes a different macro

Every Liberty file in `gf180mcu_ocd_ip_sram` is a **foundry Liberty with the header swapped
and the address bus resized**. Two fields are mechanically wrong and one whole category is
untrustworthy:

- `area` carries the foundry `sram512x8`'s 209,400 µm² against a real 155,414 µm² for the
  `sram1024x8`, and is 3.2x out on the `sram64x8`.
- `memory() { address_width }` reads 9 against ten address pins (1024 = 2¹⁰).
- **The timing is the foundry 512x8's throughout.** `CLK` to `Q` reads 13.46 to 15.87 ns at
  `ss_125C_3v00`, which is a pessimistic proxy rather than characterisation.

`flow/pdk/patch_ocd_sram.sh` corrects the first two as part of `make pdk`, computing the area
from LEF `SIZE` rather than hardcoding it, so a PDK rebuild that changes the layout is
reflected automatically. It runs during the build rather than as a one-time hand edit
precisely so a rebuild cannot silently discard it.

The timing is left alone deliberately: it is pessimistic, and STA signs off against it.

**Take macro area from LEF `SIZE`, never from Liberty.** `flow/synth/area_report.py` reads
LEF geometry for exactly this reason, and `flow/synth/filelist.sh` hands the Liberty to slang
for module definitions only, never to `stat -liberty`.

**The Verilog model is 2x optimistic** on access time, and is not corrected. The local data
that would fix it is itself corrupted: `specs/5_AC_Characteristics2.csv`'s `Tah`/`Tal` at the
`ss_n40C` corner reports the same value as the `ff_n40C` corner, which is monotonically
impossible. Patching a simulation-only delay from data already known to be bad would be
fabricating a number. This is why a passing gate-level run demonstrates **function, not
silicon margin**.

Separately, the vendor's simulation model **silently discards every access**: it commits in
`always @(posedge clk_dly)` with `clk_dly` 100 ps behind `CLK`, sampling its own control
inputs at that later moment, so without clock-to-Q delay every input has already moved on and
the memory reads back as zeros forever. `sim/tb/gf180mcu_ocd_ip_sram_behav.sv` replaces it
unconditionally at both RTL and gate level.

## The SRAM macro's LEF contradicts its own GDS

The LEF declares a 3 µm frame free of Metal1 to Metal3 on each macro edge. The real GDS runs
Metal3 — both full-width straps and edge-reaching comb fingers — **flush to the true macro
boundary on all four sides**, confirmed by walking the macro's own GDS.

So abutting the columns put two macros' real Metal3 within 2 to 10 nm of each other. Full-chip
KLayout DRC found 197 genuine violations, 196 `M3.2a` and 1 `M3.2b`, all at the seven column
boundaries. `flow/macros.yaml` now opens a 1 µm gap, which clears the 0.28/0.3 µm rule against
every measured case.

Note that **OpenROAD's own post-route DRC reported zero violations** on the same layout. This
is a real gap between the router-side checker and full KLayout sign-off, and it is not the
only one: the antenna decks disagree the same way, which is why
`DRT_ANTENNA_REPAIR_MARGIN` is raised to 25% so OpenROAD's repair targets headroom past its
own threshold rather than converging exactly to it.

The gap has a second-order cost. A bare 1 µm-wide, 515.81 µm-tall sliver between two hard
macros is a routing-congestion trap: global routing sees it as available capacity and keeps
trying to thread nets through it, which measured as an 80+ minute stall on a step that
normally takes about 90 seconds. `ROUTING_OBSTRUCTIONS` in `flow/config.yaml` blocks the 14
gaps on Metal1 through Metal3 — and only those three, because the macro carries no Metal4 or
Metal5 in LEF or GDS, and blocking those too cost 107 real shorts against the obstructions.

## Global routing's runtime varies from one minute to hours

`OpenROAD.GlobalRouting` has taken anywhere from 1m05s to 4+ hours across otherwise-identical
runs, independent of clock frequency.

**Confirmed mechanism.** The "extra iterations to remove overflow" loop
(`-congestion_iterations $GRT_OVERFLOW_ITERS`, LibreLane default 50) does not run once. It
**restarts from iteration 1 every time it disables the non-default routing rule on one
congested net**, then grinds through up to 50 more. This design has 73
`delaynet_*_clk_PAD` nets — a hold-fix delay chain on the clock net — and however many of
them end up congested for a given placement directly sets the total wall time. One run had
cleared 2 of 73 after four hours.

This is consistent with the general mechanism OpenROAD's maintainers describe for long GRT
runs ([discussion #2889](https://github.com/The-OpenROAD-Project/OpenROAD/discussions/2889):
overconstrained timing → excess buffering → high density → many overflow iterations;
[issue #3336](https://github.com/The-OpenROAD-Project/OpenROAD/issues/3336): an unresolved
"stuck for days" report on the same loop, closed stale, no upstream fix).

**Capping the iterations works, and the right number is much lower than it looks.**

| `GRT_OVERFLOW_ITERS` | Time per net disabled | Extrapolated for all 73 |
| --- | --- | --- |
| 50 (default) | 4+ hours, only 2/73 cleared when abandoned | days |
| 12 | 8m12s, exactly, every time | ~10 hours |
| 3 | ~25s, every time | ~30 minutes |

The striking part: at every cap tried, the router disables the rule on the same nets **in the
same order**, mostly descending `delaynet_N_clk_PAD`. The iteration count is not buying real
convergence attempts; it is just how long the router grinds before conceding on whichever net
was already going to lose. `GRT_ALLOW_CONGESTION: true` already accepts the quality tradeoff
at any cap, so 3 is what runs now.

What is *not* explained is why the number of congested nets varies run to run.
Non-deterministic buffer placement between otherwise-identical runs is the likely candidate —
OpenROAD's resizer and CTS code iterate pointer-keyed `unordered_set`s elsewhere, which is
the confirmed root cause of the CTS crash above — but the disable *order* is deterministic
once congestion exists, so this is a hypothesis rather than a finding.

Reducing the 73 delay nets in the first place would need to restart from placement rather
than resume routing, so it stays a real lever for later if routing *quality* rather than wall
time ever becomes the concern.

## KLayout DRC and memory

Full-chip DRC once triggered an out-of-memory cascade that took down the host desktop
session: the kernel OOM killer took out `pipewire`, `wireplumber`, `xdg-desktop-portal`,
`dbus-broker` and `systemd --user` alongside `klayout`. The klayout log simply stops
mid-run — no shell error, no Ruby exception — which is what a SIGKILL looks like from
inside.

**How the parallelism resolves.** LibreLane forwards every key in `KLAYOUT_DRC_OPTIONS`
verbatim to the PDK's Ruby runset as a `-rd` variable; it does not interpret `workers` or
`decks` at all. The runset resolves `max` for both `workers` and `threads` to
`Etc.nprocessors`, with no cap and no headroom reservation. LibreLane's own
`KLAYOUT_DRC_THREADS` default is `os.cpu_count()`. So an unconfigured run on a 20-thread host
asks for 20 × 20.

**What works.** `deep` run mode (the runset's own default) with `workers: 1` and
`KLAYOUT_DRC_THREADS: 1`. Forcing `run_mode: flat` also survives, but costs 3-4x the wall
time: deep mode's hierarchical engine exploits the repetition in a real routed design
(thousands of identical standard-cell-level via and metal patterns) instead of flattening the
whole chip for every rule. The verified deep-mode run covered all 156 non-connectivity decks
in 2h56m with peak memory under 5 GB, against ~11.4 GB for the flat-mode netlist build alone.

Higher `workers` under deep mode was never re-tested. It is plausible that 2 or 4 would fit
and cut wall time further; that is untested, not a recommendation.

**Two different OOMs, and the cap only fixes one.** `run.sh` sets `--memory` and
`--memory-swap` (12g/14g by default, overridable with `MEMORY_LIMIT` and
`MEMORY_SWAP_LIMIT`), and that does its job: `journalctl -k` shows
`oom-kill:constraint=CONSTRAINT_MEMCG` scoped to the container's own cgroup, and the host
recovers within seconds.

But a cgroup cap **bounds** what the container may use; it does not **reserve** it. A later
`OpenROAD.DetailedRouting` kill logged `constraint=CONSTRAINT_NONE` — a genuine global OOM —
with `openroad` at only ~5.5 GB RSS, nowhere near the 12 GB cap. The container was never the
resource that ran out: a concurrent unrelated build plus a normal desktop session had already
consumed most of the host's real memory, and the kernel's global OOM killer picks whatever
has the largest RSS system-wide.

So: check `free -h` before starting a long run, and treat "available" under about 4 GB as
"don't start". Run heavy stages serially, never in parallel, and chain them in one driver
script that waits on the previous stage rather than overlapping them. Losing a long run near
the end costs far more than the wall clock saved by overlapping.

`DRT_SAVE_SNAPSHOTS: true` and `DRT_THREADS: 8` in `flow/config.yaml` exist for the same
reason: capping threads shrinks the peak working set (each thread holds its own regional
routing state), and checkpointing after every iteration means a crash loses one iteration
rather than the ~13 hours that one did.

## Smaller things

**`flow/final` can be a fossil.** LibreLane is passed `--save-views-to flow/final` and does
not reliably populate it: after a run that completed every step and every checker,
`flow/final` still held a GDS from a week earlier and had no `spice/` directory at all. Both
`make precheck` and `make sim-gl` were silently reading stale artifacts. `make sync-final`
now mirrors the newest completed run's own `final/` instead, and `make harden` calls it on
the way out.

**`VDD_PIN_VOLTAGE` is silently ignored.** It is a *removed* variable in the LibreLane 3.1
in this container ("Information should be obtained from dotlib files", `config/removals.py`).
Setting it is accepted without complaint and never reaches `resolved.json`. Check that file
rather than the config when a corner override looks like it did not take.

**`SYNTH_LATCH_MAP` is deleted from the PDK configuration.** The PDK ships the latch map and
points at it, but LibreLane's gf180mcu compatibility shim strips the key on the way in
(`config/pdk_compat.py`), so it has to be set again in `flow/config.yaml`.

**`make sw` in the submodule does not work here.** Its default recipe targets
`nexys-pin-table.csv`, an FPGA board pin table this port has no reason to track, and throws a
`KeyError` on `PERIO_UART1_TX` because this design's `N_UART` and `N_GPIO` diverge from what
that table assumes. `flow/synth/bootrom.sh` and `flow/synth/app.sh` regenerate the headers
against `gf180-pin-table.csv` directly instead.
