# KLayout DRC memory research

Originally a research task with `flow/config.yaml` left untouched. A follow-up session acted
on the findings, ran the fixes live against the real design, and got a first complete DRC
pass — see [Update: what actually worked, end to end](#update-what-actually-worked-end-to-end)
at the bottom for the final, verified state; the sections below are the original research and
are kept as-is for the reasoning trail.

## What happened

`make harden`'s `KLayout.DRC` step (162 GF180MCU rule decks against `chip_top`'s full GDS)
triggered a sustained, escalating out-of-memory cascade that took down the host desktop
session — `journalctl -k` showed the OOM killer taking out `pipewire`, `wireplumber`,
`xdg-desktop-portal`, `dbus-broker`, and `systemd --user` itself, alongside the `klayout`
process. Full incident narrative: `HANDOFF.md` (now likely deleted per its own instructions)
and `README.md`'s "Full-chip DRC/LVS sign-off" note. Host: 20 hardware threads (`nproc`), 15
GiB RAM, chronically under 5 GB free at idle (`free -h` at research time: 773 MiB free, 3.2
GiB "available", 12 GiB already used with nothing heavy running).

One directly measured artifact survived the incident: `flow/runs/RUN_2026-08-14_20-23-37/
297-klayout-drc/klayout-drc.log`, timestamped this morning (08:16–08:17 EDT), 81 lines, then
silence — no shell error, no Ruby exception, the process log simply stops. This is treated as
primary evidence throughout this document and is discussed in detail under Question 1 and the
"what actually killed it" note, because it complicates the "workers: max is obviously the
whole story" framing this task started from.

## Question 1: how do `workers` and `threads` get passed down to KLayout?

**Confirmed from primary source.** Two layers are involved: LibreLane's Python step, and the
GF180MCU PDK's own Ruby DRC runset (which LibreLane treats as an opaque script it only passes
`-rd key=value` flags to).

**LibreLane** (`/usr/local/lib/python3.12/dist-packages/librelane/steps/klayout.py` inside the
`iic-osic-tools:cts-fix` container image, package `librelane 3.1.0.dev2`, confirmed via `pip
show librelane`): `KLayout.DRC.run_gf180mcu` builds the KLayout invocation as

```python
opts = []
if self.config["KLAYOUT_DRC_OPTIONS"]:
    for k, v in self.config["KLAYOUT_DRC_OPTIONS"].items():
        opts.extend(["-rd", f"{k}={v}"])

threads = self.config["KLAYOUT_DRC_THREADS"] or str(_get_process_limit())
if threads != "1":
    opts.extend(["-rd", f"threads={threads}"])

self.run_subprocess(["klayout", "-b", "-zz", "-r", drc_script_path,
                      "-rd", f"input={abspath(input_view)}",
                      "-rd", f"topcell={self.config['DESIGN_NAME']}",
                      "-rd", f"report={abspath(lyrdb_report)}",
                      *opts])
```

Every key in `KLAYOUT_DRC_OPTIONS` (`decks`, `variant`, `workers`, or anything else the runset
accepts) is forwarded verbatim as a KLayout `-rd` variable — LibreLane does not interpret
`workers` or `decks` at all; it is pure passthrough to the PDK's runset. `_get_process_limit()`
(`librelane/common/misc.py`) is `int(os.getenv("_OPENLANE_MAX_CORES", os.cpu_count() or 1))` —
unset here, so it resolves to `os.cpu_count()` (20 on this host). One quirk worth flagging: the
`threads != "1"` check compares against the *string* `"1"`, but `KLAYOUT_DRC_THREADS` is typed
`Optional[int]`, so a YAML value of `1` resolves to the Python int `1`, and `1 != "1"` is `True`
in Python — the "skip passing threads=1" branch is effectively dead code whenever the value is
set explicitly. In practice this works in this repo's favor: the observed log line "Number of
threads for DRC functions: 1" confirms `-rd threads=1` really was passed and really did take
effect, despite the comparison bug. (Directly confirmed from the incident log, not just code
reading — good thing, because code reading alone pointed at the wrong conclusion here.)

**The GF180MCU runset** (`pdk/ciel/gf180mcu/versions/f6eeac7dad085ffcc829ccfd721f7b4ce39edcf7/
gf180mcuD/libs.tech/klayout/tech/drc/`, fetched by `make pdk`, so this is the actual deck this
repo runs, not a generic example) receives `workers` and `threads` as KLayout global variables
(`$workers`, `$threads`) and resolves them in `options.rb`:

