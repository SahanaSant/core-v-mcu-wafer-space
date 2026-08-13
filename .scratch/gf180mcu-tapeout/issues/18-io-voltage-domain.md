# IO voltage domain: a 5.0 V ring over the 3.3 V core, or single supply?

Type: grilling
Status: open
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

<!-- filled on resolution -->
