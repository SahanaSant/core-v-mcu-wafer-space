# Harden the design and sign it off

`make harden` runs LibreLane end to end: synthesis, floorplan, PDN, placement, design
repair, clock tree synthesis, routing, extraction, STA and the sign-off checkers. Sign-off is
a clean `make precheck`, not a clean `make harden`.

Budget most of a day. Run it with nothing else heavy on the machine; several stages hold
multiple gigabytes and an OOM near the end is expensive.

## The short version

```sh
make harden           # the full run
make precheck-image   # build the wafer.space submission checker (once)
make precheck         # check flow/final/gds/chip_top.gds against the submission rules
```

Use the patched OpenROAD image if you plan more than one run
([patched-openroad.md](patched-openroad.md)); without it, clock tree synthesis crashes on
roughly 99 attempts in 100 and you will be retrying it by hand.

```sh
make harden OSIC_IMAGE=iic-osic-tools:cts-fix
```

## Roughly how long each stage takes

| Stage | Time | Note |
| --- | --- | --- |
| Synthesis | ~9 min | |
| Floorplan, PDN | ~10 min | |
| Global placement | ~10 min | |
| `RepairDesignPostGPL` | ~63 min | Inserts ~65,000 buffers. Cost is structural and does not move with the clock target. |
| Clock tree synthesis | minutes | See the crash note below. |
| `ResizerTimingPostCTS` | ~10 min | This is the step that responds to the clock target. |
| Global routing | 1 min to hours | Highly variable; see [known-issues.md](../explanation/known-issues.md). |
| Detailed routing | ~3.5 min | |
| KLayout DRC | ~4 h | The slow one at the end. |

## Iterating without repeating everything

`ARGS=` passes flags straight through to LibreLane.

```sh
make harden ARGS="--to OpenROAD.PadRing"                  # stop early
make harden ARGS="--last-run --from OpenROAD.CTS"         # resume the previous run
make harden ARGS="--last-run --flow OpenInKLayout"        # open the previous run's layout
```

The floorplan steps take seconds and detailed routing takes minutes to hours, so iterating
with `--to` is how the configuration gets debugged.

Runs land in `flow/runs/RUN_<timestamp>/`. `make harden` finishes by running `sync-final`,
which mirrors the newest completed run's `final/` into `flow/final/`. That indirection
exists because LibreLane's own `--save-views-to` does not reliably populate the directory,
and `make precheck` and `make sim-gl` were silently reading a stale GDS as a result. Runs
stopped early with `--to` never write a `final/`, so they cannot be picked up by accident.

## Getting past `OpenROAD.CTS`

On the stock image this step will very likely crash. It is a known, root-caused OpenROAD bug
(TritonCTS null-dereferences on certain designs), not anything wrong with your setup. Two
ways through:

**Retry it.** `make harden-cts` resumes the last run and retries the CTS step until it
survives, up to 200 attempts. Then continue with:

```sh
make harden ARGS="--last-run --from OpenROAD.STAMidPNR-1"
```

The crash is intermittent rather than configuration-dependent, so give any single pass or
failure a real sample before drawing a conclusion from it.

**Patch it.** Build the image once per [patched-openroad.md](patched-openroad.md) and point
every target at it with `OSIC_IMAGE=iic-osic-tools:cts-fix`. CTS then passes like any other
step.

## Sign-off

```sh
make precheck-image   # clones and builds wafer-space/gf180mcu-precheck
make precheck
```

The precheck runs sixteen stages against the final GDS: top cell name and count, origin,
database units, maximum metal layer, slot dimensions, density, zero-area polygons, antenna
rules and DRC. A design is done when this passes.

`PRECHECK_THREADS` defaults to 1. `precheck.py`'s own default is `max`, which resolves to
`os.cpu_count()`, and KLayout's DRC holds per-thread copies of the intermediate layers: on a
20-thread host that grew to 9.15 GB resident and the kernel killed it four hours in. Raise it
only against measurement, and only with the machine otherwise idle.

## Checking the result yourself

Beyond the precheck, the numbers worth reading come from
`flow/runs/<RUN>/final/metrics.json` and the per-step logs. Every headline figure in
[reference/design.md](../reference/design.md) is sourced from there. The cell-class
breakdown in that document is reproduced with:

```sh
python3 flow/synth/buffer_report.py \
    flow/runs/<RUN>/02-yosys-synthesis/chip_top.nl.v \
    flow/runs/<RUN>/27-openroad-repairdesignpostgpl/chip_top.nl.v \
    pdk/gf180mcuD/libs.ref/gf180mcu_fd_sc_mcu7t5v0/lef/gf180mcu_fd_sc_mcu7t5v0.lef
```

Finally, run the gate-level simulation against the netlist you just built:

```sh
make sim-gl
```

## Starting over

```sh
make clean   # removes flow/runs, flow/final, flow/build and sim/sim_build; keeps the PDK
```
