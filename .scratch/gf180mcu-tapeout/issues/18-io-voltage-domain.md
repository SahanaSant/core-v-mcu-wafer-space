# IO voltage domain: a 5.0 V ring over the 3.3 V core, or single supply?

Type: grilling
Status: resolved
Blocked by: 15

## Question

Ticket 14 settled the core at 3.3 V and recorded **3.3 V single supply** as the arrangement
that is buildable today. It could not settle the IO ring, because the library that would make
a second domain possible is not built. This ticket decides the IO supply once ticket 15 has
built it, and owns the final power pad allocation.

**Why single supply is currently forced, not chosen.** `gf180mcu_fd_io` ships exactly two
supply pad cells. `__dvdd` bonds DVDD and passes DVSS and VSS through unbonded; `__dvss`
bonds DVSS and passes DVDD and VDD through. Neither bonds a core rail, and the LEF confirms
it: on `__dvdd` only DVDD reaches Metal2, the layer that drops to the pad structure, while
DVSS and VSS exist on Metal3 to Metal5 as pass-through rails only. So a die built from
`fd_io` has no way to bring core VDD to a pin except by tying it to DVDD. wafer.space say
this is deliberate, in Leo Mouser's words: "The foundry-provided pads short the core and I/O
domain on purpose."

**Why 5 V tolerance is not the escape hatch.** A 3.3 V ring cannot simply accept 5 V inputs.
In `gf180mcu_fd_io__bi_t` every output PMOS is a `pfet_06v0_dss` with its **bulk tied to
DVDD** and its drain on `PAD`, and the ESD network clamps `PAD` to DVDD as well
(`comp018green_esd_clamp_v5p0_DVDD`, plus `ppolyf_u` resistors from PAD to DVDD). Driving a
pin to 5 V with DVDD at 3.3 V forward-biases the drain-bulk junction about 0.7 V above the
rail and dumps pad current into the supply. The devices are 6 V rated so they survive 5 V,
but only with DVDD at 5 V. These pads are 5 V **capable**, not 5 V **tolerant**. Interfacing
at 5 V therefore means running DVDD at 5.0 V, which with `fd_io` alone would drag the core to
5 V and lose the OCD SRAM.

**What ticket 15 should deliver.** `gf180mcu_ocd_io`, Tim Edwards' 3.3/5 V cells, pinned in
`nodeinfo.json` at `6e0e354a…`. Its LibreLane config already ships in the PDK and names two
terminals the `fd_io` config does not have:

```
$::env(PAD_CELL_LIBRARY)__vss/VSS
$::env(PAD_CELL_LIBRARY)__vdd/VDD
```

Separate core power and ground pads, alongside `dvdd`/`dvss`. Leo describes these cells as
having "a level shifter between core and I/O domain" and keeping "both domains properly
separated in the power/ground pads."

## What to decide

- **The IO supply.** 5.0 V for native 5 V signalling and tolerance, or 3.3 V. Note that 3.3 V
  IO with separated domains is still worth something over the single-supply baseline, because
  it isolates pad switching noise from the core.
- **The power pad allocation**, superseding ticket 14's provisional 9 `dvdd` / 9 `dvss`. A
  split die needs the 18 divided across four cells, and IO drive current and core IR drop pull
  in different directions.
- **Where the domain crossing sits** and what shifts it, if the `ocd_io` cells do not do all
  of it. Ticket 14's answer notes that a single-supply die leaves `apb_pll`'s five analog
  supply ports with no rail to reach; a split die may change that, which feeds ticket 05.
- **The fallback**, if the built cells turn out to be drawn for `gf180mcuC`, to lack a
  `gf180mcuD` DRC-clean path, or if the wafer.space template's ring generator does not
  support the split in time. Leo's "in the (very) near future" refers to template support, and
  the map's standing preference is to seed the ring from the template rather than hand-write
  it. December is the constraint, and the single-supply baseline is the thing to fall back to.

## Watch for

This is the ticket-08 failure mode in a new place. Check the variant of every `ocd_io` cell
before building anything on it, and remember that `pdk/` symlinks `gf180mcuA` through `D` into
one ciel version, so a wrong variant name resolves to a real directory rather than failing.

The decision is also **not reversible late**. Pad ring supply arrangement is floorplan-level,
so this has to resolve before the first full harden, not after it.

