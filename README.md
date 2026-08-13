# core-v-mcu-wafer-space

Port of the [OpenHW CORE-V MCU](https://github.com/openhwgroup/core-v-mcu) to GlobalFoundries
GF180MCU, for fabrication on a [wafer.space](https://wafer.space) shuttle slot using an
open-source RTL-to-GDS flow.

**Status: skeleton.** No RTL or flow configuration written yet. The porting analysis that
defines the work is in [docs/porting-analysis.md](docs/porting-analysis.md); read it first.

## Prerequisites

Docker or Podman, plus `git` and `make`. Nothing else is installed on the host. Every tool
runs inside a container.

## Setup

```sh
git clone --recurse-submodules <url> && cd core-v-mcu-wafer-space
make pdk      # fetch the pinned PDK into ./pdk (slow the first time)
make shell    # drop into the toolchain container
```

`make` on its own lists the available targets.

## Layout

```
core-v-mcu/     upstream CORE-V MCU (submodule, pinned)
rtl/gf180mcu/   GF180 technology cells: SRAM, clock gate, ROM, pads
rtl/chip/       chip_top, pad ring, upstream instantiation
flow/           LibreLane config, SDC, PDN, macro placement
sim/            cocotb testbenches (RTL and gate level)
docs/           porting analysis
```

Each directory has its own README stating exactly what belongs in it.

## Pinned versions

Everything is pinned so results are reproducible. Override any of these on the `make`
command line.

| What | Value | Why |
| --- | --- | --- |
| `OSIC_TAG` | `2026.07` | IIC-OSIC-TOOLS image, carries LibreLane, OpenROAD, Magic, KLayout, netgen |
| `PDK` | `gf180mcuD` | 5 metal layers, the variant wafer.space fabricates |
| `PDK_COMMIT` | `f6eeac7d…` | Matches the wafer.space project template |
| `SLOT` | `1x1` | 3.93 × 5.12 mm die, 12.92 mm² core area |
| `SCL` | `gf180mcu_fd_sc_mcu7t5v0` | 7-track 5V standard cells |
| `SRAM` | `gf180mcu_fd_ip_sram` | Foundry macros, 512×8 maximum |

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
