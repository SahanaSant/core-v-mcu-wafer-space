# Core supply voltage: 3.3 V or 5.0 V?

Type: grilling
Status: resolved
Assignee: yusefkarim
Blocked by: none

## Question

Surfaced by ticket 07, which found that the denser OCD SRAM macros have **no 5.0 V corner at
all**. They are characterised only at 1.8 V and 3.3 V.

Ticket 01 confirmed against the pinned PDK that `gf180mcu_fd_sc_mcu7t5v0`, despite the `5v0`
in its name, ships fifteen Liberty corners across three voltage families: 5.0 V, 3.3 V (3v00,
3v30, 3v60) and 1.8 V (1v62, 1v80, 1v98). The foundry SRAM carries the same three families,
so it follows the core supply either way. `gf180mcu_fd_io` is characterised at 2v50, 3v30 and
5v00. The `5v0` is the oxide, not the only supported supply, so both options are live.

The choice is straightforward to state and consequential to get wrong:

- **Core at 3.3 V.** The OCD SRAM drops in with a matched supply, no level shifters at the
  memory boundary, and 0.155 mm²/KiB instead of 0.409. Standard cells run slower at 3.3 V
  than at 5.0 V, which eats into the 25 MHz target in ticket 05.
- **Core at 5.0 V.** Faster cells, and the foundry SRAM works natively. But the OCD macros
  become unusable without a level shifter on every SRAM interface, which costs area, costs
  timing, and adds a whole class of things to get wrong on a first tapeout.

This is a power architecture decision that reaches into the memory choice (ticket 11), the
frequency target (ticket 05) and the pad ring (ticket 06, since IO supplies and the core
supply need separate pads and the slot only has so many).

Also decide what the IO ring runs at, whether the design is single-supply or multi-supply,
and if multi-supply, where the domain crossings are and what shifts them.

Three things ticket 01 turned up that shape how the answer gets implemented:

- **3.3 V is an override, not a default.** The PDK's LibreLane config for `gf180mcuD`
  hardcodes `VDD_PIN_VOLTAGE 5.00` and builds `CELL_LIBS`, `STA_CORNERS` and `DEFAULT_CORNER`
  from the 5v00, 4v50 and 5v50 corners only. Choosing 3.3 V means overriding all four in
  `flow/config.yaml`, and nothing warns you if you change the supply and leave the corners.
- **A native 3.3 V standard cell library exists.** `gf180mcu_as_sc_mcu7t3v3` ships a LibreLane
  config already pinned to 3v30. It is a lead, not a recommendation: it is not built into the
  pinned PDK, and its config writes `::env(LIB)` where the current `gf180mcuD` config writes
  `::env(CELL_LIBS)`, which suggests nobody has run it under LibreLane 3.x. Deciding to use it
  would need a ticket of its own.
- **1.8 V is characterised too.** Probably not wanted on a first tapeout, but it exists, and
  the OCD SRAM is characterised there as well, so rule it out deliberately rather than by
  omission.

## Definition of done

A named core supply with the reasoning written down, a statement of whether the design is
single or multi supply, the power pad allocation, and confirmation from the pinned PDK that
the chosen standard-cell corner actually exists. Feeds tickets 05, 06 and 11.

## Answer

**Core at 3.3 V, single supply, on the standard cell library already in use.** The IO ring is
3.3 V as the buildable baseline, but that half is provisional and now belongs to ticket 18.

| | decided | basis |
| --- | --- | --- |
| core supply | **3.3 V** | keeps both SRAM families live; costs logic depth only |
| standard cells | `gf180mcu_fd_sc_mcu7t5v0`, unchanged | fully characterised at 3.3 V |
| signoff corners | `ss_125C_3v00`, `tt_025C_3v30`, `ff_n40C_3v60` | all present in the pinned PDK |
| IO ring | 3.3 V, single supply, **provisional** | the only arrangement `gf180mcu_fd_io` can build |
| power pads | 9 `dvdd` / 9 `dvss`, distributed, **provisional** | ticket 18 sets the final split |
| clock budget | 50 ns for 20 MHz, working number | ticket 05 owns the final target |
| 1.8 V | ruled out | foundry SRAM needs 56.57 ns at `ss_125C_1v62` |

### The ticket's premise was wrong in the design's favour

