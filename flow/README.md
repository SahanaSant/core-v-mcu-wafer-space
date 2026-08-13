# Physical implementation

LibreLane configuration for hardening `chip_top`. Run it with `make harden` from the
repository root; outputs land in `runs/` and `final/`, both gitignored.

## Files to add here

| File | Purpose |
| --- | --- |
| `config.yaml` | LibreLane flow configuration, `meta.version: 3` |
| `chip_top.sdc` | timing constraints, used for both PnR and sign-off |
| `pdn/pdn_cfg.tcl` | power distribution network |
| `macros.yaml` | SRAM macro definitions: LEF, LIB, GDS, netlist |
| `macro_placement.cfg` | explicit placement for every SRAM macro |
| `gf180mcu_render.lyp` | KLayout layer properties for rendering |

Seed all of these from `librelane/` in the
[wafer.space project template](https://github.com/wafer-space/gf180mcu-project-template).
It is pre-tuned for `gf180mcuD` and the slot geometry. Start from it and diff, rather than
writing configuration from first principles.

## Settings that matter

The template's defaults encode hard-won knowledge. Change them deliberately, not casually.

- **Supply and corners.** Ticket 14 settled the core at 3.3 V, single supply, and the PDK's
  own `libs.tech/librelane/config.tcl` defaults to 5 V, so four settings have to be overridden
  after seeding from the template and nothing warns you if you miss one:
  `VDD_PIN_VOLTAGE: 3.30`, and `CELL_LIBS`, `STA_CORNERS` and `DEFAULT_CORNER` rebuilt from
  `tt_025C_3v30`, `ff_n40C_3v60` and `ss_125C_3v00`. The library does not change:
  `gf180mcu_fd_sc_mcu7t5v0` carries all 229 cells at every one of its fifteen corners, and
  cell geometry is identical across them, so the supply choice costs no area.
- `CLOCK_PERIOD: 50` gives 20 MHz, revised from 40 by ticket 14. At 3.3 V the synthesised
  logic is 35 stages and 29.1 ns deep, which is 73% of a 40 ns budget and 58% of a 50 ns one,
  before any wire RC, clock tree or hold fixing exists. Ticket 05 owns the final number. The
  memory is not the limit either way: the foundry macro needs 18.26 ns at `ss_125C_3v00`.
- `PL_TARGET_DENSITY_PCT: 35`. Run 1 designs achieved 3k to 14k cells/mm², against a
  theoretical maximum several times higher. Plan against 8k to 12k.
- Hold-slack margins are overfixed at 0.30 to 0.35 ns for a reason. Leave them alone.
- `PDN_CORE_RING_*WIDTH: 25`, because 30 µm is the maximum metal width before slotting rules
  apply.
- `MAGIC_GDS_FLATGLOB` carries a long list of cell patterns that must be flattened to avoid
  false DRC errors, most of them inside the foundry SRAM macros. Any new macro will need its
  own entries, discovered the hard way.
- `ERROR_ON_MAGIC_DRC: False`, because Magic DRC is not a submission gate. Review the
  violations anyway.

## SystemVerilog front end

**Settled: yosys-slang.** Yosys alone will not read upstream's RTL, which uses interfaces,
packages and packed structs across more than fifty files, but the `read_slang` plugin shipped
with Yosys 0.67 in the pinned container reads the whole SoC and elaborates `core_v_mcu` in
about three seconds. The PULP chain (Bender, Morty, SVase, sv2v) is not needed and Morty and
SVase are not in the container anyway. In LibreLane this is `USE_SLANG: True` with
`SLANG_ARGUMENTS: ['--keep-hierarchy']`.

Reproduce it with `make elaborate`, which runs `flow/synth/elaborate.sh`. That script asks
fusesoc to resolve upstream's unmodified `default` target from the submodule, filters the
eFPGA out of the resulting file list, adds `rtl/gf180mcu/` and `flow/synth/stubs.sv`, and runs
the front end. It ends by printing every module the design instantiates but does not define,
which is the work list for `rtl/gf180mcu/`.

Two settings the flow config has to match. `-D SYNTHESIS` is passed, which only disables
assertion blocks here; the `SCM_IMPLEMENTED` and `SCM_BASED_ICACHE` defines it switches on in
`pulp_soc_defines.svh` are referenced nowhere in the RTL. `PULP_FPGA_EMUL` is left undefined,
which is what selects the ASIC branches in `soc_domain.sv` and `safe_domain.sv`; fusesoc's
`default` target declares it as a parameter defaulting to true, so do not let a backend pass
it through.

## Synthesis must flatten

Not optional, and worth 1.30 mm² of cell area. The eFPGA slot is replaced by
`rtl/gf180mcu/gf180_efpga_stub.sv`, whose four TCDM master ports hold `req` low forever.
Flattened, constant propagation removes them completely: ticket 10 confirmed
`gen_l2_demux[5]` through `[8]` contain zero cells in the flat netlist while ports 0 to 4
survive. With module boundaries kept, nothing propagates across them, all nine master ports
are built in full, and the three crossbars arbitrate between nine masters instead of five.
Measured, that is 4.72 mm² hierarchical against 3.42 mm² flattened.

So do not set `SYNTH_HIERARCHY_MODE` to keep hierarchy, and if a future ticket wants
hierarchy preserved for some other reason, parameterise `N_EFPGA_TCDM_PORTS` down first.
`make area` runs both ways precisely so this stays visible.

Two other things synthesis needs, both discovered by ticket 10. `dfflibmap` maps flip-flops
only, and upstream's `apb_soc_ctrl` infers four latches (`r_bootsel[1:0]`,
`reset_reason[1:0]`), so the PDK's `libs.tech/librelane/$SCL/latch_map.v` has to be applied
or they survive as behavioural `always` blocks. And the design arrives at place and route
with no buffering at all on its highest-fanout nets: 10,130 loads on the SoC clock, 4,841 on
`apb_reset`, 4,309 on a reset-derived enable, twenty-two nets above 500. Clock tree synthesis
handles the first; the reset nets are `repair_design`'s problem and are worth checking
explicitly rather than assuming.

## Macro placement

Sixteen to thirty-two SRAM macros will not place themselves. Write `macro_placement.cfg`
explicitly and leave routing channels between rows. `GRT_ALLOW_CONGESTION: true` is set in
the template but is not a substitute for a floorplan.

## Sign-off

LibreLane finishing is not sign-off. Run `make precheck` and treat a clean precheck as the
definition of done. It checks top cell name and count, origin, database units, maximum metal
layer, slot dimensions, density, zero-area polygons, antenna rules, and DRC.
