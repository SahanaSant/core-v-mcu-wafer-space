# Measure the real logic area

Type: task
Status: resolved
Blocked by: 03

## Question

How large is the SoC's logic, actually?

`docs/porting-analysis.md` estimates 200 to 300 kGE for the full SoC, roughly 3 to 5 mm²
placed at 35% density, leaving 7 to 9 mm² of the 12.92 mm² core for SRAM. That estimate is
the weakest number in the entire plan, and tickets 11 and 12 both depend on it. Replace it
with a measurement.

Synthesise with memories black-boxed and technology cells stubbed, against
`gf180mcu_fd_sc_mcu7t5v0`. This does not need real SRAM wrappers, real pads or a floorplan;
it needs a cell count.

**Ticket 03 has resolved and left most of the setup behind.** `make elaborate` runs
`flow/synth/elaborate.sh`, which generates the file list from the submodule with fusesoc,
excludes the eFPGA, adds `rtl/gf180mcu/` and the black boxes in `flow/synth/stubs.sv`, and
reads the design through yosys-slang. Extend that script rather than starting a new one: the
committed, repeatable synthesis script this ticket asks for is that file plus `synth` and
`abc`. Elaboration currently reports 81,414 word-level Yosys cells, which is pre-techmap and
not a gate count, but it is the number this ticket has to replace.

Two things to watch that ticket 03 surfaced:

- The eFPGA is gone, replaced by a tie-off stub whose four TCDM master ports hold `req` low.
  They should constant-fold the interconnect ports feeding them away. Check whether they did,
  because if they did not, `soc_interconnect` is carrying four dead master ports.
- The I2C slave brings two 256×8 behavioural RAMs, 4,096 memory bits with no macro behind
  them. Expect roughly 2,048 flip-flops in `apb_i2cs` unless they are cut. Break `apb_i2cs`
  out separately in the per-module table so ticket 12 sees the cost.

**Read the Basilisk paper here** (arXiv:2405.04257, with arXiv:2406.15107 and
arXiv:2505.10060), not for the front end, which is settled. ETH Zürich and Bologna document
the custom Yosys and ABC scripting behind a 1.8 MGE to 1.1 MGE reduction on a PULP-ecosystem
SoC in an open flow. That is a quality-of-results question and this is the quality-of-results
ticket, and a third off the gate count is the difference between fitting and not.

## Definition of done

A report containing:

- Total cell count and total cell area in µm².
- Gate-equivalent count, using the GF180 7T NAND2 at roughly 6.6 µm².
- Placed area at `PL_TARGET_DENSITY_PCT: 35`, and the implied SRAM budget once subtracted
  from 12.92 mm².
- **A per-module breakdown**, so ticket 12 can cut peripherals with data rather than
  intuition. The uDMA subsystem in particular should be broken out per peripheral.
- A first look at the critical path, feeding the frequency question in ticket 05.

Commit the synthesis script so the measurement is repeatable after every RTL change. The
number will move, and re-measuring should be one command.

## Answer

**311 kGE, and it does not fit.** The estimate's gate count was nearly right and its area
was not, because the gate-equivalent conversion was wrong by a factor of 1.66. Reproduce
with `make area`; the report lands at `flow/build/area/area.md`.

| | estimate | measured |
| --- | --- | --- |
| logic | 200 to 300 kGE | **311.3 kGE** |
| cell area | 2.2 to 3.3 mm2 (at 6.6 um2/GE) | **3.417 mm2** |
| placed at 35% | 3 to 5 mm2 | **9.76 mm2** |
| left for SRAM | 7 to 9 mm2, "16 to 21 KiB" | **3.16 mm2, 7.7 KiB** |

Flattened: 118,998 cells, 3,416,649 um2, 46.9% of it sequential. Hierarchical: 172,017
cells, 4,719,649 um2. Mapped to `gf180mcu_fd_sc_mcu7t5v0` at `ss_125C_4v50` against 40 ns.
Both passes are kept because they answer different questions, and the 27.6% area gap between
them is itself a finding (see the eFPGA note below).

**The 6.6 um2 NAND2 in `docs/porting-analysis.md` section 4.3 is wrong.**
`gf180mcu_fd_sc_mcu7t5v0__nand2_1` is 2.800 x 3.920 um = **10.976 um2**, from both the
liberty `area` and the LEF `SIZE`. The report derived it as three 0.56 um sites; it is five.
Every kGE-to-area conversion in that report is 1.66x optimistic, which is the whole
difference between "3 to 5 mm2 placed" and 9.76. `area_report.py` now reads the number out
of the liberty rather than carrying a constant, so it cannot drift again.

