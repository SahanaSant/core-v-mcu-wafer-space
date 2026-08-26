# Getting started

This walks from a fresh clone to a passing simulation. It takes about an hour, most of it
waiting for the PDK to build. Nothing here needs a full RTL-to-GDS run; when you want that,
go on to [how-to/harden.md](how-to/harden.md).

## What you need

Docker or Podman, `git`, and `make`. That is the whole list. Every tool runs inside the
pinned `hpretl/iic-osic-tools` container, and `run.sh` bind-mounts the repository into it at
`/foss/designs`. About 60 GB of disk for the container image and the PDK, and 16 GB of RAM if
you later want to run place-and-route.

## 1. Clone

```sh
git clone --recurse-submodules <url>
cd core-v-mcu-wafer-space
```

The `core-v-mcu/` submodule is upstream's RTL, pinned. If you forgot `--recurse-submodules`,
run `git submodule update --init` now.

## 2. Build the PDK

```sh
make pdk
```

This takes about fifteen minutes and only has to happen once. It clones open_pdks at the
pinned commit and builds `gf180mcuD` from source into `./pdk`.

Building from source rather than fetching a prebuilt PDK is deliberate: the prebuilt one
carries only the five `gf180mcu_fd_*` libraries, and this design needs `gf180mcu_ocd_ip_sram`
and `gf180mcu_ocd_io` too. The build also applies
[flow/pdk/patch_ocd_sram.sh](../flow/pdk/patch_ocd_sram.sh), which corrects two Liberty
fields the vendor copied from the wrong macro.

Sanity-check the result:

```sh
make shell                       # drop into the container
ls pdk/gf180mcuD/libs.ref        # should list gf180mcu_fd_* and gf180mcu_ocd_*
exit
```

## 3. Read the RTL

```sh
make elaborate
```

Seconds. This resolves the file list with fusesoc, reads the whole SoC through yosys-slang,
and prints every module the design instantiates but does not define. That list should be
empty: every technology-dependent module has a real implementation in `rtl/gf180mcu/`.

If this fails, the problem is your setup, not the design. If it prints unresolved modules,
something in the RTL changed and `rtl/gf180mcu/` needs a new cell.

## 4. Synthesise and look at timing

```sh
make area    # about 10 minutes
make sta     # about 2 minutes, needs `make area` first
```

`make area` synthesises to standard cells twice, flattened and hierarchical, and writes
`flow/build/area/area.md`: totals, gate equivalents, macro area from LEF, and a per-module
breakdown. `make sta` reports the deepest pre-layout logic path.

Read `make sta` as logic depth, not as a frequency. The netlist has been through neither
placement nor buffering, so its raw slack numbers mean nothing;
[flow/synth/path_summary.py](../flow/synth/path_summary.py) explains what part of the output
is real.

## 5. Build the boot ROM and simulate

```sh
make bootrom   # compile sw/bootrom, regenerate rtl/gf180mcu/gf180_bootrom.sv, check it
make sim       # RTL simulation: boot from flash, walk the SRAM, print over UART
```

`make sim` is the end-to-end functional check. It boots `chip_top` from a real QSPI flash
model through the boot ROM, verifies the image CRC, jumps into L2, walks every SRAM bank, and
prints `BOOT OK` and `SRAM PASS` over UART0. If that passes, your toolchain and the design
are both healthy.

## Where to go next

- Run the real flow: [how-to/harden.md](how-to/harden.md).
- Understand what you just built: [reference/design.md](reference/design.md).
- Understand why it is shaped this way: [explanation/decisions.md](explanation/decisions.md).
- Something misbehaving in a tool: [explanation/known-issues.md](explanation/known-issues.md).