```ruby
def resolved_parallel(base_params)
  PARALLEL_PARAMS.to_h do |key|
    value = base_params[key]
    resolved = value.to_s == 'max' ? Etc.nprocessors : value.to_i
    [key, resolved]
  end
end
```

`Etc.nprocessors` is Ruby's hardware-thread count — `workers: max` and `threads: max` both
resolve to literal `os.cpu_count()`-equivalent, no cap, no headroom reservation. The runset's
own `DEFAULTS` are `workers: '1', threads: 'max'` — i.e. if `KLAYOUT_DRC_THREADS` were ever
*absent* from the LibreLane invocation (which the "1" != "1" bug above happens to avoid), the
runset's own default is "all cores," not "1." Worth knowing if that comparison bug is ever
"fixed" upstream — this repo's `KLAYOUT_DRC_THREADS: 1` would need to keep working after such a
fix, which it would, since removing the bug only means `-rd threads=1` stops being redundantly
skipped for values that aren't literally 1.

`gf180mcu.drc`'s main script then does, in order: load the GDS (`source`), call `threads
(opts.threads)`, select `deep`/`flat`/`tiling` mode (`opts.run_mode`, default `'deep'`),
unconditionally read and count every technology-defined layer
(`GF180DRC::GenericLayers.extract_layers_from_design`), unconditionally build derived generic
layers, conditionally build full-chip connectivity + a device-level netlist if any selected
deck's tags require it (`dnwell`, `ldnmos`, `ldpmos`, `lvpwell`, `nat`, `nwell` — several of
which are in this run's deck selection), and only *then* construct a runner:

```ruby
runner = if opts.workers > 1
           RuleFramework::Runners::Parallel.new(ctx, num_workers: opts.workers)
         else
           RuleFramework::Runners::Sequential.new(ctx)
         end
runner.run(opts.decks)
```

Everything before `runner.run` happens exactly once, in a single process, regardless of
`workers`. This matters a great deal for Question 4 and for reading the incident log correctly.

## Question 2: does each worker hold its own full copy of the layout?

**Confirmed from primary source (the runset's own code) and cross-confirmed by the KLayout
maintainer on the KLayout forum.** `RuleFramework::Runners::Parallel#run_all`
(`rule_framework.rb`) spawns workers with Ruby's `fork`, not threads:

```ruby
def fork_worker(id)
  result_r, result_w = IO.pipe
  pid = fork do
    result_r.close
    result = execute_deck(id)
    result_w.write(JSON.dump(result))
    result_w.close
    exit
  end
  result_w.close
  [pid, result_r]
end
```

`fork(2)` on Linux is copy-on-write: each worker starts as a page-level *shared* snapshot of
whatever the parent process had already loaded (the full GDS, all generic layers, and — if
triggered — the connectivity netlist), and only diverges from the parent (and from sibling
workers) as it writes to those pages. So the honest answer is "shared at fork time, diverging
under write pressure," not "N independent full copies from the start." This is deliberate PDK
design, not an accident: the KLayout maintainer (Matthias Köfferlein) states on the official
forum, discussing this exact class of parallel-DRC-worker design —

> "I'd not try parallelization inside the application. Qt and large parts of the application
> are not thread-safe." … "A subprocess is easy to kill." … "The sharing of memory creates too
> many issues and I don't want to waste my time with hunting rare glitches."
> — https://www.klayout.de/forum/discussion/2839/drc-scripts-reports-and-parallelism

and a forum participant (username "Scafir" — plausibly the same author lineage as this PDK's
`rule_framework.rb`, given the near-identical fork/COW design) reports:

> "I could get more than 2x improvement in ram usage compared to fully separated processes
> (due to Copy on Write)."
> — same thread

"More than 2x" is a real saving, not a free lunch: it implies COW does *not* hold for most of a
worker's run once it starts computing derived (sized/booleaned/merged) regions for its one
assigned rule — each such operation writes new shape data, which is exactly what forces a COW
page copy. With 20 concurrent workers each independently deriving regions from a base layout
that includes a 17.7M-polygon `contact` layer and an 8.7M-polygon `metal1_drawn` layer, peak
resident memory should be expected to land well above "1 copy" and meaningfully below "20
copies," but there's no primary-source number for exactly where in that range — that's
workload-dependent and would need to be measured, not looked up.

