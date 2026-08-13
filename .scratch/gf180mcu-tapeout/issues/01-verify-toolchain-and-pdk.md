# Verify the toolchain container and the pinned PDK

Type: task
Status: resolved
Blocked by: none

## Question

Does `make shell` open a working environment, and does `make pdk` actually place `gf180mcuD`
at the pinned commit under `./pdk`?

Nothing in the Makefile's PDK path has ever been run. `./pdk` is currently empty, so either
`make pdk` was never invoked or it failed. The `ciel enable` flag names (`--pdk-root`,
`--pdk-family`) were written from the standard interface without being executed. The
container engine was switched from Docker to Podman after the skeleton was committed, and
`run.sh` moved from `docker/` to the repository root, so the Makefile and README both need
to agree with reality.

This blocks essentially everything else, and it is cheap. Do it first.

## Definition of done

From inside `make shell`, all of these report a version: `yosys`, `openroad`, `magic`,
`klayout`, `netgen`, `iverilog`, and `librelane`.

`$PDK_ROOT/gf180mcuD/libs.ref` exists and contains `gf180mcu_fd_sc_mcu7t5v0`,
`gf180mcu_fd_io` and `gf180mcu_fd_ip_sram`. Specifically confirm that LEF, Liberty and GDS
for `gf180mcu_fd_ip_sram__sram512x8m8wm1` are all present, since the whole memory plan
assumes they are.

Two extra checks added after ticket 07, both cheap and both load-bearing:

- **List the Liberty corners shipped for `gf180mcu_fd_sc_mcu7t5v0`.** Ticket 14's entire
  argument rests on the claim that this library, despite the `5v0` in its name, is
  characterised at 3.3 V (3v00, 3v30, 3v60) as well as 5.0 V. Confirm or refute it by
  listing the `.lib` files. If there is no 3.3 V corner, ticket 14 collapses to a single
  option and the OCD SRAM becomes much less attractive.
- **Check whether `gf180mcu_ocd_ip_sram` is present in the pinned PDK**, since `open_pdks`
  carries it as an optional library. If it is not, record what enabling it would take.

The Makefile's `pdk` target runs clean from a fresh checkout, with whatever flags actually
work recorded in the file rather than in a comment. Fix `run.sh` and the README so the
Podman move is consistent.

## Answer

The toolchain works and the PDK is in place. The premise that `./pdk` was empty was stale by
the time this ticket was worked: `make pdk` had already been run successfully at the end of
the previous session, and re-running it here is idempotent and exits clean. The `ciel enable`
flags in the Makefile were written from the standard interface and turn out to be correct as
written, so nothing needed changing there.

### Tools

All seven report a version from inside `make shell`, running `hpretl/iic-osic-tools:2026.07`
under rootless Podman 6.0.2 with `--userns=keep-id`.

| Tool | Version |
| --- | --- |
| yosys | 0.67 (2d1509d1b) |
| openroad | 26Q3-850-gc74892e7b |
| magic | 8.3.678 |
| klayout | 0.30.9 |
| netgen | 1.5.323 |
| iverilog | 14.0 devel (s20260301-328-geda9fdcd) |
| librelane | v3.1.0.dev2 |

`ciel` 2.6.1 is also present, which matters below. `PDK_ROOT=/foss/designs/pdk` and
`PDK=gf180mcuD` arrive in the container correctly.

### PDK

`ciel` placed open_pdks `f6eeac7d` at `pdk/ciel/gf180mcu/versions/f6eeac7d…`, 3.5 GB, with
`pdk/gf180mcu{A,B,C,D}` as symlinks into it. `pdk/gf180mcuD/libs.ref` contains
`gf180mcu_fd_sc_mcu7t5v0`, `gf180mcu_fd_sc_mcu9t5v0`, `gf180mcu_fd_io`, `gf180mcu_fd_ip_sram`
and `gf180mcu_fd_pr`.

`gf180mcu_fd_ip_sram__sram512x8m8wm1` is complete: GDS, LEF, CDL, SPICE, Magic and maglef
views, a plain and a blackbox Verilog model, and fifteen Liberty corners. The library ships
64x8, 128x8, 256x8 and 512x8 and nothing larger, confirming the 512 byte per macro ceiling
the memory plan assumes.

### Liberty corners: ticket 14's premise is confirmed, and wider than claimed

`gf180mcu_fd_sc_mcu7t5v0` ships fifteen corners spanning three voltage families, not one:

