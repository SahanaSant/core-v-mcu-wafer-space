# Write the L2 SRAM wrappers and re-measure

Type: task
Status: resolved
Blocked by: none

## Question

Ticket 11 committed the configuration; this builds it. Nothing here is a decision.

Write `rtl/gf180mcu/gf180_interleaved_ram.sv` and `rtl/gf180mcu/gf180_private_ram.sv`, both
1024 words by 32 bits from four ganged `gf180mcu_ocd_ip_sram__sram1024x8m8wm1`. They are the
same module under two names, since ticket 11 sized both banks at 4 KiB, so write one body and
decide whether upstream's two module names justify two files or one file with two wrappers.

Apply the parameter set from ticket 11's answer:

| file | parameter | from | to |
| --- | --- | ---: | ---: |
| `rtl/includes/pulp_soc_defines.svh:32` | `NB_L2_CHANNELS` | 4 | 2 |
| `l2_ram_multi_bank.sv:23` | `BANK_SIZE_INTL_SRAM` | 32768 | 1024 |
| `l2_ram_multi_bank.sv:24` | `BANK_SIZE_PRI0` | 8192 | 1024 |
| `l2_ram_multi_bank.sv:25` | `BANK_SIZE_PRI1` | 8192 | 1024 |
| `soc_domain.sv:101` | `L2_BANK_SIZE` | 29184 | 1024 |

and the memory map, contiguous from `0x1C00_0000`: private bank 0 to `0x1C00_1000`, private
bank 1 to `0x1C00_2000`, interleaved TCDM to `0x1C00_4000`.

Points to get right rather than discover:

- **Pin mapping.** `CEN`, `GWEN` and `WEN[7:0]` are active low. The bus carries a 4-bit `be_i`,
  one bit per byte lane, and each macro is one byte lane, so macro `k` takes
  `WEN = {8{~be_i[k]}}`. Record the mapping in `rtl/gf180mcu/README.md` as the map's Notes
  require.
- **Instantiate, do not infer**, as ticket 16 established, which means `read_liberty -lib` on
  `gf180mcu_ocd_ip_sram` before `read_slang` in `filelist.sh` exactly as the clock cells needed.
  Without it yosys-slang stops on the unknown module.
- **Liberty `area` for these macros is wrong** by 1.35x, so if `area_report.py` starts counting
  macros, take their area from LEF `SIZE`. See ticket 20.
- Delete the matching stubs from `flow/synth/stubs.sv` as each wrapper lands.

## Definition of done

`make elaborate` reports two fewer black boxes. `make area` and `make sta` run to completion and
their new numbers are quoted, with the flattened total read against ticket 16's 0.3% precision
floor rather than as an exact delta. `rtl/gf180mcu/README.md` updated: the technology-cell table
loses both memory rows, `core_v_mcu_interleaved_ram` having gone from 4 instances to 2.

## Answer

**Built, measured, and it cost negative area. One file, `rtl/gf180mcu/gf180_l2_ram.sv`, sixteen
macros, 16 KiB.** `make elaborate` is down to two black boxes, `a2_bootrom` and `apb_pll`. The
flattened netlist went from 118,290 cells and 3,407,908 um2 to **114,244 and 3,349,208**, which
is 1.7% smaller and so a real saving rather than ABC noise against ticket 16's 0.3% floor.

The ticket said nothing here is a decision. That was true of the wrappers. It was not true of
what re-measuring found, which is that `make sta` has been reporting the wrong path since ticket
10. That is ticket 22 and it is the more important half of this resolution.

### The wrappers

One file, two upstream names, one body, following `gf180_clk_gate.sv`'s precedent rather than
splitting a module that differs only in its name. `gf180_l2_bank` is 1024 x 32 from four ganged
`gf180mcu_ocd_ip_sram__sram1024x8m8wm1`; `core_v_mcu_interleaved_ram` and
`core_v_mcu_private_ram` wrap it. 1024 words is the macro's whole depth, so there is **no depth
decoding and no output mux** and the address bus passes through unmodified.

The pin mapping in the question is correct, and the reason it works is worth stating because it
is not obvious from the Liberty. The macro's own simulation model gives
`write_flag = cen_fell & !CEN & !GWEN & !(&WEN)` and `read_flag = cen_fell & !CEN & GWEN`, so
driving a masked lane's whole `WEN` bus high fails the `!(&WEN)` term. A masked byte lane on a
write cycle therefore neither writes nor reads and holds `Q`, with no gating on `CEN` and nothing
added to the write path. TCDM ignores read data on a write, so holding is enough.

`ADDR_WIDTH` other than 10 is an elaboration error rather than a silent aliasing bug, via an
elaboration-time `$error` in a generate block. Verified by instantiating with 12 and watching
slang refuse it, not by inspection.

### The parameter set, and why it paid for itself

All five parameters applied as specified, plus the memory map, all committed on the submodule's
local `master` per ticket 02. Four upstream files: `pulp_soc_defines.svh`,
`l2_ram_multi_bank.sv`, `soc_domain.sv`, `soc_mem_map.svh`.

