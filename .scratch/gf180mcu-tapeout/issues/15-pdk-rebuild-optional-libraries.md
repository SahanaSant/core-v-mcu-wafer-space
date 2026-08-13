# Build the pinned PDK from source with the optional libraries enabled

Type: task
Status: open
Blocked by: 14

## Question

Can `ciel build` produce a `gf180mcuD` PDK at the pinned open_pdks commit that includes
`gf180mcu_ocd_ip_sram`, `gf180mcu_ocd_io` and `gf180mcu_as_sc_mcu7t3v3`, and is the result
still variant-pure?

**Ticket 14 widened this ticket from one library to three**, because a from-source build is
the expensive step and the marginal cost of each extra `-l` is small. Each answers a different
open question, and each is wanted for its own reason:

| Library | Wanted for | Question it answers |
| --- | --- | --- |
| `gf180mcu_ocd_ip_sram` | 2.6x density, the original reason | Does ticket 11 get 20.4 KiB or 7.7 KiB? |
| `gf180mcu_ocd_io` | separated core and IO supply domains | Can the die have a 5.0 V IO ring over a 3.3 V core? |
| `gf180mcu_as_sc_mcu7t3v3` | 3.3 V-native thin-oxide cells | Is there area or speed on the table against `fd_sc_mcu7t5v0`? |

Ticket 01 found that the prebuilt PDK `ciel enable` fetches carries only the `gf180mcu_fd_*`
libraries. Every non-foundry library is absent from `libs.ref` while still being referenced
elsewhere in the same tree: `libs.tech/magic/gf180mcuD.magicrc` adds a search path for
`gf180mcu_ocd_ip_sram` that does not exist, `.config/nodeinfo.json` pins it at commit
`efdbf734d806…`, and `libs.tech/librelane/` ships configs for `gf180mcu_ocd_io`,
`gf180mcu_as_sc_mcu7t3v3` and both `gf180mcu_osu_sc_*`. The pinned open_pdks knows about all
of them; this distribution simply did not build them.

The route is `ciel build` rather than `ciel enable`:

```
ciel build --pdk-family gf180mcu \
  -l gf180mcu_ocd_ip_sram -l gf180mcu_ocd_io -l gf180mcu_as_sc_mcu7t3v3 \
  -j <n> f6eeac7dad085ffcc829ccfd721f7b4ce39edcf7
```

`-l/--include-libraries` may be repeated, or take `all`. `nodeinfo.json` pins each of these
to a commit already (`efdbf734…`, `6e0e354a…`, `c35a86ac…`), so the versions are not a
choice.

This is the hidden cost of ticket 07's answer. The OCD macros are 2.6x denser and that is
what makes 32 KiB of L2 reachable, but ticket 11 cannot rest on a macro nobody has managed to
obtain. Ticket 14 chose a 3.3 V core, so this ticket is **in scope and unblocked**; had it
chosen 5.0 V the OCD macros would have been unusable regardless and this would have been
ruled out instead.

**What ticket 14 wants from `gf180mcu_ocd_io` specifically.** Its LibreLane config, which
ships in the pinned PDK at `libs.tech/librelane/gf180mcu_ocd_io/config.tcl`, lists two
`PAD_PLACE_IO_TERMINALS` entries that the `gf180mcu_fd_io` config does not have:

```
$::env(PAD_CELL_LIBRARY)__vss/VSS
$::env(PAD_CELL_LIBRARY)__vdd/VDD
```

Those are separate core power and ground pads. The foundry `fd_io` library has only `dvdd`
and `dvss`, which bond the IO rails and pass the core rails through unbonded, so a die built
from `fd_io` can only tie VDD to DVDD and be single-supply. Confirm the cells exist in the
built result, that they carry the level shifter between domains, and which supply corners
they are characterised at. Note the config maps the 3.3 V pad corners onto `ff_n40C_3v63` and
`ss_125C_2v97`, not the `3v60`/`3v00` names the standard cells use.

Watch for: whether the build needs network access or a GitHub token, whether it is
reproducible against the same commit, how long it takes, and whether anything it emits is
drawn against `gf180mcuC`. The last one is the important one. Ticket 08 died on exactly that
mismatch, and a from-source build is more likely to expose variant assumptions than a tarball
someone else validated.

## Definition of done

All three libraries exist under `pdk/gf180mcuD/libs.ref/` with LEF, Liberty and GDS,
produced from the pinned commit: `gf180mcu_ocd_ip_sram` with `sram1024x8m8wm1`,
`gf180mcu_ocd_io` with `__vdd` and `__vss` among its cells, and `gf180mcu_as_sc_mcu7t3v3`.
`make pdk` reaches that state from a fresh checkout, with the build flags recorded in the
Makefile rather than in a comment or in this ticket. The `gf180mcu_fd_*` libraries still work
afterwards, confirmed by re-running `make area`.

Then one measurement, since the build is the expensive part and this is nearly free:
`SCL=gf180mcu_as_sc_mcu7t3v3 make area`, compared against ticket 10's baseline of 311.3 kGE
and 3.417 mm² of cell area on `gf180mcu_fd_sc_mcu7t5v0`. A 3.3 V-native library uses
thin-oxide devices, so it may be smaller, faster or both at this supply, and area is the
binding constraint. **This measures, it does not switch**: changing the committed library is
a separate decision, taken on the number this produces.

Record the wall-clock build time, since it lands in the Run 3 schedule.

## Answer

<!-- filled on resolution -->
