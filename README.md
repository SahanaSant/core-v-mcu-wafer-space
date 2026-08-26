# core-v-mcu-wafer-space

The [OpenHW CORE-V MCU](https://github.com/openhwgroup/core-v-mcu) ported to GlobalFoundries
GF180MCU and hardened for a [wafer.space](https://wafer.space) shuttle slot, using an
open-source RTL-to-GDS flow.

**Status: signed off.** The final GDS passes all sixteen stages of
[gf180mcu-precheck](https://github.com/wafer-space/gf180mcu-precheck). Timing closes at
5 MHz with zero setup and zero hold violations across all nine STA corners, DRC and LVS are
clean, and gate-level simulation boots the hardened netlist from SPI flash and prints over
UART. See [docs/reference/design.md](docs/reference/design.md) for the measured numbers.

The chip is a CV32E40P RV32IMC core with 16 KiB of L2 SRAM, a boot ROM, a uDMA peripheral
subsystem and a JTAG debug module, on a 3.93 × 5.12 mm die with a 74-position pad ring.

## Getting started

You need Docker or Podman, plus `git` and `make`. Every tool runs inside a container;
nothing is installed on the host.

```sh
git clone --recurse-submodules <url> && cd core-v-mcu-wafer-space
make pdk         # build the pinned PDK into ./pdk (about 15 min, once)
make elaborate   # read the RTL, confirm the setup works (seconds)
```

[docs/getting-started.md](docs/getting-started.md) walks through that first hour and ends
with a passing simulation. `make` on its own lists every target.

## Documentation

| | |
| --- | --- |
| **[Getting started](docs/getting-started.md)** | Set up, elaborate, synthesise, simulate. Start here. |
| **How-to** | [Harden and sign off](docs/how-to/harden.md) · [Simulate](docs/how-to/simulate.md) · [Build patched OpenROAD](docs/how-to/patched-openroad.md) |
| **Reference** | [The design](docs/reference/design.md) · [Pin-out](docs/reference/pinout.md) · [Flow configuration](docs/reference/flow.md) · [RTL](docs/reference/rtl.md) |
| **Explanation** | [Design decisions](docs/explanation/decisions.md) · [Timing closure](docs/explanation/timing.md) · [Known issues](docs/explanation/known-issues.md) · [Original porting analysis](docs/explanation/porting-analysis.md) |

## Layout

```
core-v-mcu/   upstream CORE-V MCU (git submodule, pinned)
rtl/gf180mcu/ GF180 technology cells: SRAM wrappers, clock gates, boot ROM, clock generator
rtl/chip/     chip_top, the pad ring, and the upstream SoC instantiation
flow/         LibreLane configuration, SDC, PDN, macro placement, synthesis scripts
sim/          cocotb testbenches, RTL and gate level
sw/           boot ROM and the simulation payload application
ip/           vendored wafer.space marker cells
docs/         everything above
```

`pdk/` (built by `make pdk`) and `openroad-build/` are gitignored host-local build output.

## Pinned versions

Everything is pinned so results reproduce. Override any of these on the `make` command line.

| What | Value | Why |
| --- | --- | --- |
| `OSIC_TAG` | `2026.07` | IIC-OSIC-TOOLS image: LibreLane, OpenROAD, Yosys, Magic, KLayout, netgen |
| `PDK` | `gf180mcuD` | 5 metal layers, the variant wafer.space fabricates |
| `PDK_COMMIT` | `f6eeac7d…` | Matches the wafer.space project template |
| `SLOT` | `1x1` | 3.93 × 5.12 mm die, 12.90 mm² core |
| `SCL` | `gf180mcu_fd_sc_mcu7t5v0` | 7-track cells. The `5v0` is the oxide, not the supply: the core runs at 3.3 V |
| `PAD` | `gf180mcu_ocd_io` | 5.0 V ring with a level shifter in each pad, over the 3.3 V core |
| `SRAM` | `gf180mcu_ocd_ip_sram` | wafer.space's denser 1024×8 macro |

The container ships its own PDK build. `make pdk` deliberately builds the pinned commit into
`./pdk` instead, so the image and the PDK version stay independent.

## Contributing

Changes split in two. **Upstreamable** RTL (technology cells, parameterisation, making the
eFPGA optional) belongs in the `core-v-mcu/` submodule and goes to OpenHW as pull requests
from a fork; contributors must be covered by the
[Eclipse Contributor Agreement](https://www.eclipse.org/legal/ECA.php). **Shuttle-specific**
work (flow configuration, pad ring, macro placement, slot markers) stays in this repository,
where it has no meaning upstream.

Keep that split honest: anything that would help someone porting to a different PDK belongs
upstream.

## Licence

Apache-2.0 WITH SHL-2.1, matching upstream, so RTL moves between the two repositories without
a licence change. See [LICENSE.md](LICENSE.md).