## Definition of done

A named IO supply with the reasoning, a statement of single or multi supply, the allocation of
all 18 power pads by cell, and confirmation from the built PDK that the pad cells and corners
chosen actually exist. If the answer is the split domain, the level shifter's location is
named. If it is the fallback, ticket 14's single-supply baseline is confirmed unchanged and
the reason it could not be improved on is recorded.

## Answer

**5.0 V ring over the 3.3 V core, split domain, via `gf180mcu_ocd_io`.** Grilled live. The
decisive input was a use-case call only the human could make: whether the chip needs to talk
to any real 5 V logic is not yet known, and the instruction was to try for 5 V and only fall
back if it turns out infeasible. It doesn't turn out infeasible — both of the ticket's own
named fallback conditions are cleared by inspection of the built PDK and a live check of the
template:

- **Variant.** `gf180mcu_ocd_io` is built `gf180mcuD`-native in the pinned PDK (ticket 15),
  not a symlinked mismatch — the ticket-08 failure mode this ticket warned about does not
  recur.
- **Characterisation.** Twelve real corners, 2.5 V / 3.3 V / 5.0 V, confirmed genuinely
  characterised rather than a header-swapped foundry file (unlike the OCD SRAM): the library's
  own `docs/datasheet.rst` describes it as the foundry `fd_io` library plus level shifters "in
  front of all core-facing signals, so that on the core side, all signaling is done in the
  3.3V voltage domain," which is also this ticket's answer on where the domain crossing sits —
  **inside each `ocd_io` pad cell** (`bi_t`, `in_c`, `in_s`, `bi_a`), not a separate shared
  block.
- **Template support.** A live fetch of
  [wafer.space/gf180mcu-project-template](https://github.com/wafer-space/gf180mcu-project-template)
  found `PAD=gf180mcu_ocd_io` already listed as a supported value alongside
  `PAD=gf180mcu_fd_io` in its Makefile. Leo's "in the (very) near future," quoted in this
  ticket's own text, has landed; the ring generator is not a blocker.
- **Geometry.** Every `ocd_io` pad cell measured identical to its `fd_io` counterpart in LEF
  (75.000 × 350.000 um for `dvdd`/`dvss`/`vdd`/`vss`/`bi_t`), so picking the split library costs
  nothing in ring geometry or pad-slot count. The 18-pad power budget from ticket 14 is a fixed
  total either way; this ticket only decides which cell types fill it.

One of the two motivations this ticket named for going split — giving `apb_pll`'s five analog
supply ports somewhere to land — turned out moot before this ticket resolved: ticket 05 already
removed those ports entirely, independent of what this ticket decided.

**Power pad allocation: `dvdd` 5 / `dvss` 5 / `vdd` 4 / `vss` 4**, provisional. No current data
exists to derive this from measurement: neither `docs/datasheet.rst` (in `gf180mcu_ocd_io` or
`gf180mcu_fd_io`) carries a drive-current table, Liberty has no headline current figure (drive
strength is buried in CCS tables), and no `report_power` step exists anywhere in this flow. The
allocation keeps `dvdd`=`dvss` and `vdd`=`vss` for symmetric ESD return current, biased 10
pads to the IO rail against 8 to the core rail on the unmeasured but directional reasoning that
SDIO/QSPI pad switching is more likely to dominate IR drop than a 10 MHz core. **Ticket 21 owns
the real number**, once PDN analysis exists to check it against; this is a placeholder for the
floorplan to start from, not a measured result, the same shape as ticket 14's own "9/9,
provisional" that this supersedes.

**The fallback (3.3 V single supply) is not taken.** Both conditions the ticket named for
falling back — a variant mismatch or a template that can't build the split in time — are
cleared, so there is nothing to fall back from. Ticket 14's single-supply baseline stays the
documented history of how the die got here, not the final answer.

Known follow-up, not new work this ticket adds: `libs.tech/librelane/gf180mcu_ocd_io/config.tcl`
ships `PAD_CDLS ""` where `fd_io` inherits real CDL (ticket 15's finding). The SPICE exists as a
proper hierarchical netlist; the LibreLane config just isn't pointed at it yet. Already tracked
in the map's "DRC, LVS and antenna" fog patch, now confirmed live rather than conditional.
