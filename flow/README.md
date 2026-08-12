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

- `CLOCK_PERIOD: 40` gives 25 MHz. That is the realistic target for this process and flow.
  The SRAM macro itself runs at 164 MHz typical at 5.0 V, so the limit is standard-cell delay
  and open-tool timing closure, not memory.
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

Yosys alone will not read upstream's RTL, which uses interfaces, packages and packed structs
across more than fifty files. Two options, in order of preference:

1. `USE_SLANG: True` with `SLANG_ARGUMENTS: ['--keep-hierarchy']`. Both appear commented out
   in the template config. yosys-slang elaborates PULP Platform designs including
   Snitch-Cluster and Cheshire, so this is the most likely path to work.
2. The PULP chain: Bender, Morty, SVase, then sv2v down to Verilog-2005. This is what PULP
   used for Basilisk and Iguana, and `lip6/core-v-180-mcu` uses sv2v plus svase on CV32E40P
   specifically. Read their CI before starting.

Either way, get the design elaborating before touching physical design. That is where the
schedule risk is.

## Macro placement

Sixteen to thirty-two SRAM macros will not place themselves. Write `macro_placement.cfg`
explicitly and leave routing channels between rows. `GRT_ALLOW_CONGESTION: true` is set in
the template but is not a substitute for a floorplan.

## Sign-off

LibreLane finishing is not sign-off. Run `make precheck` and treat a clean precheck as the
definition of done. It checks top cell name and count, origin, database units, maximum metal
layer, slot dimensions, density, zero-area polygons, antenna rules, and DRC.
