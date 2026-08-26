# Pin-out and the pad ring

`rtl/chip/chip_top.sv` holds the pad cells and the five wafer.space marker cells and nothing
else, so its instance names stay a one-to-one match for the `PAD_SOUTH` / `PAD_EAST` /
`PAD_NORTH` / `PAD_WEST` lists in `flow/slot_1x1.yaml`. `rtl/chip/chip_core.sv` is everything
between the ring and the SoC: one `core_v_mcu` instance and the fan-out of `pad_cfg_o` onto
the pads' configuration pins.

## Pad positions are not ours to choose

The wafer.space template's README is explicit: **do not change the number of pads**, because
the default bonding setup is drawn against their positions, and **do not change any power or
ground pad**, because the default breakout PCB is. What may change is a signal pad's *type*.

The ring is 74 positions: 56 signal (40 bidirectional, 14 input-only, 2 analog) and 18
power. All of them are the template's, in the template's order, and exactly one type
differs. The template's `inputs[11]` position, at the head of the west signal run, is a
`bi_24t` here rather than an `in_c`: `jtag_tdo_o` is the one signal outside the io array that
drives, `in_c` and `in_s` have no output driver, and spending a bidirectional pad from the io
array on it would have cost the spare at `io_num` 39 for nothing. That is also why the input
array is 11 wide here and 12 in the template.

Power pad counts are the breakout PCB's, not a design choice: `dvdd` 6, `dvss` 8, `vdd` 2,
`vss` 2. Two core supply pads for a design this size is worth watching in
`OpenROAD.IRDropReport` rather than assuming; the measured worst-case drop is 7.8 µV.

## Pad budget

A 1x1 slot provides 56 signal pads: 40 bidirectional, 14 input-only, 2 analog.

`core_v_mcu.sv` exposes `N_IO = 40` general-purpose pads, all bidirectional, plus
`jtag_tck/tdi/tdo/tms/trst`, `ref_clk_i`, `rstn_i` and `stm_i` as separate ports outside that
array. `bootsel_i` is gone entirely, since there is no bootsel-driven ROM fallback.

Of the 40 io pads, 39 are assigned (`core-v-mcu/gf180-pin-table.csv`) and one is spare:

| io_num | Function | io_num | Function |
| --- | --- | --- | --- |
| 0-15 | GPIO 0-15 | 28-31 | qspim1 (storage/sensors), single-line |
| 16-23 | PWM, 8 of 16 channels | 32-34 | sdio0, 1-bit |
| 24-25 | i2cm0 | 35-38 | qspim0 (boot flash), fixed mux slot |
| 26-27 | uart0 | 39 | spare |

`N_APBIO` is 24 (gpio 16 + pwm 8; `apb_i2cs` is cut).

Only some pad-forced cuts save silicon. `apb_adv_timer`, `udma_spim_top` and `udma_sdio_top`
are fixed-shape upstream IP with no channel-count parameter, so bonding fewer pins is free.
`N_UART` (2 → 1) is a real generate-loop instance count, so cutting it is a real area saving.

## Where each function lands on the ring

`bidir[n]` carries `io_num` n directly, and the template's ring order puts:

- **South**: `ref_clk_i`, `rstn_i`, then GPIO 0 to 13. The SRAM array runs along this edge,
  so the quietest functions go here.
- **East**: GPIO 14/15, PWM, i2cm0.
- **North**: uart0, qspim1, sdio0, qspim0. Both analog pads are here, both unconnected.
- **West**: all five JTAG signals in one contiguous run, immediately below the core VDD/VSS
  pair.

The 8 signals outside the io array take the input row and the two dedicated pads:

| Signal | Pad | Why |
| --- | --- | --- |
| `ref_clk_i` | `in_s` | Schmitt trigger: a board oscillator over a wire bond is the one input whose edge quality this chip does not control |
| `rstn_i` | `in_c`, pulled down | an unbonded reset holds the chip in reset |
| `jtag_tck/tms/tdi/trst`, `stm_i` | `inputs[0..4]` | |
| `jtag_tdo_o` | the retyped `bi_24t` | the only output outside the io array |

The remaining six input pads and both analog pads are spare. Every spare input is pulled down
rather than left floating; the analog pads are unconnected on both sides.

## Pad configuration bits

`pad_cfg_o` is upstream's six-bit-per-pad electrical configuration bus, which upstream leaves
undefined ("electrical configuration, which is not implemented in the current design").
`chip_core.sv` fixes the mapping onto `bi_24t`'s five configuration pins and nowhere else
does:

| Bit | Pin |
| --- | --- |
| 0 | CS |
| 1 | SL |
| 2 | IE |
| 3 | PU |
| 4 | PD |
| 5 | reserved |

The register resets to all ones, which under this mapping is the safe state: Schmitt inputs,
slow slew, input buffer on, no pull. The pad's pull devices are `~OE && PU && ~PD` and
`~OE && ~PU && PD`, so both bits high is "neither" rather than contention.

## Regenerating the pad multiplexer

`pad_control.sv` in the submodule is a **generated file**. Regenerate it with upstream's
`util/ioscript.py` against `core-v-mcu/perdef.json` and `core-v-mcu/gf180-pin-table.csv`.
Hand-edited pad tables will not be accepted upstream and will drift from the software headers
the boot ROM and application builds generate.

`safe_domain.sv` only references `N_APBIO` and `N_GPIO` parametrically and needs no
regeneration.

## Precheck requirements this ring has to satisfy

- The top cell must be named **`chip_top`**, be the only top cell, and sit at origin (0, 0).
- Layout database units must be 0.001 µm, with Metal5 as the highest layer used.
- Die dimensions must match the declared slot.
- Chip-on-board delivery needs the wafer.space marker cells present exactly once each:
  `gf180mcu_ws_ip__qrcode_id`, `shuttle_id`, `project_id`, `marker`, `logo`.
