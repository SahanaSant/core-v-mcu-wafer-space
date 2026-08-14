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

Seed `chip_top.sv` from `src/chip_top.sv` in the
[wafer.space project template](https://github.com/wafer-space/gf180mcu-project-template)
rather than writing it from scratch. The template's pad ring generator and slot geometry are
already correct, and reproducing them by hand is how people lose a shuttle slot.

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

`pad_control.sv` is the only **generated file** here — `safe_domain.sv` only references
`N_APBIO`/`N_GPIO` parametrically and needs no regeneration, despite this file previously saying
otherwise. Regenerate the pad multiplexer with upstream's `util/ioscript.py`,
`core-v-mcu/perdef.json` and `core-v-mcu/gf180-pin-table.csv`. Hand-edited pad tables will not be
accepted upstream and will drift from the software headers that `make sw` produces.
