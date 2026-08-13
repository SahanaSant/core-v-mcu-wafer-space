# Floorplan, PDN and macro placement

Type: grilling
Status: open
Blocked by: 06, 18, 19

## Question

Graduated from the map's fog by ticket 11, which fixed the inputs this could not be asked
without: sixteen `gf180mcu_ocd_ip_sram__sram1024x8m8wm1` macros of 301.30 x 515.81 um, in four
groups of four, inside a 3050 x 4240 um core.

Ticket 11's planning arithmetic is 4 rows by 4 columns at 1235 x 2263 um, about 2.79 mm2, on a
50 um channel per row. That is an estimate and this ticket replaces it with a placement.

What has to be settled:

- **Array shape and orientation.** Every signal pin sits on Metal2 in the 3 um band along the
  macro's bottom edge, all 37 of them, so each macro presents its whole interface on one side.
  Every macro needs a channel below it and orientation is not free. 4x4 and 2x8 both fit the core
  and cost the same area; they differ in how far the interleaved banks sit from the crossbar and
  how far the private banks sit from the core.
- **Which group goes where.** The two private banks feed instruction fetch through the
  contiguous crossbar; the two interleaved banks feed data and uDMA through the interleaved
  crossbar. Ticket 11's firmware story assumes those paths stay independent, and placement is
  what makes that true or not.
- **PDN.** Metal4 and Metal5 are free over the macros, Metal1 to Metal3 are obstructed over the
  interior with a 3 um frame, and power arrives as a Metal2/Metal3 ring on each macro's
  perimeter. Ticket 18 decides whether the ring is one 3.3 V rail or a split domain, which
  changes strap count and pad allocation.
- **Density headroom.** Ticket 11 leaves the core at about 89% occupancy after ticket 12's
  `apb_i2cs` cut, and 97% without it. Whether the standard-cell region actually places at the
  template's 35% is the thing this ticket finds out, and ticket 10 flagged 35% as the optimistic
  end of Run 1 experience.
- **`MAGIC_GDS_FLATGLOB` patterns** for the SRAM macros, which the map's DRC fog patch expects to
  be discovered by running into false errors.

## Definition of done

A `macro_placement.cfg` that places sixteen macros, a PDN configuration, and a LibreLane run that
completes through detailed routing with the real numbers quoted. Sign-off is a separate matter:
this closes when the design places and routes, not when it passes precheck.

## Answer

<!-- filled on resolution -->