**The conclusion in section 4.4 inverts.** "Roughly 7 to 9 mm2 remains for memory, that is 16
to 21 KiB, design for 16 KiB" becomes 3.16 mm2, which is 7.7 KiB of foundry macro. The 16 KiB
target does not fit alongside the logic as it stands. Ticket 07's OCD macro would give 20.4
KiB in the same 3.16 mm2, so **ticket 11's macro choice is now load-bearing rather than an
optimisation**: with the foundry part the design misses its own memory target.

One cross-check in the estimate's favour. 118,998 cells in 9.76 mm2 is 12,190 cells/mm2,
which sits at the top of the 8,000 to 12,000 band `docs/porting-analysis.md` says to plan
against, and near the top of the 3,000 to 14,000 Run 1 actually achieved. So 35% is the
optimistic end of the assumption, not a safe one. At 8,000 cells/mm2 the logic alone wants
14.9 mm2 and there is no chip at all. That belongs to the schedule-viability question.

### Where the area is

Hierarchical, so these sum to 4.72 mm2 rather than 3.42, and should be read as proportions.

| block | um2 | % |
| --- | ---: | ---: |
| udma_subsystem | 1,421,260 | 30.1 |
| soc_interconnect_wrap | 1,040,079 | 22.0 |
| fc_subsystem (CV32E40P) | 790,770 | 16.8 |
| apb_i2cs | 533,232 | 11.3 |
| soc_event_generator | 276,898 | 5.9 |
| apb_adv_timer | 220,126 | 4.7 |
| apb_soc_ctrl | 110,243 | 2.3 |
| debug module | 109,655 | 2.3 |
| apb_gpiov2 | 61,239 | 1.3 |
| periph_bus_wrap | 57,411 | 1.2 |
| apb_timer_unit | 44,624 | 0.9 |
| dmi_jtag | 40,420 | 0.9 |
| pad_control | 8,206 | 0.2 |
| l2_ram_multi_bank | 799 | 0.0 |
| efpga_subsystem (stub) | 75 | 0.0 |

The uDMA breakdown ticket 12 asked for:

| instance | um2 | % of uDMA |
| --- | ---: | ---: |
| i_udmacore | 310,287 | 21.8 |
| i_filter_gen[0] | 281,466 | 19.8 |
| i_spim_gen[1] | 224,108 | 15.8 |
| i_spim_gen[0] | 224,014 | 15.8 |
| i_sdio_gen[0] | 119,865 | 8.4 |
| i_cam_gen[0] | 79,907 | 5.6 |
| i_uart_gen[0] | 45,970 | 3.2 |
| i_uart_gen[1] | 45,952 | 3.2 |
| i_i2c_gen[1] | 44,760 | 3.1 |
| i_i2c_gen[0] | 44,760 | 3.1 |

The uDMA is the biggest block in the SoC and only 6.4% of it is the two UARTs that the
destination's "boots and prints over UART" actually needs. `i_filter_gen[0]` alone, a
peripheral nothing in the destination uses, is 281,466 um2, which is six times both UARTs
together and 8.2% of the whole flattened design.

### The two things ticket 03 asked to watch

**The eFPGA tie-off folds, but only when flattened.** In the flat netlist
`gen_l2_demux[5]` through `[8]`, the four eFPGA TCDM master ports, contain zero cells; ports
0 to 4 survive. Hierarchically each of the four costs 18,378 um2 of demux, 3,504 of bridge
and 12,478 of address decoder, and the three crossbars carry nine masters instead of five.
That is most of the 1.30 mm2 gap between the two passes. **This is a flow-configuration
requirement, not a free win**: LibreLane has to flatten across the interconnect boundary or
the design pays for ports that never request. Noted in `flow/README.md`.

**`apb_i2cs` is worse than predicted.** 533,232 um2, 11.3% of the design, and 97.6% of that
is `i2c_peripheral_registers_i0`. The two `RAM_256x8_behavioral` instances are 243,217 um2
each. The ticket expected roughly 2,048 flip-flops; it is 4,096 memory bits, 2,048 per FIFO,
and they synthesise to 2,048 `$_DFFE_PP_` each plus the read multiplexing. For scale, this
one peripheral's two FIFOs cost more area than the CV32E40P's entire pipeline outside the
register file. It is the cheapest large cut available to ticket 12.

### Critical path

