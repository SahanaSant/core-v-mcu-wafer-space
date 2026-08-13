# Build the pinned PDK from source with the optional libraries enabled

Type: task
Status: open
Blocked by: 14

## Question

Can `ciel build` produce a `gf180mcuD` PDK at the pinned open_pdks commit that includes
`gf180mcu_ocd_ip_sram`, and is the result still variant-pure?

Ticket 01 found that the prebuilt PDK `ciel enable` fetches carries only the `gf180mcu_fd_*`
libraries. Every non-foundry library is absent from `libs.ref` while still being referenced
elsewhere in the same tree: `libs.tech/magic/gf180mcuD.magicrc` adds a search path for
`gf180mcu_ocd_ip_sram` that does not exist, `.config/nodeinfo.json` pins it at commit
`efdbf734d806…`, and `libs.tech/librelane/` ships configs for `gf180mcu_ocd_io`,
`gf180mcu_as_sc_mcu7t3v3` and both `gf180mcu_osu_sc_*`. The pinned open_pdks knows about all
of them; this distribution simply did not build them.

The route is `ciel build` rather than `ciel enable`:

```
ciel build --pdk-family gf180mcu -l gf180mcu_ocd_ip_sram -j <n> f6eeac7dad085ffcc829ccfd721f7b4ce39edcf7
```

`-l/--include-libraries` may be repeated, or take `all`. Decide whether to pull in
`gf180mcu_as_sc_mcu7t3v3` in the same build if ticket 14 has made a 3.3 V standard cell
library interesting, since a second from-source build is expensive.

This is the hidden cost of ticket 07's answer. The OCD macros are 2.6x denser and that is
what makes 32 KiB of L2 reachable, but ticket 11 cannot rest on a macro nobody has managed to
obtain. It is blocked on ticket 14 because a 5.0 V core makes the OCD macros unusable
regardless, in which case this ticket is ruled out of scope rather than worked.

Watch for: whether the build needs network access or a GitHub token, whether it is
reproducible against the same commit, how long it takes, and whether anything it emits is
drawn against `gf180mcuC`. The last one is the important one. Ticket 08 died on exactly that
mismatch, and a from-source build is more likely to expose variant assumptions than a tarball
someone else validated.

## Definition of done

`pdk/gf180mcuD/libs.ref/gf180mcu_ocd_ip_sram` exists with LEF, Liberty and GDS for
`sram1024x8m8wm1`, produced from the pinned commit. `make pdk` reaches that state from a
fresh checkout, with the build flags recorded in the Makefile rather than in a comment or in
this ticket. The `gf180mcu_fd_*` libraries still work afterwards, confirmed by re-running
whatever the current flow can run.

Record the wall-clock build time, since it lands in the Run 3 schedule.

## Answer

<!-- filled on resolution -->
