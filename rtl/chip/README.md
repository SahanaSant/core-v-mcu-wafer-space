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

A `1x1` slot provides 56 signal pads: 40 bidirectional, 14 input-only, 2 analog.

Upstream currently needs 57. `core_v_mcu.sv` exposes `N_IO = 48` general-purpose pads plus
`jtag_tck/tdi/tdo/tms/trst`, `ref_clk_i`, `rstn_i`, `bootsel_i` and `stm_i`. It does not fit.

Planned allocation:

| Pads | Count | Assigned to |
| --- | --- | --- |
| bidirectional | 40 | `io_in_i` / `io_out_o` / `io_oe_o`, with `jtag_tdo_o` on one as output |
| input-only | 8 of 14 | `jtag_tck`, `jtag_tdi`, `jtag_tms`, `jtag_trst`, `ref_clk_i`, `rstn_i`, `bootsel_i`, `stm_i` |

So `N_IO` drops from 48 to 40, and `N_APBIO` must drop with it: GPIO(32) + PWM(16) + I2CS(3)
is 51 functions competing for 40 pads.

`pad_control.sv` and `safe_domain.sv` are **generated files**. Regenerate the pad multiplexer
with upstream's `util/ioscript.py` and `perdef.json`. Hand-edited pad tables will not be
accepted upstream and will drift from the software headers that `make sw` produces.