This was framed as a choice between a fast library and a dense memory. It is not a library
choice at all. `gf180mcu_fd_sc_mcu7t5v0` carries **all 229 cells at every one of its fifteen
corners**, and cell geometry does not move with the corner: `nand2_1` is 10.976 µm² at
`ss_125C_3v00` exactly as at `ss_125C_4v50`. The `5v0` is the oxide, not the supply. So 3.3 V
is four LibreLane settings, not a new library, and **ticket 10's 311.3 kGE and 9.76 mm² stand
unchanged**. The open thread ticket 10 left, that a 3.3 V choice would force a re-measurement
against a different library, is closed rather than deferred.

That leaves an asymmetry the ticket did not see. The foundry SRAM is characterised at 3.3 V
as well as 5.0 V, so **3.3 V keeps both macro families available** and lets ticket 11 choose
on merit, while 5.0 V would have removed ticket 07's 2.6x density permanently. 3.3 V is the
option-preserving choice and 5.0 V the option-closing one, and that is most of the decision.

The price is logic depth, and only that. Ticket 10 measured 35 stages at both corners: 19.9 ns
at 5.0 V, 29.1 ns at 3.3 V. Against 40 ns that is 50% versus 73%; against 50 ns it is 40%
versus 58%. The clock budget moves to 50 ns, so 3.3 V now has roughly the margin 5.0 V had at
25 MHz. Dynamic power also falls to (3.3/5.0)² = 44%.

**1.8 V is ruled out on measurement.** `gf180mcu_fd_ip_sram__sram512x8m8wm1` needs a
`min_period` of 56.57 ns at `ss_125C_1v62`, so the memory alone misses a 20 MHz cycle before
any logic exists. `gf180mcu_fd_io` has no 1.8 V family either.

### Why the IO ring could not be settled here

The ticket asked for a single-or-multi-supply statement. The honest answer is that the pinned
PDK as built can only produce a single-supply die, and that this is deliberate on the
foundry's part rather than an oversight.

**`gf180mcu_fd_io` has no core-supply pad cell.** It ships exactly two: `__dvdd`, with pins
DVDD, DVSS and VSS, and `__dvss`, with DVDD, DVSS and VDD. Neither bonds a core rail, and the
LEF geometry confirms which rail each one actually drops to the pad: on `__dvdd` only DVDD
reaches Metal2, with DVSS and VSS present on Metal3 to Metal5 as pass-through rails only.
`gf180mcu_ef_io` does not help, carrying only `bi_t` in this distribution. So core VDD can
reach a pin only by being tied to DVDD. wafer.space confirm the intent, in Leo Mouser's
words: "The foundry-provided pads short the core and I/O domain on purpose."

**And 5 V tolerance is not an escape hatch.** A 3.3 V ring cannot simply accept 5 V inputs.
In `gf180mcu_fd_io__bi_t` every output PMOS is a `pfet_06v0_dss` with its bulk tied to DVDD
and its drain on `PAD`, and the ESD network clamps `PAD` to DVDD as well
(`comp018green_esd_clamp_v5p0_DVDD`, plus `ppolyf_u` bleed resistors from PAD to DVDD). Drive
a pin to 5 V with DVDD at 3.3 V and the drain-bulk junction forward-biases about 0.7 V above
the rail, dumping pad current into the supply. The devices are 6 V rated and survive 5 V, but
only with DVDD at 5 V to keep those junctions reverse-biased. These pads are 5 V **capable**,
not 5 V **tolerant**.

Taken together, with `fd_io` alone a 5 V-signalling die is necessarily a 5 V-core die, which
loses the OCD SRAM and with it the 16 KiB memory target. That is the trade, and it is why the
IO ring is worth a ticket of its own rather than a default.

**The way out exists and is pinned but unbuilt.** `gf180mcu_ocd_io`, Tim Edwards' 3.3/5 V
cells, is fixed in `nodeinfo.json` at `6e0e354a…`, and its LibreLane config already ships in
the PDK. The only difference from the `gf180mcu_fd_io` config's `PAD_PLACE_IO_TERMINALS` is
two extra entries, `__vss/VSS` and `__vdd/VDD`: separate core power and ground pads, exactly
the separation Leo describes. It sits in the identical position to `gf180mcu_ocd_ip_sram`
from ticket 07, referenced throughout the pinned PDK and absent from `libs.ref`. The same
`ciel build` obtains both, which is the build ticket 15 already exists to run.

