# Write chip_top.sv and route the design against ticket 21's floorplan

Type: task
Status: open
Blocked by: 23, 24

## Question

Ticket 21 decided the shape (2 rows x 8 columns), placement (south edge, private banks then
interleaved channels) and power domain (single 3.3 V rail, no split) for the sixteen SRAM
macros, but stopped short of building any of it: `rtl/chip/chip_top.sv` doesn't exist, and the
SoC can't even elaborate end to end until tickets 23 and 24 land (`a2_bootrom` and `apb_pll` are
still black boxes). This ticket is the build: write the top level, seed the LibreLane
configuration from the wafer.space template, and get a run through detailed routing.

What has to happen:

- **`rtl/chip/chip_top.sv`**, seeded from `src/chip_top.sv` in the
  [wafer.space project template](https://github.com/wafer-space/gf180mcu-project-template), not
  written from scratch. One instance of `core_v_mcu`, the pad ring (`gf180mcu_ocd_io` per ticket
  18, 40 bidirectional + jtag + ref_clk_i/rstn_i/stm_i per ticket 06's pin table), and the five
  wafer.space marker cells (`qrcode_id`, `shuttle_id`, `project_id`, `marker`, `logo`) each
  present exactly once. `PAD_SOUTH`/`EAST`/`NORTH`/`WEST` side assignment is new work here, not
  fixed by any prior ticket.
- **`flow/config.yaml`**, `flow/chip_top.sdc`, `flow/pdn/pdn_cfg.tcl`, `flow/macros.yaml`,
  `flow/macro_placement.cfg`, `flow/gf180mcu_render.lyp`, per `flow/README.md`'s table. Seed
  from the template's `librelane/` directory and diff, per the map's Notes. The template's own
  `macros.yaml` folds instance placement into the macro definition (no separate
  `macro_placement.cfg`); check whether that structure or the two-file split `flow/README.md`
  describes is what the LibreLane version in this container actually wants before committing to
  one.
- Sixteen macro instances placed per ticket 21's decision: 2 rows x 8 columns, south edge,
  private bank 0/1 then interleaved channel 0/1 left to right. Compute exact coordinates from
  the macro LEF `SIZE` and the `slot_1x1` core area, the way `patch_ocd_sram.sh` already computes
  area from LEF rather than hardcoding it.
- PDN: single 3.3 V core ring (ticket 21), macro perimeter grids on Metal2/Metal3, Metal4/Metal5
  free over the macros, following the template's `pdn_3v3_sram.tcl` pattern rather than writing
  the stripe geometry from scratch.
- `MAGIC_GDS_FLATGLOB` entries for the OCD SRAM macros, discovered by running into false DRC
  errors, added to `flow/config.yaml`'s list.
- Four LibreLane settings moved together for the 3.3 V corner, per `flow/README.md`:
  `VDD_PIN_VOLTAGE: 3.30`, `CELL_LIBS`, `STA_CORNERS`, `DEFAULT_CORNER` from `tt_025C_3v30`,
  `ff_n40C_3v60`, `ss_125C_3v00`.

## Definition of done

`make harden` completes through detailed routing with no fatal errors. Quote the real numbers:
final density against the 35% target, whether the design actually placed and routed at that
density or needed a different target, and any `MAGIC_GDS_FLATGLOB` patterns discovered along the
way. Sign-off (a clean `make precheck`) is not required to close this ticket, matching ticket
21's own DoD language: this closes when the design places and routes, not when it passes
precheck.

## Answer

<!-- filled on resolution -->
