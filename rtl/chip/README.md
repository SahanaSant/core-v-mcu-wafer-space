# Chip top level

The wafer.space die: pad ring, power, and one instance of the upstream `core_v_mcu` SoC.
This is the boundary between upstream RTL and this shuttle, so it stays here and is never
contributed upstream.

## Requirements

The precheck enforces these, so get them right from the start:

- The top cell must be named **`chip_top`**, be the only top cell, and sit at origin (0, 0).
- Layout database units must be 0.001 µm, with Metal5 as the highest layer used.
- Die dimensions must match the declared slot.
- Chip-on-board delivery needs the wafer.space marker cells present exactly once each:
  `gf180mcu_ws_ip__qrcode_id`, `shuttle_id`, `project_id`, `marker`, `logo`.

`chip_top.sv` is seeded from `src/chip_top.sv` in the
[wafer.space project template](https://github.com/wafer-space/gf180mcu-project-template)
rather than written from scratch. The template's pad ring generator and slot geometry are
already correct, and reproducing them by hand is how people lose a shuttle slot.

Two files, following the template's own split. `chip_top.sv` holds pad cells and the five
marker cells and nothing else, so that its instance names stay a one-to-one match for the
`PAD_SOUTH`/`PAD_EAST`/`PAD_NORTH`/`PAD_WEST` lists in `flow/slot_1x1.yaml`. `chip_core.sv`
is everything between the ring and the SoC: one `core_v_mcu` instance and the fan-out of
`pad_cfg_o` onto the pads' configuration pins.

## Pad positions are not ours to choose

The template's README is explicit: **do not change the number of pads**, because the default
bonding setup is drawn against their positions, and **do not change any power or ground
pad**, because the default breakout PCB is. What may change is a signal pad's *type*.

So all 58 pad positions are the template's, in the template's order, and exactly one type
differs: the template's `inputs[11]` position, at the head of the west signal run, is a
`bi_24t` here rather than an `in_c`. `jtag_tdo_o` is the one signal outside the io array that
drives, `in_c`/`in_s` have no output driver, and spending a bidirectional pad from the io
array on it instead would have cost ticket 06's spare at `io_num` 39 for nothing. That is
also why the input array is 11 wide here and 12 in the template.

This supersedes ticket 18's provisional 5/5/4/4 power-pad split, which was explicitly
unmeasured: the counts are `dvdd` 6, `dvss` 8, `vdd` 2, `vss` 2, and they are the breakout
PCB's, not a design choice. Two core supply pads for a design this size is worth watching in
`OpenROAD.IRDropReport` rather than assuming.

## Pad budget

A `1x1` slot provides 56 signal pads: 40 bidirectional, 14 input-only, 2 analog. Resolved by
ticket 06 (`.scratch/gf180mcu-tapeout/issues/06-pad-and-io-budget.md`); this section records the
result, not the plan.

`core_v_mcu.sv` exposes `N_IO = 40` general-purpose pads (all bidirectional; only pads that can
drive output work at all, so every general function lives here) plus `jtag_tck/tdi/tdo/tms/trst`,
`ref_clk_i`, `rstn_i` and `stm_i` as separate ports outside that array, unchanged from upstream
(`bootsel_i` is gone entirely, ticket 04's boot-architecture decision). Of the 40, 39 are assigned
(`core-v-mcu/gf180-pin-table.csv`), one spare:

| io_num | function | io_num | function |
| --- | --- | --- | --- |
| 0-15 | GPIO 0-15 | 28-31 | qspim1 (storage/sensors), single-line |
| 16-23 | PWM, 8 of 16 channels | 32-34 | sdio0, 1-bit |
| 24-25 | i2cm0 | 35-38 | qspim0 (boot flash, ticket 04), fixed mux slot |
| 26-27 | uart0 | 39 | spare |

`N_APBIO` is 24 (gpio 16 + pwm 8; apb_i2cs is cut, ticket 12). Only some of the pad-forced cuts
save silicon: `apb_adv_timer`, `udma_spim_top` and `udma_sdio_top` are fixed-shape upstream IP
with no channel-count parameter, so bonding fewer pins is free; `N_UART` (2→1) is a real
generate-loop instance count, so cutting it is a real area saving.

Where each function lands on the ring follows from that: `bidir[n]` carries `io_num` n
directly, and the template's ring order puts GPIO 0 to 13 on the south edge (the quietest
functions on the edge ticket 21 gave to the SRAM array), GPIO 14/15 with PWM and i2cm0 on the
east, uart0/qspim1/sdio0/qspim0 on the north, and all five JTAG signals in one contiguous run
on the west, immediately below the core VDD/VSS pair.

The 8 signals outside the io array take the input row and the two dedicated pads:
`ref_clk_i` on the Schmitt-trigger `in_s` (a board oscillator over a wire bond is the one
input whose edge quality this chip does not control), `rstn_i` on an `in_c` pulled down so an
unbonded reset holds the chip in reset, `jtag_tck/tms/tdi/trst` and `stm_i` on `inputs[0..4]`,
and `jtag_tdo_o` on the retyped pad. The remaining six input pads and both analog pads are
spare; every spare input is pulled down rather than left floating, and the analog pads are
unconnected on both sides.

`pad_cfg_o` is upstream's six-bit-per-pad electrical configuration bus, which upstream leaves
undefined ("electrical configuration, which is not implemented in the current design").
`chip_core.sv` fixes the mapping onto `bi_24t`'s five configuration pins and nowhere else
does: bit 0 to CS, 1 to SL, 2 to IE, 3 to PU, 4 to PD, bit 5 reserved. The register resets to
all ones, which under this mapping is the safe state (Schmitt inputs, slow slew, input buffer
on, no pull) because the pad's pull devices are `~OE && PU && ~PD` and `~OE && ~PU && PD`, so
both bits high is "neither" rather than contention.

`pad_control.sv` is the only **generated file** here — `safe_domain.sv` only references
`N_APBIO`/`N_GPIO` parametrically and needs no regeneration, despite this file previously saying
otherwise. Regenerate the pad multiplexer with upstream's `util/ioscript.py`,
`core-v-mcu/perdef.json` and `core-v-mcu/gf180-pin-table.csv`. Hand-edited pad tables will not be
accepted upstream and will drift from the software headers that `make sw` produces.