**Threads within a worker**, separately: KLayout's own DRC reference documents `threads(n)` as
distributing *tiles* across CPU cores — "If using threads, tiles are distributed on multiple
CPU cores for parallelization. Still, all tiles must be processed before the operation proceeds
with the next statement." (https://www.klayout.de/doc-qt5/about/drc_ref_global.html, fetched
via WebFetch). This is intra-process, shared-memory parallelism — the opposite of `workers`'
process-per-unit isolation — and its applicability is explicitly *tiling-mode* framed. This
run's `run_mode` is `deep` (the runset default), not `tiling`, so `threads(opts.threads)`'s
practical effect in this specific run is unclear from documentation alone; the log confirms the
value (1) was passed and logged, but not what if anything it changed given the mode. Flagged as
**inferred, not confirmed**: `threads` in this run most likely had little effect regardless of
its value, because deep mode is not the tiling engine `threads()` is documented against.

`deep` mode itself: "In deep mode, the operations will be performed in a hierarchical fashion.
Sometimes this reduces the time and memory required for an operation, but this will also add
some overhead for the hierarchical analysis." (same KLayout doc page). Crucially,
`generic_layers.rb` shows the runset changes behavior based on this exact flag:

```ruby
merge = (ctx.options.run_mode != 'deep')
...
ps = ctx.drc.polygons(layer, datatype)
merge ? ps.merged : ps
```

In `deep` mode (this run), every layer is registered **unmerged** — the `contact` layer's
17,743,113 individual polygon shapes are kept exactly as drawn, relying on the hierarchical
engine to manage them cell-by-cell rather than collapsing them into a smaller flat shape count
up front. In `flat` or `tiling` mode, `.merged` runs immediately, which for a design like this
(regular contact/via arrays, large metal pours) would very plausibly reduce the working shape
count substantially before any rule even runs. This is **confirmed from the runset's own
source**, not inferred — but its actual memory impact on this specific design is not measured,
only architecturally plausible.

## Question 3: what does `workers: max` concretely resolve to, and is there a documented warning?