So the IO decision waits on evidence rather than on argument. **Ticket 18** owns it, blocked
on 15. Until then 3.3 V single supply is the baseline, and it is a real fallback rather than a
placeholder: it builds today, it needs no unbuilt library, and board-level shifting covers any
5 V system a test chip needs to talk to.

### Measured, not assumed

The map's standing preference is to measure rather than reason about what a change should have
done, so the flow defaults were moved to the chosen corner and `make area` and `make sta`
re-run. The claim that 3.3 V costs no area is now a measurement:

| | ticket 10, `ss_125C_4v50` at 40 ns | this ticket, `ss_125C_3v00` at 50 ns |
| --- | ---: | ---: |
| flattened cells | 118,998 | **118,998** |
| flattened cell area | 3,416,649 µm² | **3,416,649 µm²** |
| kGE | 311.3 | **311.3** |
| hierarchical cells | 172,017 | **172,017** |
| placed at 35% | 9.76 mm² | **9.76 mm²** |
| left for SRAM | 3.16 mm² | **3.16 mm²** |

Identical, to the cell. The concern behind mapping at the signoff corner, that a slower corner
makes ABC buy drive strength, does not materialise here because 50 ns at 3v00 is about as
slack as 40 ns at 4v50, so both passes produce the same netlist. If the clock budget ever
tightens, that equivalence stops holding and the area has to be re-measured.

Timing, both arms, against the new 50 ns budget:

| corner | stages | median stage | floor | ceiling | of 50 ns |
| --- | ---: | ---: | ---: | ---: | ---: |
| `ss_125C_3v00` (3.3 V, signoff) | 35 | 0.832 ns | 29.1 ns | 34.3 MHz | **58%** |
| `ss_125C_4v50` (5.0 V, informational) | 35 | 0.568 ns | 19.9 ns | 50.3 MHz | 40% |

So 3.3 V at 20 MHz has slightly better margin than 5.0 V had at 25 MHz, which is the trade
this ticket made. The unbuffered nets are unchanged and remain the real risk rather than the
supply: 10,130 loads on `apb2per_newdebug_i.clk_i`, 4,842 on `soc_peripherals_i.apb_reset`,
22 nets above 500 fanout, with no clock or reset tree built.

### Consequences for other tickets

- **Ticket 11 is unblocked**, its last open dependency being this one. It gets both macro
  families to choose between.
- **Ticket 15 is unblocked and in scope**, not ruled out as it would have been at 5.0 V. It
  widened from one library to three: `gf180mcu_ocd_ip_sram` for density, `gf180mcu_ocd_io` for
  ticket 18, and `gf180mcu_as_sc_mcu7t3v3` to price a 3.3 V-native thin-oxide library against
  ticket 10's baseline. One build answers all three, and its DoD now carries that measurement.
- **Ticket 05** gets 50 ns as a working budget rather than a decision, plus one input: a
  single-supply die leaves `apb_pll`'s five analog supply ports (`AVDD`, `AVDD2`, `AVSS`,
  `VDDC`, `VSSC`) with no rail to reach, which strengthens the case for removing them. Ticket
  18 could change that.
- **Ticket 06** is unaffected in its arithmetic. Power pads are separate from the 56 signal
  pads, so the 57-into-56 problem does not move.
- **Ticket 17** keeps its premise. The critical path is measured at both corners, and 3.3 V
  makes the interconnect's contribution worse in absolute terms, not better.

### What was committed

- `run.sh`, `flow/synth/area.sh` and `flow/synth/sta.sh` now default to `ss_125C_3v00` and a
  50 ns clock. They previously defaulted to `ss_125C_4v50` and 40 ns, so every future
  `make area` would silently have measured a chip we have decided not to build. `sta.sh` also
  had `ss_125C_4v50` hardcoded outside its corner loop for the fanout report; that now follows
  `LIB_CORNER` through a `SIGNOFF_CORNER` variable, and the loop reports 3.3 V first with
  5.0 V kept as the informational arm.
- `flow/README.md` gains the four-setting corner override that seeding from the template will
  not do for you, and its `CLOCK_PERIOD` entry moves to 50.
- `README.md` and `docs/porting-analysis.md` section 3 no longer call the standard cell
  libraries "5 V" without qualification. The report's section 10.4 gains a resolution note
  recording that the IO ring, not the standard cells, is the hard half of the supply question.
