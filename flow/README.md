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
- `CLOCK_PERIOD: 50` gives 20 MHz, revised from 40 by ticket 14. **Do not plan against
  `make sta`'s headline number**: ticket 19 found it reports the path with the worst raw
  arrival, which pre-layout is set by unbuffered fanout rather than by depth, so it is not the
  deepest path and it changes identity under unrelated churn. The same netlist that reports 35
  stages in the AXI crossbar carries a 90-stage path inside the CV32E40P, from the decoder's
  `instr_rdata_i` to `alu_operand_a_ex`, at about 0.8 ns a stage. That is roughly 70 ns at
  3.3 V, over budget, and it was there in ticket 10's netlist too. Ticket 22 owns it and
  ticket 05 owns the final clock number. The memory is not the limit either way: the OCD macro
  reports 13.46 to 15.87 ns at `ss_125C_3v00`, against a 50 ns budget.
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

**The liberty has to be read before the RTL.** As of ticket 16,
`rtl/gf180mcu/gf180_clk_gate.sv` instantiates three PDK cells by name, and yosys-slang will
import an instance as a black box only if some earlier yosys command already loaded that
module. `flow/synth/filelist.sh` resolves the standard-cell liberty and both `elaborate.sh`
and `area.sh` open with `read_liberty -lib` on it. LibreLane's own synthesis step already
does this, so no config setting follows from it, but a hand-written yosys script that reads
the RTL first will stop on an unknown module rather than degrade gracefully. Reading the
liberty is also what gives those cells real area in `stat -liberty` instead of zero.

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
with no buffering at all on its highest-fanout nets: 10,122 loads on the SoC clock, 4,684 on
`apb_reset`, 4,290 on a debug-control net, twenty-three nets above 500. Clock tree synthesis
handles the first; the reset nets are `repair_design`'s problem and are worth checking
explicitly rather than assuming. These nets are also why `make sta`'s reported path is the
wrong one, per the clock-period note above.

## Macro placement

Sixteen `gf180mcu_ocd_ip_sram__sram1024x8m8wm1`, fixed by ticket 11 and instantiated by
ticket 19, will not place themselves. Write `macro_placement.cfg` explicitly and leave routing
channels between rows: **every signal pin on this macro is on Metal2 in a 3 um band along the
bottom edge**, all 37 of them, so each macro presents its whole interface on one side and
orientation is not free. `GRT_ALLOW_CONGESTION: true` is set in the template but is not a
substitute for a floorplan. Ticket 21 owns this.

## Sign-off

LibreLane finishing is not sign-off. Run `make precheck` and treat a clean precheck as the
definition of done. It checks top cell name and count, origin, database units, maximum metal
layer, slot dimensions, density, zero-area polygons, antenna rules, and DRC.