**Confirmed, with a directly measured number.** `workers: max` → `Etc.nprocessors` in the
runset (Ruby's hardware-thread count) → the incident log states outright:

```
Number of parallel workers: 20
Number of threads for DRC functions: 1
```

So on this exact host, `workers: max` is not a theoretical concern — it measurably resolved to
20 concurrent forked processes for this exact run.

No warning of "workers: max is memory-unsafe" was found in LibreLane's own source
(`klayout.py`'s `Variable` docstrings for `KLAYOUT_DRC_OPTIONS` / `KLAYOUT_DRC_THREADS` say
nothing about memory) or in LibreLane's GitHub issues (a WebSearch across `The-OpenROAD-Project/
OpenLane` and `KLayout/klayout` issues found no issue specifically about `workers: max`). The
only in-repo warning is this project's own `flow/config.yaml` comment (sourced from the
wafer.space project template, per the file's own header) and the runset's `options.rb` help
text ("Number of parallel workers. 'max' for number of available cores") — neither states a
safety ceiling, both simply document what "max" means.

**Related, and itself a documented prior-art warning about KLayout+LibreLane RAM use on large
designs generally** (not `workers` specifically): OpenLane issue
[#1721](https://github.com/The-OpenROAD-Project/OpenLane/issues/1721), "Too much RAM usage on
drc_rosetta.py" — reports that for designs over 100k cells, the `tr_to_klayout` GDS-conversion
step alone (not even DRC) peaks over 60 GB RAM, because "every one of these functions creates
the whole database in RAM and writes it back after it is finished." Different step, same
underlying pattern (KLayout's Python/Ruby scripting layer building a whole in-memory database
rather than streaming) — treated as **confirmed prior art of the general failure mode**, not as
evidence about `workers` specifically.

## Question 4: what would materially cut peak memory for this run?

Every item below is evaluated against what the incident log actually shows, which is important:
**the process died in the single-process setup phase, before any of the 20 workers were ever
forked.** The log's last lines are

```
14:17:21 : Memory Usage (752732K) : contact has 17743113 polygons
14:17:22 : Memory Usage (752924K) : metal1_drawn has 8724078 polygons
14:17:22 : Memory Usage (752924K) : metal1_slot has 0 polygons
14:17:23 : Memory Usage (752924K) : metal1_dummy has 165915 polygons
```
— then nothing. No "Rule requiring connectivity detected…" line (which the connectivity build
step logs before running), no "Setup took N seconds," no "Starting DRC in isolated parallel
mode" (which `RuleFramework::Runners::Parallel#run` logs as its first act). Reported RSS at the
last line is ~735 MB — small in absolute terms — meaning whatever consumed the rest of 15 GB did
so in the gap after that line, in code that logs no incremental progress: the remaining
technology layers, `compute_generic_layers`, and/or (since this run's deck selection includes
`dnwell`, `nat`, `lvpwell` — all in `CONNECTIVITY_RULES`) `GF180DRC::Connectivity.build` +
`netlist`, which walks connectivity across exactly the two largest layers just logged (`contact`
↔ `metal1_drawn` ↔ `via1` ↔ `metal2_drawn`, per `connectivity.rb`'s `BASE_CONNECTIONS`). This is
**inferred, not confirmed** — the log doesn't name the exact culprit line — but it is the most
plausible reading of "next thing after this exact log tail is either finish reading ~15 more
layers, run pure-Ruby derived-layer math, or build a full-chip netlist across the two biggest
layers in the design," combined with "the process disappeared with no further output."

**This means `workers` and `threads` may not have been the proximate cause of *this specific*
crash at all** — a single non-parallel KLayout process, in `deep` mode, appears to have run out
of memory before parallelism ever entered the picture. `HANDOFF.md`'s account ("3 of 162 rule
decks completed") does not match this log (no deck ever started per this log's evidence) —
noted as a discrepancy between the two sources rather than resolved; this log is the more direct
primary evidence of the two, dated this morning, but it's worth someone checking whether a
*different*, later attempt (not recorded in `flow/runs/`) is what HANDOFF.md's "3 of 162"
figure refers to.

Given that, the concrete levers, in descending order of confidence:

1. **Lower `workers`.** Still correct and still worth doing — 20 concurrent forked processes
   each independently running `deep`-mode region math over a 17.7M/8.7M-polygon base layout is
   a real risk even if it wasn't what killed *this* run, and per the KLayout maintainer's own
   guidance this is the intended, safer-than-threading design; it just isn't free. Confirmed
   mechanism (fork+COW), inferred safe value (no primary source gives a number for this design).

2. **`run_mode: flat` or `run_mode: tiling` instead of the default `deep`.** Directly relevant
   to what plausibly killed this run, since `deep` mode is what causes every layer — including
   the 17.7M-polygon `contact` layer — to load **unmerged** (`generic_layers.rb`'s `merge =
   (run_mode != 'deep')`). This is a `KLAYOUT_DRC_OPTIONS` key (`run_mode`), not currently set
   in `flow/config.yaml`, so it currently takes the runset's own default (`deep`). The KLayout
   forum independently confirms tiling's memory profile: "In tiling mode, the memory
   requirements are usually smaller (depending on the choice of the tile size) and multi-CPU
   support is enabled." (drc_ref_global docs). Confirmed as a documented option; not confirmed
   whether `tiling` mode is fully exercised/tested for every rule in this specific PDK's decks
   (the runset's own `README.md` and code only mention tiling as a supported top-level mode, no
   PDK-specific caveats found). This is the single highest-leverage untried lever, because it's
   the one thing that changes the setup-phase behavior that the log shows actually failed.

3. **Batching the 162 decks across multiple `klayout` invocations is possible but only
   partially helps, and there's no LibreLane config knob for it.** `KLAYOUT_DRC_OPTIONS.decks`
   accepts a comma-separated tag expression (`"all,-antenna,-density,-cup"`), and the runset's
   tag system (`tags: %w[all feol contact]` etc., visible throughout `rule_decks/*.rb`) supports
   arbitrary subsets — e.g. running `decks: "feol"`, then `decks: "beol"`, then `decks:
   "contact"` as three separate `make harden ARGS="--from KLayout.DRC --to KLayout.DRC"` runs
   with three different `flow/config.yaml`s (or, more simply, three direct `klayout -b -r
   gf180mcu.drc -rd decks=... -rd input=... -rd report=...` invocations against the GDS
   LibreLane already produced, at e.g. `flow/runs/<run>/293-klayout-filler/chip_top.gds` per
   this run's own log). **But** `extract_layers_from_design` reads and counts *every*
   technology-defined layer unconditionally, regardless of which decks are selected — confirmed
   directly from `generic_layers.rb`'s structure and cross-checked against the log (all 67
   named layers were being read in sequence with no deck-selection filtering visible before the
   process died). So batching reduces the number of concurrently-forked workers at the *rule
   execution* phase, but does **not** reduce the one-time setup cost that this incident's
   evidence points at — each batch would redo the same full-layout read and (if its deck subset
   still touches connectivity-tagged layers) the same netlist build. Worth doing for the
   worker-multiplication risk; not a substitute for addressing setup-phase cost.

4. **`.forget` is already used, but only within rule decks, not at the framework level.**
   Individual deck files (`dnwell.rb`, `guard_ring.rb`, `dummy_comp.rb`, etc.) call `.forget` on
   their own intermediate derived layers once a rule's check is done — confirmed by grep across
   `rule_decks/*.rb` (dozens of call sites). This is memory hygiene *within* a single deck's
   lifetime, already present in the PDK's own decks, and not something this repo needs to add.
   It does not touch the generic/base layers computed once up front (those live in `ctx` for the
   whole run, by design, since every deck needs access to them).

5. **Bound total memory with a container-level cgroup limit (`podman --memory`), so an OOM
   degrades gracefully instead of taking the host down.** Confirmed available on this host:
   `podman info` reports `CgroupManager: systemd` and `/sys/fs/cgroup/cgroup.controllers`
   includes `memory` (cgroup v2, memory controller present — rootless podman can enforce
   `--memory` here). `run.sh` (the script every `make` target invokes to enter the toolchain
   container) currently sets no memory limit at all on its `podman run` / `docker run` call.
   Adding e.g. `--memory=12g --memory-swap=14g` there would mean a future OOM kills processes
   *inside the container's cgroup* (klayout, its forked workers) under kernel enforcement, not
   the host's global OOM killer picking off arbitrary host session processes by heuristic score
   — which is exactly what took out `pipewire`/`systemd --user` last time. This is the one
   mitigation that changes the *failure mode* rather than trying to avoid triggering it; it's a
   `run.sh` change, not a `flow/config.yaml` change, so it's called out separately below.

## Question 5: prior art on full-chip signoff DRC on ~16 GB RAM machines with tens-of-millions-of-polygon designs

No LibreLane issue, KLayout mailing list thread, or GitHub discussion was found addressing this
combination directly (16 GB, tens-of-millions of polygons, full-chip signoff DRC) as a named
scenario. What was found, all via WebSearch/WebFetch against klayout.de and github.com:

- KLayout forum, "DRC scripts, reports and parallelism"
  (https://www.klayout.de/forum/discussion/2839/drc-scripts-reports-and-parallelism) — the
  fork/COW discussion quoted under Question 2. General guidance on parallel DRC workers, not
  specific to a memory ceiling.
- KLayout forum, "KLayout DRC on large layouts"
  (https://www.klayout.de/forum/discussion/2806/klayout-drc-on-large-layouts) — general memory
  advice: prefer sized-layer booleans over long-distance separation checks ("Long-distance
  separation checks... usually screw up performance as the number of interactions grows roughly
  quadratic with the interaction distance"), and use `.forget` between rule stages. No specific
  RAM-size guidance.
- KLayout GitHub issue [#2299](https://github.com/KLayout/klayout/issues/2299), "gf180mcu DRC
  performance regression" — a *different* problem (10x runtime regression between KLayout
  0.30.5 and 0.30.6/0.30.7 on this same PDK's deck), not a memory issue, but useful prior art
  that this exact PDK's DRC deck has a history of being sensitive to KLayout point-release
  behavior changes. Worth checking the container's KLayout version against this if DRC behavior
  ever looks anomalous again.
- OpenLane issue [#1721](https://github.com/The-OpenROAD-Project/OpenLane/issues/1721) —
  discussed under Question 3, general "whole database in RAM" pattern for large designs.

No source recommended a specific RAM floor for full-chip GF180MCU DRC, and none discussed
running it on hardware as constrained as 15 GB alongside a live desktop session. The absence
itself is notable: this appears to be an under-documented combination, not a solved one.

## Recommended `flow/config.yaml` changes

Not applied — the user decides. Proposed starting point:

```yaml
KLAYOUT_DRC_THREADS: 1

KLAYOUT_DRC_OPTIONS:
  decks: "all,-antenna,-density,-cup"
  variant: ref::$PDK
  workers: 4
  run_mode: flat

KLAYOUT_DENSITY_OPTIONS:
  decks: "density"
  variant: ref::$PDK
  workers: 4

KLAYOUT_ANTENNA_OPTIONS:
  decks: "antenna"
  variant: ref::$PDK
  workers: 4
```

- **`workers: 4`** (down from `max` = 20). Caps concurrent forked full-database copies at 4
  instead of 20 — per Question 2, each is COW-shared at fork but diverges under write pressure,
  so this bounds worst-case multiplication to a number that leaves real headroom on a 15 GB
  host, rather than one sized to hardware thread count. 4 is a starting guess, not a measured
  optimum — there is no primary source giving a safe number for this design; treat it as the
  first value to try and adjust from, not a proven ceiling. Applied to `DENSITY` and `ANTENNA`
  too for consistency, though those runs are far smaller (single-tag deck selections) and less
  likely to be the risk.
- **`KLAYOUT_DRC_THREADS: 1`** unchanged — already confirmed working as intended (log evidence
  under Question 1), and per Question 2's `threads()`/tiling-mode reading, raising it would only
  plausibly help if `run_mode` also moves off `deep`.
- **`run_mode: flat`** (new key, not currently set — currently defaults to the runset's own
  `deep`). This is the change most directly aimed at what the incident log's evidence points at:
  `deep` mode loads every layer, including the 17.7M-polygon `contact` layer, **unmerged**
  (Question 4, item 2). `flat` forces immediate `.merged` calls at layer-registration time,
  which should reduce the working shape count before any rule runs, at the cost of losing deep
  mode's hierarchical time/memory benefits for rules where hierarchy actually helps. `tiling` is
  the KLayout-documented lower-memory alternative to both and is worth trying too (`run_mode:
  tiling`, possibly with an explicit tile size) if `flat` alone isn't enough — not proposed as
  the first try here only because it changes more behavior at once (borders, per-tile
  reprocessing) and `flat` is the more surgical first step given deep mode's specific role in
  the evidence.
- Not changing `decks` — batching would reduce worker-phase risk but not the setup-phase cost
  the log points at (Question 4, item 3), so it's not worth the operational complexity as a
  first move. Revisit if `workers: 4` + `run_mode: flat` still isn't enough headroom.

**Separately, not a `flow/config.yaml` change:** add a memory ceiling to the container
invocation in `run.sh` (the `podman run` / `docker run` call every `make` target goes through),
e.g. `--memory=12g --memory-swap=14g` on the `podman run` branch. Confirmed viable on this host
(cgroup v2, memory controller present, systemd cgroup manager). This doesn't prevent an OOM but
changes who dies when one happens — the container's cgroup instead of the host's session
processes — which is the difference between "klayout crashes, rerun it" and "reboot the desktop
session."

## Before you run this again — operational checklist

- `free -h` immediately before starting. If "available" is already under ~4 GB, don't start —
  close something first. (At research time: 773 MiB free, 3.2 GiB available, with nothing heavy
  running — this host runs tight even at idle.)
- If the `run.sh` memory-limit change above hasn't been applied, treat that as the highest
  priority to add before the next attempt — it's what determines whether a repeat failure stays
  contained to the container or takes the desktop down again.
- Watch memory during the run, not just at the start: `watch -n5 free -h` in another terminal,
  or `podman stats` if running one container. The incident log shows RSS at only ~735 MB one
  second before the process disappeared — a poll interval much coarser than a few seconds could
  miss the actual spike entirely, which is a plausible explanation for why the prior session's
  20-second watchdog didn't fire in time.
- Given Question 4's finding that the setup phase (layer read + possible connectivity/netlist
  build), not the 20-worker fork, is the more likely proximate cause in the one incident log
  available, don't assume `workers: 4` alone fixes it — watch specifically for a stall/spike
  right after the `contact` and `metal1_drawn` layer-count log lines, before any "Starting DRC
  in isolated parallel mode" line appears. If it recurs at that exact point even with `workers:
  4`, that's confirmation the setup phase (and thus `run_mode`) is the real lever, not worker
  count.
- If it's going to be re-run with the same settings as last time on purpose (e.g. to reproduce
  before trying a fix), do it deliberately and alone — nothing else memory-heavy running, and
  ideally with the `run.sh --memory` cap already in place so a repeat doesn't repeat the
  desktop-session damage too.
- `flow/runs/*/297-klayout-drc/klayout-drc.log` (or wherever the new run directory numbers it)
  is ground truth for what actually happened, the same way `resolved.json` is ground truth for
  config — read it, don't infer from exit codes alone, since (per this incident) the process can
  disappear with no error message at all.

## Update: what actually worked, end to end

A later session acted on this research live, against the real host and the real design, over
several hours of iteration. The short version: `run_mode: flat` (this document's original
recommendation) does fix the crash, but it was the wrong fix — `run_mode: deep`, the runset's
own default, turned out both faster and dramatically lighter on memory once given enough
headroom to survive its setup phase. Full path, in order:

1. **Applied this doc's two recommendations** (`workers: 4`, `run_mode: flat`) and added the
   `run.sh` memory cap (`--memory`/`--memory-swap`, now real — see
   [run.sh](#container-memory-cap-now-real) below). Re-ran the full 156-deck (non-connectivity)
   set: it got past the exact point that killed the original run, then died later, at
   `V1.3c`, from a *different* memory source than Question 4 had found — not the connectivity
   netlist build (that was correctly excluded), but flat mode's per-worker COW divergence
   during actual rule execution, confirmed via `journalctl -k`
   (`constraint=CONSTRAINT_MEMCG`) as a clean, contained kill each time — the host was never
   endangered again after the `run.sh` cap went in, across six total contained OOM kills that
   night.
2. **Lowered `workers` progressively** (4 → 2 → 1/sequential) chasing the same crash. Each
   attempt got further, and the sequential (workers: 1) run's own log directly measured the
   fixed cost of flat mode's setup phase: `# Setup took 787.77 seconds`, ~7.6 GB, *for a single
   selected deck* — confirming the cost is dominated by something closer to a fixed
   per-invocation cost (scanning/registering the full 156-deck rule graph regardless of
   selection) than a per-deck one, which is why smaller batches didn't buy proportionally more
   headroom.
3. **Raised the container cap** (`MEMORY_LIMIT=13g MEMORY_SWAP_LIMIT=24g` via `run.sh`'s
   override, see below) and isolated the single deck that kept killing every batch (`V1.3c`,
   `via.rb`'s "min. via spacing between arrays" rule) on its own. It completed cleanly —
   `DRC RESULT: SUCCESS (0 violations)`, 18m31s, peak ≈9.6 GB — proving flat mode's problem was
   headroom, not a broken rule.
4. **Retried the full 156-deck set at the raised cap, still in flat mode.** It got past
   `V1.3c` this time, but stalled for ~30 minutes on the very next slow deck (`V1.3d`) with CPU
   time climbing (genuinely computing, not hung) and memory flat — a *runtime*, not memory,
   problem. Reading `V1.3d`'s actual KLayout operations (`via_rule_3d` in `via.rb`) showed why:
   ~8 chained boolean/edge derived-layer operations, all short-range (0.04–0.06 µm), the kind
   of rule that gains enormously from KLayout's hierarchical (`deep`) engine reusing computation
   across a design's massively repetitive standard-cell-level via/metal patterns — and gains
   nothing from `flat` mode, which forfeits that reuse entirely to keep memory down.
5. **Tested `run_mode: deep` (the PDK runset's own default) at the same raised cap**, first on
   `V1.3d` alone (13m36s total, peak ≈3.4 GB — lighter *and* faster than flat mode's `V1.3c`
   run), then on the **full 156-deck non-connectivity set**: completed in **2h56m**, peak memory
   under 5 GB throughout, zero crashes. First time this design has ever completed a full DRC
   pass. Result: `DRC RESULT: FAILURE (197 violation(s))` — `M3.2a` (min. metal3 spacing): 196,
   `M3.2b` (spacing to wide metal3): 1, every other rule across all 156 decks clean. Both are
   genuine metal3 routing spacing violations in `metal.rb`'s own rules
   (`metal_drawn.space(min_space.um, euclidian)`), not a tooling artifact — worth noting
   OpenROAD's own internal DRC check after detailed routing had reported 0 violations, so this
   is a real gap between OpenROAD's router-side checker and full KLayout signoff on metal3
   specifically. Report: `flow/runs/*/<klayout-drc ordinal>/reports/drc.klayout.{lyrdb,json}`.
6. **The 6 connectivity-tagged decks** (`dnwell`, `ldnmos`, `ldpmos`, `lvpwell`, `nat`, `nwell`
   — the ones that trigger the full-chip netlist build under Question 4) were run separately,
   in deep mode, at the same raised cap, since that netlist build was never re-tested outside
   `flat` mode. Clean: the netlist build itself peaked around 4.3 GB (vs. flat mode's ~11.4 GB
   for the same phase), and all 6 decks passed — `DRC RESULT: SUCCESS (0 violations)`, 31m44s
   total. Deep mode's advantage held for the connectivity/netlist path too, not just plain
   rule execution.

**Combined result, all 162 decks (156 + 6 connectivity; `antenna`/`density`/`cup` are separate
checker categories, not part of this DRC decks run): 197 violations total, all in the
non-connectivity batch** — `M3.2a` (196) and `M3.2b` (1), both minimum-metal3-spacing rules.
Every connectivity/device-recognition rule and every other DRC rule across the whole deck set
passed clean. Full reports: `flow/runs/*/306-klayout-drc/reports/` (156-deck run) and
`flow/runs/*/307-klayout-drc/reports/` (connectivity run) under
`flow/runs/RUN_2026-08-14_20-23-37/`.

### Container memory cap, now real

`run.sh` now sets `--memory`/`--memory-swap` on every container run (default 12g/14g),
overridable per-invocation via `MEMORY_LIMIT`/`MEMORY_SWAP_LIMIT` env vars — this is the
mechanism this document's original "not a `flow/config.yaml` change" recommendation described.
It did exactly its job across every crash logged above: `journalctl -k` shows
`oom-kill:constraint=CONSTRAINT_MEMCG` scoped to the container's own cgroup every time, and the
host recovered to double-digit GB free within seconds of each kill — a sharp contrast to the
original incident's `pipewire`/`systemd --user`-killing cascade. The runs above that needed
more than the 12g/14g default used `MEMORY_LIMIT=13g MEMORY_SWAP_LIMIT=24g` (single-deck tests)
or `...=30g` (the full 156-deck run, for extra swap margin); 13g/30g is a reasonable starting
point for a repeat of the full run on this host, not a proven-minimal number.

### Current `flow/config.yaml`

`KLAYOUT_DRC_OPTIONS` now omits `run_mode` (so it uses the runset's own `deep` default) and
sets `workers: 1` — the exact configuration verified above, not a guess. Higher `workers`
values were never re-tested under `deep` mode; deep mode's much lower memory footprint makes
it plausible that `workers: 2` or `4` would also fit comfortably and cut wall time further,
but that's untested, not recommended here.

### A second, different OOM: contained cap doesn't help against host-wide contention

Ticket 29's `OpenROAD.DetailedRouting` run was killed overnight (2026-08-18, ~20:53 EDT), and at
first glance it looked like this document's fix had regressed: `journalctl -k` showed
`Out of memory: Killed process ... (openroad) ... oom-kill:constraint=CONSTRAINT_NONE,...,
global_oom` -- not `CONSTRAINT_MEMCG` like every kill this document's "what actually worked" run
logged. It hadn't regressed. `openroad`'s own RSS at the time was ~5.5 GB, nowhere near the
container's 12g cap -- the container was never the resource that ran out.

**The mechanism this document's fix doesn't cover**: `--memory=12g` bounds what the container's
cgroup is *allowed* to use, but doesn't *reserve* that memory for it. If everything outside the
container -- the desktop session, other tools, other agent sessions, unrelated builds -- is
already consuming most of the host's real 15 GB, the container's own usage can still be well
under its cap while the *host* runs out of physical RAM+swap. When that happens the kernel's
global OOM killer fires (`constraint=CONSTRAINT_NONE`), not the per-cgroup one, and it picks
whatever process has the largest RSS system-wide, container or not -- which on this host is
usually whatever `make harden` is currently running, simply because it has the biggest single
footprint, not because it did anything wrong.

Confirmed live, immediately after retrying the crashed run: host `free -h` was down to 218 MiB
free / 2.9 GiB available with `openroad` only at 3.8 GB RSS and climbing, because a concurrent,
entirely unrelated `bazel` build (JVM, ~1.1 GB RSS, a different project's workspace) had started
at the same time as the retry, on top of the usual desktop load (Zed ~1.1 GB, Firefox several
hundred MB across processes, Discord ~366 MB, one or more `claude`/agent-sdk sessions each a few
hundred MB). None of this is inside the toolchain container or under this repo's control.

**Practical takeaway**: the `run.sh` memory cap is real and does its job for the failure mode it
targets (the container's *own* workload ballooning), but it is not a substitute for the
operational checklist above (`free -h` before starting, `available` under ~4 GB means don't
start) -- that checklist has to account for the whole host, not just what the container might do.
A long unattended `make harden`/`make precheck` run sharing a 15 GB host with an active desktop
session and other concurrent tools is realistically going to re-hit this unless something
outside the container's control (closing other memory-heavy apps, not scheduling concurrent
builds) also holds.

### Swap, for the record

The host's btrfs-backed swapfile (`/swap/swapfile`, 16 GiB) is correctly configured and
working — clean single-extent activation at boot (`Adding 16777212k swap on
/swap/swapfile. ... extents:1`), no errors in a week of `journalctl -k`. It was never the
bottleneck: every OOM kill during this investigation was the container's own cgroup swap
ceiling (`--memory-swap` minus `--memory`) being hit, confirmed directly in `journalctl -k`
(`swap: usage 2097152kB, limit 2097152kB` = exactly the 2 GB the original 12g/14g cap allowed),
not the host's real ~10+ GB of free swap running out.
