# Floorplan, PDN and macro placement

Type: grilling
Status: resolved
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

**Decided the shape, order and power domain of the macro array; splitting off the actual build
(chip_top.sv, the LibreLane config files, and a routed run) as ticket 25, since that work is
blocked on RTL that doesn't exist yet.** This ticket resolves as a decision, not a placement,
matching what tickets 04 and 05 did when they hit the same wall (spinning off 23 and 24
respectively).

**Why this splits.** The Definition of Done as written asks for a completed LibreLane run
through detailed routing. That isn't reachable this session: `rtl/chip/chip_top.sv` doesn't
exist at all (only its README, describing what it should contain), and `make elaborate` can't
even complete on the SoC alone yet, since tickets 23 (boot ROM) and 24 (clock gen) are still
open and `a2_bootrom`/`apb_pll` are still black boxes. Grilled live: rather than widen this
ticket to include writing that RTL, or block it entirely on 23/24 finishing first, the decision
half (what tickets 04/05 called the "architecture question") is answered now, and the build half
becomes its own ticket, blocked on the two that actually gate elaboration.

**Array shape: 2 rows x 8 columns**, not the 4x4 that ticket 11's planning arithmetic assumed.
Each macro is 301.30 x 515.81 um with all 37 signal pins on Metal2 in a 3 um band along the
bottom edge, so every row needs a channel below it. Channel area works out the same either way
(~241,000 um2, since total channel length scales with row count in inverse proportion to row
width), so that wasn't the deciding factor. The shape is: 4 rows x 4 columns is 1235 x 2263 um
and would sit in a corner of the 3048 x 4238 um core, leaving an L-shaped remainder for standard
cells. 2 rows x 8 columns is roughly 2410 x 1132 um and sits along one edge, leaving a single
clean rectangle above it for the placer to fill evenly toward the 35% target density. The two
interleaved channels pair into one row, the two private banks into the other, so the grouping
that mattered for ticket 11's firmware story (private banks feeding instruction fetch, interleaved
banks feeding data/uDMA) survives the reshape as a row-level split rather than a quadrant-level
one.

**Placement: south edge of the core, private banks (0, 1) then interleaved channels (0, 1)
left to right.** Grilled live: with no pad-to-side assignment fixed yet (that's chip_top.sv work,
also deferred to ticket 25) and nothing else in the floorplan pinned down, there's no data on
hand that makes one edge or one ordering measurably better than another. LibreLane's placer pulls
whichever crossbar logic connects to a macro toward that macro once macros are fixed, regardless
of which edge they sit on, so this is a reasonable default to place and then validate by routing,
not a conclusion to defend analytically. A center placement (splitting the standard-cell region
into two pieces) was considered and rejected, since it gives up the single-clean-rectangle benefit
that was the actual reason to prefer 2x8 over 4x4.

**Power domain: single 3.3 V rail, no split.** The question as originally framed ("ticket 18
decides whether the ring is one 3.3 V rail or a split domain") is stale: ticket 18 resolved by
splitting the *IO ring* to 5.0 V over the 3.3 V core, not the core rail itself, which ticket 14
already fixed at a single 3.3 V supply and ticket 18 didn't touch. The macro perimeter ring is
VDD/VSS at 3.3 V, inherited rather than newly decided here.

**Density headroom and `MAGIC_GDS_FLATGLOB` entries stay unanswered on purpose.** Both need a
real run to answer (whether 35% target density places cleanly, which macro-specific patterns
throw false DRC errors), so both travel forward as part of ticket 25's Definition of Done rather
than being estimated here.