- 5.0 V: `tt_025C_5v00`, `ss_125C_4v50`, `ss_n40C_4v50`, `ff_125C_5v50`, `ff_n40C_5v50`
- 3.3 V: `tt_025C_3v30`, `ss_125C_3v00`, `ss_n40C_3v00`, `ff_125C_3v60`, `ff_n40C_3v60`
- 1.8 V: `tt_025C_1v80`, `ss_125C_1v62`, `ss_n40C_1v62`, `ff_125C_1v98`, `ff_n40C_1v98`

These are real 20 MB characterised files, not stubs. The `operating_conditions` block in the
3v30 file reads `voltage : 3.3` and in the 1v80 file `voltage : 1.8`. So the `5v0` in the
library name is the oxide, not the only supported supply, and ticket 14 keeps both options.
`gf180mcu_fd_ip_sram__sram512x8m8wm1` carries the same three families, so the foundry SRAM
tracks the core supply either way. `gf180mcu_fd_io` is characterised at 2v50, 3v30 and 5v00
tt, which is the pad side of the same question.

Two consequences for ticket 14 that were not visible before:

- **3.3 V is a flow-config override, not a default.** `libs.tech/librelane/config.tcl` for
  `gf180mcuD` hardcodes `VDD_PIN_VOLTAGE 5.00` and builds `CELL_LIBS`, `STA_CORNERS` and
  `DEFAULT_CORNER` from the 5v00, 4v50 and 5v50 corners only. Running at 3.3 V means
  overriding all four in `flow/config.yaml`. It is cheap but it is not free, and nothing
  warns you if you set the supply and forget the corners.
- **There is a native 3.3 V standard cell library.** `gf180mcu_as_sc_mcu7t3v3` has a shipped
  LibreLane config with `STA_CORNERS` already on 3v30, so derating the 5 V library is not the
  only route to 3.3 V. Treat this as a lead rather than a recommendation: the library is not
  built into this PDK (see below), and its config writes `::env(LIB)` where the current
  `gf180mcuD` config writes `::env(CELL_LIBS)`, which suggests it has not been exercised
  against LibreLane 3.x.

### `gf180mcu_ocd_ip_sram` is not in the pinned PDK, and enabling it is a rebuild

It is absent from `libs.ref` entirely. What is there is a dangling reference:
`libs.tech/magic/gf180mcuD.magicrc` already carries
`addpath ${PDK_ROOT}/gf180mcuD/libs.ref/gf180mcu_ocd_ip_sram/${MAGTYPE}` for a directory that
does not exist, and `.config/nodeinfo.json` pins it at commit `efdbf734d806…` under
`memory`. The pinned open_pdks knows about the library; this ciel distribution just did not
build it. The same is true of every non-`fd_` library: `gf180mcu_ocd_io`,
`gf180mcu_as_sc_mcu7t3v3`, both `gf180mcu_osu_sc_*` and `gf180mcu_re_efuse` all have
LibreLane configs shipped under `libs.tech/librelane/` with no `libs.ref` content behind them.

Enabling it means `ciel build` rather than `ciel enable`:

```
ciel build --pdk-family gf180mcu -l gf180mcu_ocd_ip_sram <commit>
```

`-l/--include-libraries` takes the library name and may be repeated, or `-l all`. This builds
open_pdks from source in the container against the same pinned commit, so the result stays
variant-pure and reproducible, but it is a long build rather than a tarball fetch and it has
not been attempted. `ciel build` also defaults to `-j 1`.

This does not change ticket 07's answer, but it does add a cost to acting on it: choosing the
OCD macro in ticket 11 buys a PDK rebuild, and that rebuild has to be proven before the
memory architecture can depend on it.

### Repository changes made

`make pdk` was already correct and is left alone. Two consistency fixes, both in the Makefile:

- `precheck-image` and `precheck` hardcoded `podman` while everything else went through
  `run.sh`, which detects Podman or Docker. Both now use a detected `$(ENGINE)`, so the
  README's "Docker or Podman" prerequisite is true of the whole Makefile again.
- `PDK_ROOT` was declared `?=` under a header promising every variable is overridable, but
  the `pdk` target passes a hardcoded `/foss/designs/pdk` to `ciel`, so overriding it would
  have created an empty directory and written the PDK somewhere else. It is now `:=` with a
  comment saying why.

`run.sh` and the README already reflected the Podman move and needed no further change.

### Hazard worth carrying forward

`pdk/` contains `gf180mcuA`, `gf180mcuB` and `gf180mcuC` alongside `gf180mcuD`, all symlinked
into the same ciel version. A mistyped or copy-pasted variant name resolves silently to a
real, populated directory instead of failing. Given that variant purity is a standing
constraint of this map and already killed ticket 08, anything that takes a variant name
should assert it is `gf180mcuD` rather than trust it.
