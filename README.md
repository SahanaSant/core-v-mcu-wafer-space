# core-v-mcu-wafer-space

Port of the [OpenHW CORE-V MCU](https://github.com/openhwgroup/core-v-mcu) to GlobalFoundries
GF180MCU, for fabrication on a [wafer.space](https://wafer.space) shuttle slot using an
open-source RTL-to-GDS flow.

**Status: routed, DRC and LVS clean, timing not closed.** RTL, the LibreLane flow
configuration and `chip_top` all exist. `make harden` has carried the design all the way
through detailed routing, full-chip KLayout DRC and LVS with zero violations, and `make sim`
boots it from flash and prints over UART. What is not done is timing closure: the clock
target moved to 6 MHz to match the measured critical path, and detailed routing has not yet
converged at that target. See [Where this stands](#where-this-stands) for the numbers and the
runs they came from. The original research report is in
[docs/porting-analysis.md](docs/porting-analysis.md); its numbers are what motivated the
project, not what it measures today.

## Prerequisites

Docker or Podman, plus `git` and `make`. Nothing else is installed on the host. Every tool
runs inside a container.

## Setup

```sh
git clone --recurse-submodules <url> && cd core-v-mcu-wafer-space
make pdk      # fetch the pinned PDK into ./pdk (slow the first time, ~15 min)
make shell    # drop into the toolchain container, to poke around or sanity-check the setup
```

`make` on its own lists the available targets.

## Building the design, start to finish

```sh
make elaborate    # ~seconds: read the RTL through yosys-slang, list anything unresolved
make area         # ~10 min: synthesise to standard cells, report logic area
make sta          # ~2 min: report the critical path (needs `make area` first)
make bootrom      # build sw/bootrom and simulate it against the generated ROM image
make harden       # the real RTL-to-GDS run: floorplan, PDN, placement, CTS, routing
```

`make harden` is the long one. `ARGS=` passes flags straight through to LibreLane —
`ARGS="--to <step>"` stops early, `ARGS="--last-run --from <step>"` resumes a previous run
without repeating synthesis or design repair. Expect roughly: 9 min synthesis, 10 min
floorplan/PDN, 10 min global placement, 45 min design repair, then clock tree synthesis,
routing (minutes, not the hours once assumed) and sign-off checks — full-chip DRC is the
slow one at the end, and can run considerably longer depending on the machine.

### Getting past `OpenROAD.CTS`

**It will very likely crash the first time.** This is a known, root-caused OpenROAD bug
(TritonCTS null-dereferences on certain designs; full diagnosis and an upstream patch are in
[flow/openroad/README.md](flow/openroad/README.md)), not anything wrong with your setup. Two
ways through it:

- **Brute-force retry** (no rebuild needed): `make harden-cts` retries the CTS step until it
  survives (up to 200 attempts), then continue with
  `make harden ARGS="--last-run --from OpenROAD.STAMidPNR-1"`.
  Give any single pass or failure a real sample before trusting it — this crash is
  intermittent, not configuration-dependent.
- **Patched OpenROAD** (recommended if you're doing more than one run): build the patched
  image once per `flow/openroad/README.md`, then point every `make` target at it with
  `OSIC_IMAGE=iic-osic-tools:cts-fix` (or `make ... OSIC_IMAGE=iic-osic-tools:cts-fix`). CTS
  then passes like any other step, no retrying required.

```sh
make precheck-image   # build the wafer.space submission checker (once)
make precheck         # check flow/final/gds/chip_top.gds against submission rules
```

Sign-off is `make precheck`, not a clean `make harden`; see [Sign-off](#sign-off).

## Where this stands

Real, measured numbers, each from a named run rather than a projection. The last *complete*
run through `make harden` is `RUN_2026-08-16_04-34-36`, built against the original 100 ns /
10 MHz clock target:

- **Placement**: 25.9% standard-cell density at global placement, 43.5% after design repair
  inserts about 61,000 buffers — both under the 35% target LibreLane plans against (that
  target constrains the placement, not the post-repair netlist).
- **Global routing**: 0% overflow on every metal layer, 23.14% overall routing resource usage,
  154,541 nets routed.
- **Full-chip KLayout DRC: clean.** All 738 rules report `total: 0`, density `total: 0`. The
  197 metal3 spacing violations the first routed run found were real, and were a floorplan
  problem: the OCD SRAM macro's GDS runs metal3 flush to all four edges, contradicting its own
  LEF's declared 3 µm clean margin, so abutting the columns put neighbouring metal3 2-10 nm
  apart. `flow/macros.yaml` now opens a 1 µm gap and `flow/config.yaml` blocks routing over
  it. One accepted residual: the antenna deck found 9 `ANT.16_i_ANT.4` violations, a gap
  between OpenROAD's own antenna checker (which converged to zero) and KLayout's stricter
  deck. A margin increase is live in config but unverified against a complete run.
- **LVS: clean.** Circuits match uniquely, 164,340 devices and 163,281 nets on both sides,
  every `netgen` difference counter zero.
- **IR drop**: negligible. Worst case 26.2 µV on VDD / 29.1 µV on VSS, 0.00% of the 3.3 V rail,
  against the breakout PCB's 6/8/2/2 VDD/VSS/DVDD/DVSS pad split.
- **Timing does not close at 10 MHz.** Post-route STA at the slow corner (`max_ss_125C_3v00`)
  shows a real critical path of about 128.6 ns, 29% over budget, with roughly 12,500 setup
  violations design-wide and widespread max-slew and max-cap violations; `tt` and `ff` pass
  setup comfortably, so this is corner-specific. Hold is a much smaller, normal-scale problem.

The clock target is now **166.67 ns / 6 MHz**, which puts that same measured path back at
about 77% of budget. The clock is external, so this is a budget correction rather than
anything burned into silicon. **No complete route exists at 6 MHz yet**: detailed routing
plateaus rather than converging — violations drop fast through about iteration 3, then flatten
while each further iteration costs one to three hours. That is root-caused to localized
congestion, most plausibly where design repair's ~65,000 emergency buffers and the 73
hold-fix delay nets cluster, which points at the RTL's own broadcast fanout rather than at
flow configuration. It is the design's one open blocker.

- **RTL simulation passes end to end.** `make sim` boots `chip_top` from a real QSPI flash
  model through the boot ROM, checks the image CRC, jumps into L2, walks every SRAM bank
  read-write-read with individual byte enables, and prints over UART0. See
  [sim/README.md](sim/README.md).
- **Gate-level simulation elaborates and runs but does not pass**, because the only netlist
  available predates both the 6 MHz boot ROM and an L2 addressing fix. It needs a fresh
  harden, which is blocked on the routing above.
- **`make precheck` has never run against a real final GDS.** Sign-off is a clean precheck,
  not a clean `make harden`.

## Layout

```
core-v-mcu/     upstream CORE-V MCU (submodule, pinned)
rtl/gf180mcu/   GF180 technology cells: SRAM, clock gate, ROM, pads
rtl/chip/       chip_top, pad ring, upstream instantiation
flow/           LibreLane config, SDC, PDN, macro placement, OpenROAD patches
sim/            cocotb testbenches (RTL and gate level)
docs/           porting analysis
```

Each directory has its own README stating exactly what belongs in it. `pdk/` (fetched by
`make pdk`) and `openroad-build/` (built by following `flow/openroad/README.md`) are
gitignored, host-local build output — expect them to exist on disk but not in git.

## Pinned versions

Everything is pinned so results are reproducible. Override any of these on the `make`
command line.

| What | Value | Why |
| --- | --- | --- |
| `OSIC_TAG` | `2026.07` | IIC-OSIC-TOOLS image, carries LibreLane, OpenROAD, Magic, KLayout, netgen |
| `PDK` | `gf180mcuD` | 5 metal layers, the variant wafer.space fabricates |
| `PDK_COMMIT` | `f6eeac7d…` | Matches the wafer.space project template |
| `SLOT` | `1x1` | 3.93 × 5.12 mm die, 12.92 mm² core area |
| `SCL` | `gf180mcu_fd_sc_mcu7t5v0` | 7-track cells, 5 V oxide. The `5v0` is the oxide, not the supply: all 229 cells are characterised at 5.0 V, 3.3 V and 1.8 V. Ticket 14 runs them at 3.3 V |
| `SRAM` | `gf180mcu_ocd_ip_sram` | wafer.space's denser OCD macro, 1024×8 (ticket 11); the foundry's 512×8 `gf180mcu_fd_ip_sram` was the original plan, superseded |

The container ships its own PDK build. `make pdk` deliberately fetches the pinned commit into
`./pdk` instead, so the container image and the PDK version are independent.

## Sign-off

A design is done when it passes [gf180mcu-precheck](https://github.com/wafer-space/gf180mcu-precheck),
not when LibreLane finishes. Run `make precheck` before every submission attempt.

## Relationship to upstream

`core-v-mcu/` is a submodule that should point at **your fork** of `openhwgroup/core-v-mcu`,
since OpenHW requires pull requests to come from a fork. It currently points at upstream;
re-point `.gitmodules` once your fork exists.

Changes split in two:

- **Upstreamable** RTL (technology cells, parameterisation, making the eFPGA optional) is
  developed as commits on the submodule and submitted as pull requests. Contributors must be
  covered by the [Eclipse Contributor Agreement](https://www.eclipse.org/legal/ECA.php).
- **Shuttle-specific** work (flow config, pad ring, macro placement, slot markers) stays in
  this repository. It has no meaning upstream.

Keep the split honest. Anything that would help someone porting to a different PDK belongs
upstream.

## Licence

Apache-2.0 WITH SHL-2.1, matching upstream, so RTL moves between the two repositories without
a licence change. See [LICENSE.md](LICENSE.md).