Pre-layout STA is not a frequency measurement here and `sta.sh` does not present it as one.
The netlist is unplaced and unbuffered, and the flow has built neither a clock tree nor a
reset tree: `apb2per_newdebug_i.clk_i` has **10,130** loads and `soc_peripherals_i.apb_reset`
has **4,841**, driven by a single minimum-drive inverter. Raw worst slack is -1,080 ns and
means nothing. Twenty-two nets are above 500 fanout.

Excluding those and reading the path as logic depth instead:

| corner | stages | median stage | floor | ceiling | of a 40 ns budget |
| --- | ---: | ---: | ---: | ---: | ---: |
| ss_125C_4v50 (5.0 V) | 35 | 0.568 ns | 19.9 ns | 50.3 MHz | 50% |
| ss_125C_3v00 (3.3 V) | 35 | 0.832 ns | 29.1 ns | 34.3 MHz | 73% |

**25 MHz survives on logic depth at both voltages**, which is the answer ticket 05 wanted,
but the margins are very different and that is a real input to ticket 14: 3.3 V spends 73% of
the budget before a single wire, a clock tree or any hold fixing exists. The path starts in
the AXI crossbar, at
`i_soc_interconnect_wrap.i_soc_interconnect.i_axi_xbar.i_xbar.gen_mst_port_mux[0].i_axi_mux.gen_mux.i_aw_spill_reg`,
so the interconnect is both the second-largest block and the source of the critical path.
That opened ticket 17.

**Superseded by ticket 22: this conclusion does not hold.** The 35-stage path above is the
single worst-slack path from a `report_checks -group_path_count 1` query, and ticket 19 later
found that metric picks by raw arrival, not by depth, so it is not the deepest path and it
moves identity under unrelated churn. Ticket 22 fixed the metric (search the 300 worst-slack
candidates for the deepest, not just #1) and re-measured on the current netlist: 89 stages,
62.3 ns, **125% of the 50 ns budget** at 3.3 V. "25 MHz survives on logic depth" was never
true; read ticket 22's Answer for the real number.

### Basilisk

Read as instructed, and it turns out mostly already banked. The 1.6x area and 2.3x timing
improvement in arXiv:2505.10060 comes from the combination of the yosys-slang front end with
flow tuning, and ticket 03 already took the yosys-slang half. What is left is not a third off
the gate count: the named techniques are an optimisation mapping aligned shift operations to
multiplexers, and a high-effort ABC script built by "lazy man's synthesis". The paper does
not publish either script, and Yosys 0.67 in the container is well downstream of the work.
Worth an afternoon at some point, but it is not the lever that closes a 6.6 mm2 gap. Cutting
the uDMA, `apb_i2cs` and the interconnect is.

### Left undone

The 3.3 V standard cell library `gf180mcu_as_sc_mcu7t3v3` exists in the pinned PDK, alongside
`gf180mcu_osu_sc_gp9t3v3` and `gf180mcu_osu_sc_gp12t3v3`. Everything here is measured against
`gf180mcu_fd_sc_mcu7t5v0` only. If ticket 14 chooses 3.3 V, a different cell library is on
the table and this measurement has to be repeated against it, which is one `make area` with
`SCL=` overridden.

### What was committed

- `flow/synth/filelist.sh`, the fusesoc file-list generation, factored out of `elaborate.sh`
  so both entry points share one definition. `make elaborate` is unchanged.
- `flow/synth/area.sh` and `make area`. Two passes, `MODE=hier|flat|both|report`.
- `flow/synth/area_report.py`, which reads per-module areas out of the stat log by instance
  path. `--keep-hierarchy` uniquifies module names, so a subtree is a prefix match.
- `flow/synth/sta.sh` and `make sta`, plus `path_summary.py`, `strip_params.py` and
  `blackbox.lib`. The last three exist because OpenSTA cannot link a netlist whose black
  boxes carry parameters or lack timing models.
- `run.sh` now forwards `TOP`, `MODE`, `LIB_CORNER` and `CLOCK_PERIOD_NS` into the container,
  which it silently did not before.

Two flow fixes fell out. `dfflibmap` maps flip-flops only, so the four latches upstream
infers in `apb_soc_ctrl` (`r_bootsel[1:0]`, `reset_reason[1:0]`) survived as behavioural
`always` blocks that OpenSTA rejects; the PDK's own
`libs.tech/librelane/$SCL/latch_map.v` fixes it and LibreLane will need the same. And a
`stat` log holds two hierarchy roll-ups, one before technology mapping and one after, 17%
apart; the report takes the last.