The 58,700 um2 the design lost is **not** the wrappers, which add nothing but wiring. It is the
parameters: `NB_L2_CHANNELS` 4 to 2 deletes two ports from the interleaved crossbar and two
banks of TCDM handshake, and `L2_BANK_SIZE` 29184 to 1024 takes `L2_MEM_ADDR_WIDTH` from 15 to
10, narrowing the uDMA address registers upstream's own comment says exist only to save area.
`soc_interconnect_wrap` is 994,026 um2 against ticket 10's 22.0% share, the uDMA 1,371,087
against 30.1%, and `l2_ram_multi_bank` is down to 474 um2 of handshake logic.

So the occupancy arithmetic improves, and not enough to matter:

| item | mm2 | % of core |
| --- | ---: | ---: |
| standard cells placed at 35% | 9.57 | 74.1 |
| 16 macros, from LEF | 2.49 | 19.2 |
| array, +12% channels | 2.79 | 21.6 |
| **occupied** | **12.35** | **95.6** |

Ticket 11 predicted 97% and got 95.6%. **Ticket 12's `apb_i2cs` cut is still a precondition**,
and whether the result places is still ticket 21's.

### `make area` now counts macros, from LEF

The ticket warned that Liberty `area` is wrong by 1.35x if `area_report.py` starts counting
macros. It does not count them by accident: yosys reports `Area for cell type
\gf180mcu_ocd_ip_sram__sram1024x8m8wm1 is unknown!` because `stat -liberty` is given the
standard-cell library alone. So the cell-area total stays standard cells and nothing else, and
`area_report.py` gained a separate macro section that reads `SIZE` out of the LEFs. The report
now closes the whole budget in one place instead of leaving the SRAM half to be done by hand.

`filelist.sh` reads the macro Liberty with `read_liberty -lib` before `read_slang`, exactly as
ticket 16 needed for the clock cells, and both callers now loop over a `$LIBS` list rather than a
single `$LIB`. `sta.sh` reads the real macro Liberty per corner, which replaces `blackbox.lib`'s
zero-delay model with the 13.46 to 15.87 ns the Liberty reports at `ss_125C_3v00`. Note that is
still the foundry 512x8's timing under an OCD cell name; ticket 20 owns it.

**The 5.0 V arm of `make sta` now runs on mixed corners and says so.** `gf180mcu_ocd_ip_sram` has
no `ss_125C_4v50` corner at all, which is precisely what ticket 14 settled the supply on, so the
informational arm runs standard cells at 4v50 against SRAM arcs from 3v00 and prints a note. That
arm exists for the logic comparison; there is no 5.0 V chip to measure, only a 5.0 V logic path.

### The finding: `make sta` reports the wrong path

`make sta` came back with **84 stages and 67.7 ns, 135% of budget**, against ticket 10's 35
stages and 29.1 ns. Nothing in this ticket touches the CV32E40P and the reported path does not
go near the SRAM, so rather than quote it, it got A/B'd: stash the change, re-measure the
untouched tree, restore.

The baseline reproduces **35 stages and 31.2 ns**, so the shift is real and not measurement
scatter. But querying the baseline netlist directly, `report_checks -to` the CV32E40P endpoint,
returns **90 stages at 270.5 ns** against the 283.9 ns of the crossbar path it chose to report.
The deep path was always there. It lost the ranking by 13 ns of unbuffered fanout.

That is the whole mechanism: `report_checks` ranks by slack, pre-layout slack is set by whichever
minimum-drive cell drives a big net, and in these paths three stages carry 146 ns of a 280 ns
arrival while 81 stages share the rest. Depth barely enters the ranking, and `path_summary.py`
then reports the depth of whatever path won. **So `make sta`'s headline has never been the
design's logic depth, and it can move 2.4x on a change that touches neither block involved.**

Ticket 10's "25 MHz holds on logic depth at both voltages" is the conclusion at risk. At about
0.8 ns a stage at 3.3 V, 90 stages is roughly 70 ns against a 50 ns budget. That opened
**ticket 22**, which owns both the metric and the re-derived timing conclusion. It should be
taken before ticket 05 picks a clock, and it is a candidate for the first thing that takes the
December date away, alongside ticket 21.

### Traps for the next session

- **`make sta`'s number is not logic depth.** Until ticket 22, do not plan against it and do not
  read a change in it as caused by whatever you just did.
- Macro Liberty `area` is the foundry macro's, 1.35x out on the 1024x8. `stat -liberty` excludes
  the macros by construction, which is load-bearing; if a future change hands it the SRAM
  library, the cell-area total silently gains 3.35 mm2 of fiction.
- `make area SCL=<other>` was already dead from ticket 16. `SRAM=` and `SRAM_MACRO=` overrides
  do work, since nothing in the RTL names a macro outside `gf180_l2_ram.sv`.
- Hardening is not wired up: `flow/config.yaml` still does not exist, so `macros.yaml`,
  `macro_placement.cfg` and the `MAGIC_GDS_FLATGLOB` entries these sixteen macros need are all
  ticket 21's, unstarted.
