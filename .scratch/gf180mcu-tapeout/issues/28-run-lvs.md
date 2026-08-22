# Run LVS (netgen) end to end

Type: task
Status: resolved
Blocked by: none

## Question

LVS has never run on this design at all. Ticket 26's routed run got as far as full-chip
KLayout DRC (ticket 27) but the LibreLane LVS step — KLayout extraction feeding a `netgen`
comparison against the CDL/SPICE netlist — hasn't been invoked once.

`flow/config.yaml`'s `MAGIC_GDS_FLATGLOB` list is worth a look before or during this ticket
too. Its own comment says whatever the OCD macros need beyond the template's foundry-SRAM
entries "is discovered by running into the false errors" — that discovery has never happened,
since nothing has run Magic DRC/extraction against a GDS containing the OCD SRAM or IO macros
yet. If LVS extraction on this flow goes through Magic rather than KLayout alone, expect to
need to grow this list; if it turns out unnecessary, that's worth confirming and noting here
too, since the config comment currently promises a fog patch on this map that no longer exists
as fog (folded into this ticket instead).

One known blocker has a fix already found, not yet applied: `gf180mcu_ocd_io`'s installed PDK
tree has no `libs.ref/gf180mcu_ocd_io/cdl/` directory (`PAD_CDLS ""` in
`gf180mcu_ocd_io/config.tcl`), but it does have
`libs.ref/gf180mcu_ocd_io/spice/gf180mcu_ocd_io.spice` — a 945-line hierarchical SPICE deck,
one `.subckt`/`.ends` per pad cell, in the same `*.PININFO` convention `gf180mcu_fd_io.cdl`
uses. LibreLane's KLayout LVS step concatenates whatever `PAD_CDLS` points to verbatim,
indifferent to the `.spice`/`.cdl` extension. The fix is one line in `flow/config.yaml`:

```
PAD_CDLS: [pdk_dir::libs.ref/gf180mcu_ocd_io/spice/gf180mcu_ocd_io.spice]
```

overriding the empty default. See ticket 26's Comments for the full trail on how this was
found.

Apply that, then run LVS against the routed GDS from ticket 26's run
(`RUN_2026-08-14_20-23-37`, or a fresh `--last-run --from` resume if the checkpoint needs
regenerating). Expect further gaps to surface once it actually runs — this ticket's job is to
find and clear them, not just the one already known. The OCD SRAM macros
(`gf180mcu_ocd_ip_sram`) are one thing worth checking early: confirm their CDL/SPICE is
similarly present and pointed at correctly, the same class of gap as the IO ring.

## Definition of done

`netgen` LVS reports a clean match (layout vs. schematic) for `chip_top`, numbers quoted from
the run (device count, net count, any waived mismatches with reasoning). If a mismatch turns
out to be a real design defect rather than a missing-CDL gap, that's a finding to record here,
not something to route around silently.

## Answer

**LVS passed clean on the first real run, and the CDL gap this ticket was written against turns out not to exist.** `RUN_2026-08-16_04-34-36`'s `Netgen.LVS` step (`595-netgen-lvs`) reports, quoted from the run:

- **Circuits match uniquely.**
- Circuit 1 (layout, from Magic's extraction): 164,340 devices, 163,281 nets.
- Circuit 2 (schematic, from the synthesized netlist): 164,340 devices, 163,281 nets — an exact match on both counts.
- `metrics.json`: `design__lvs_device_difference__count`, `lvs_net_difference__count`, `lvs_property_fail__count`, `lvs_unmatched_device__count`, `lvs_unmatched_net__count`, `lvs_unmatched_pin__count` all **0**.

The ticket's premise — that `PAD_CDLS ""` leaves `gf180mcu_ocd_io` with no reference netlist for LVS — doesn't hold against the actual config or the log. `595-netgen-lvs/config.json` carries a **separate** variable, `PAD_SPICE_MODELS`, already pointed at exactly the file this ticket found by hand:
`pdk/gf180mcuD/libs.ref/gf180mcu_ocd_io/spice/gf180mcu_ocd_io.spice`. `PAD_CDLS` and `PAD_SPICE_MODELS` are two different config knobs — one for `.cdl`-suffixed decks, one for `.spice`-suffixed ones — and the wafer.space template already wires the IO ring through the second one. The `.spice` file's actual read is confirmed in `netgen-lvs.log` (`Reading SPICE netlist file '.../gf180mcu_ocd_io/spice/gf180mcu_ocd_io.spice'...`), and the class-instance summary in that same log shows `gf180mcu_ocd_io__vss`, `__vdd`, `__fill1`, `__fillnc` all present and reconciled in the unique match. `flow/config.yaml`'s `PAD_CDLS` line was never touched — no fix was needed, only the (incorrect) assumption that one was.

**The OCD SRAM macros LVS clean too** (`gf180mcu_ocd_ip_sram__sram1024x8m8wm1`, 16 instances, present and matched) — no separate CDL/SPICE gap there either; `CELL_SPICE_MODELS`/`CELL_CDLS` already cover the standard-cell library and the SRAM's own `pdk_dir::` reference resolves the same way the IO ring's does.

**`MAGIC_GDS_FLATGLOB` didn't need growing.** Both `Magic.DRC` (`589-magic-drc`) and `Magic.SpiceExtraction` (`593-magic-spiceextraction`) ran clean against a GDS containing all sixteen OCD SRAM macros and the full `gf180mcu_ocd_io` ring: `magic-drc.rpt` reports `COUNT: 0`, and extraction finished with only mundane warnings (a DEF pin-count-mismatch note, an `RLIMIT_NOFILE` notice) — no false-positive layer-name collisions the template's existing FLATGLOB list would have needed to suppress. The "cell placed on top of itself, ignoring the extra one" messages seen while Magic reads the OCD SRAM's GDS are its own internal duplicate-placement dedup, unrelated to FLATGLOB and not something either DRC or LVS choked on. Left unchanged.

This ticket's own concern about MAGIC_GDS_FLATGLOB is now closed by measurement rather than left open: the template's foundry-SRAM-only list was already sufficient for the OCD macros and the IO ring both. No follow-up needed unless a future macro swap reintroduces false errors.
