# Map: CORE-V MCU on GF180MCU via wafer.space

## Destination

A GDS of `chip_top` that passes `gf180mcu-precheck` for a 1x1 slot, with gate-level
simulation showing the hardened netlist boots and prints over UART. Aimed at wafer.space
Run 3, December 2026.

## Notes

Domain: open-source ASIC physical design. RTL is SystemVerilog (upstream CORE-V MCU,
descended from PULPissimo); the flow is LibreLane driving Yosys, OpenROAD, Magic, Netgen
and KLayout, all inside IIC-OSIC-TOOLS with a separately pinned `gf180mcuD` PDK.

This map **carries execution**, not just decisions. Hardware sign-off is a change made in
place: the destination is an artifact, and a ticket that stops at "we decided to write the
SRAM wrapper" has not moved the map. Tickets resolve when the thing works and is measured.

Background reading, in order of usefulness: `docs/porting-analysis.md` is the full research
report and the source of every number quoted in these tickets. `rtl/gf180mcu/README.md` has
the technology-cell replacement map, the SRAM pin mapping and the area budget.
`rtl/chip/README.md` has the pad arithmetic. `flow/README.md` has the LibreLane settings
that matter and why.

`make elaborate` exists as of ticket 03 and takes under ten seconds. It reads the whole SoC
through yosys-slang and prints every module the design instantiates but does not define. Any
ticket that changes RTL should end by running it, and any ticket that wonders what is left to
write should start by running it.

`make area` and `make sta` exist as of ticket 10 and take about ten and two minutes. The
first synthesises to standard cells twice, flattened and hierarchical, and writes
`flow/build/area/area.md`: totals, kGE, placed area, macro area from LEF, the occupancy
arithmetic and a per-module breakdown by instance path. Any ticket that removes or
reconfigures RTL should quote the new flattened total rather than describing what it expects
to have saved.

**`make sta`'s headline is trustworthy again as of ticket 22, and it is bad news.** Ticket 19
found that a plain `report_checks -group_path_count 1` reports the path with the worst
pre-layout slack, which pre-layout is set by unbuffered fanout rather than depth, so it moved
identity under changes to unrelated blocks: the same netlist reported 35 stages in one
measurement and a 90-stage CV32E40P path in the next. Ticket 22 fixed it: `sta.sh` now searches
the 300 worst-slack candidates for whichever is actually deepest and reports its rank, so an
unstable winner is visible rather than hidden. Re-measured on the current netlist: **89
stages, 62.3 ns, 125% of the 50 ns / 20 MHz budget at 3.3 V**, and a tighter `abc -D` synthesis
target changes nothing (byte-identical netlist), so this is not slack left on the table by
synthesis. Quote this number; it is not provisional the way the old one was.

As of ticket 14 both default to the **3.3 V** signoff corner `ss_125C_3v00` and a **50 ns**
clock, so what they measure is the chip that is actually being built. `sta.sh` still reports
5.0 V as a second arm, because that margin is what the design gave up to reach the denser
SRAM and it should stay visible. Note that arm is hardcoded to two corners, so `make sta` only
works against a library carrying both; ticket 15 measured `gf180mcu_as_sc_mcu7t3v3` on area
alone for that reason. Since ticket 19 the 5.0 V arm is also **mixed-corner**: the OCD SRAM has
no `ss_125C_4v50`, which is what ticket 14 settled the supply on, so that arm runs standard cells
at 4v50 against SRAM arcs from 3v00 and prints a note saying so.

Ticket 16 attached two conditions to `make area`. **Its flattened total is good to roughly
0.3% and no better**: adding the clock cells cost a measured 3,776 um2 and moved the flattened
total 8,741 um2 the *other* way, because removing 70 hierarchy boundaries made ABC remap the
whole design. Quote the new total, as this map already requires, but do not read a sub-1%
delta as a saving. And the **`SCL=` override no longer works for other standard-cell
libraries**, because `gf180_clk_gate.sv` names cells from `gf180mcu_fd_sc_mcu7t5v0`. Nothing
needs it: `gf180mcu_as_sc_mcu7t3v3` is dead on measurement.

`make pdk` builds the PDK from source as of ticket 15 and takes about ten minutes per attempt,
plus two to clone. It is not reliable in one pass: magic segfaults intermittently on the
efabless pad cell, so the build retries up to four times and a cold run can take half an hour.
Budget an hour and keep it off the critical path of anything time-boxed. Both `make area` and
`make sta` take an `SCL=` override, and `flow/synth/latch_map/` holds a map for any library the
PDK does not ship one for.

Ticket 11 committed the memory, ticket 19 built it, and one standing trap sits behind them. The
configuration is **16 KiB of L2: sixteen `gf180mcu_ocd_ip_sram__sram1024x8m8wm1`, two interleaved
channels of 4 KiB plus two private banks of 4 KiB, contiguous from `0x1C00_0000` to
`0x1C00_4000`**, and it is in the RTL as of ticket 19: `rtl/gf180mcu/gf180_l2_ram.sv` plus four
patched upstream files on the submodule's local `master`. The trap
is that **nothing in `gf180mcu_ocd_ip_sram` was characterised**: every Liberty file is a foundry
Liberty file with the header swapped and the address bus resized, so its timing, power and
`area` all describe a different macro. Take macro area from LEF `SIZE`, never from Liberty, where
the error runs to 3.2x. Never conclude that an OCD macro matches a foundry one on timing, because
that compares a file with itself. And the `sram1024x8` Verilog specify block, the one piece of
3.3 V data that exists, is 2x optimistic on access time. Ticket 20 owns all of it. Ticket 19 built
the defences: `area_report.py` reads LEF geometry, and `stat -liberty` is handed the standard-cell
library alone so the macros contribute no area at all rather than the wrong area. Both are
load-bearing, and neither warns if a later change undoes it.

Standing preferences for this effort:

- **The supply is 3.3 V, single rail, until ticket 18 says otherwise.** Set by ticket 14. The
  `5v0` in `gf180mcu_fd_sc_mcu7t5v0` is the oxide, not the supply, and the library is fully
  characterised at 3.3 V, so this is a corner override and never a library change. Four
  LibreLane settings have to move together (`VDD_PIN_VOLTAGE`, `CELL_LIBS`, `STA_CORNERS`,
  `DEFAULT_CORNER`) and nothing warns you if one is missed. Anything that reasons about pad
  supplies should know that the foundry pads short the core and IO domains on purpose.
- Measure before committing. Ticket 10 did this for logic area and the estimate it replaced
  was 1.66x optimistic, so treat every remaining derived number in
  `docs/porting-analysis.md` as unverified until something measures it. `make area` and
  `make sta` are one command each and take about twelve minutes together; run them after any
  RTL or configuration change rather than reasoning about what the change should have done.
- Seed from the [wafer.space project template](https://github.com/wafer-space/gf180mcu-project-template)
  and diff, rather than writing flow configuration from first principles. Its defaults encode
  Run 1 and Run 2 experience.
- Keep PDK cell instantiation confined to `rtl/gf180mcu/`, in upstream's style, so the
  technology cells stay contributable.
- **Variant purity.** Everything must be drawn and verified against `gf180mcuD`
  specifically. Variants cannot be mixed in one tapeout, and C and D differ in top-metal
  thickness (roughly 0.99 µm against 1.19 µm) and therefore in DRC rules, so a cell verified
  under C's deck is not automatically clean under D's. This killed ticket 08 and it is the
  open question hanging over ticket 07's macros. Check the variant of any third-party IP
  before spending time on it. As of ticket 15 the mistyped-variant hazard is **gone**: the PDK
  is built for `gf180mcuD` alone, so `pdk/` holds one symlink and a wrong variant name fails
  instead of resolving to a real populated directory. Keep asserting `gf180mcuD` anyway, the way
  `area.sh`, `sta.sh` and `flow/pdk/build.sh` do, because the assertion is what keeps that true.
- Sign-off means a clean precheck. LibreLane finishing is not sign-off.
- **Nothing is published.** Established by ticket 02: no commit, branch, fork or repo from
  this effort is pushed to a public remote. The dev publishes when they choose. Work is kept
  by committing locally, in this repo and on the submodule's local `master`.

Dated signal: **re-check after 13 September 2026** for ORConf 2026 in Ghent, where the
`gf180mcu_ocd_ip_sram` silicon characterisation is presented (Edwards, "Finally Testing
Silicon Again: Chipalooza and Wafer.Space!") along with a wafer.space shuttle retrospective
(Moser). Ticket 07 established that those macros are 2.6x denser than the foundry part but
that their published timing is simulation-derived, so this talk is what turns a planning
number into a signoff number. It lands three months before the Run 3 deadline.

Settled without a ticket: the slot is `1x1`, because it is the largest wafer.space offers
and the design does not fit in anything smaller. The PDK variant is `gf180mcuD`, because
that is what wafer.space fabricates. The FPU and Xpulp extensions are already disabled in
upstream's `fc_subsystem.sv` and stay that way.

Upstreaming the portable technology cells to OpenHW is in scope but sits past the
destination, so ticket 13 is held until the GDS is signed off. December comes first. Ticket 02
added two hard preconditions to it that do not exist yet: a fork to open the PR from, and a
signed ECA covering the commit author.

## Decisions so far

<!-- one line per resolved ticket -->

- [01 Verify the toolchain container and the pinned PDK](issues/01-verify-toolchain-and-pdk.md)
  — Both work. All seven tools report versions inside `make shell` under rootless Podman, and
  `make pdk` places open_pdks `f6eeac7d` correctly, so the toolchain is no longer an unknown.
  Two findings beyond the check itself. Ticket 14's premise is **confirmed and wider than
  claimed**: `gf180mcu_fd_sc_mcu7t5v0` ships fifteen real corners across 5.0 V, 3.3 V and
  1.8 V, and the foundry SRAM tracks all three, though the PDK's LibreLane config defaults to
  5 V only so 3.3 V is a flow-config override. And `gf180mcu_ocd_ip_sram` is **not in the
  pinned PDK at all**, only referenced by it, so acting on ticket 07 costs a from-source
  `ciel build`. That opened ticket 15.
- [02 Fork upstream and re-point the submodule](issues/02-fork-and-repoint-submodule.md)
  — **No fork.** Port commits live on the submodule's local `master`, unpushed, and
  `.gitmodules` stays pointed at upstream unchanged. The DoD's "a fresh recursive clone
  builds" is knowingly **not** met: the parent records a submodule commit that exists on one
  disk, and the parent has no remote either. `submodule.core-v-mcu.update = merge` is set
  locally so a stray `git submodule update` cannot detach HEAD and orphan the port commits.
  The ECA is deferred until the work goes public; when it does, the commit author email
  `yusefkarim@riseup.net` must be on the Eclipse account or ticket 13's PRs bounce.
- [03 Get upstream RTL through a SystemVerilog front end](issues/03-sv-front-end.md)
  — **yosys-slang, first try.** The schedule risk this map was most afraid of is gone: the
  full SoC elaborates in about two seconds with one upstream source patch of one line, and
  `make elaborate` reproduces it. The eFPGA is removed by name collision rather than by
  patching upstream, its APB slot at `0x1A30_0000` staying decoded and reading zeros. The
  definitive missing-module list is ten modules: six clock cells across three naming families
  (70 instances, now ticket 16), the two L2 memories, the boot ROM, and `apb_pll`, which
  turns out to be the entire clock generator rather than a cell inside one. **No pad
  wrappers** appear at all, so pads are purely a `chip_top` concern. Ticket 09's exclusion
  list proved unnecessary and its `DISABLE_EFPGA` define does not exist upstream.
- [07 Is gf180mcu_ocd_ip_sram a denser alternative?](issues/07-ocd-sram-characterisation.md)
  — Yes, roughly 2.6x. The OCD `sram1024x8m8wm1` measures 0.155 mm²/KiB against the foundry
  macro's 0.409, which makes 32 KiB of L2 reachable at 39% of core area where it previously
  did not fit at all. Silicon from Run 1 is functional, but the Liberty data predates the
  wafers and is simulation-derived, with characterisation due at ORConf on 11 to 13 September
  2026. The macros have no 5.0 V corner, which opened ticket 14.
- [08 Can c4m-arrakeen-memgen generate a usable SRAM macro?](issues/08-memgen-viability.md)
  — No, and not before December. It emits no Liberty file anywhere in its stack, and it
  hardcodes `gf180mcuC` with no `gf180mcuD` code path at all, which is a DRC-relevant
  mismatch since the two variants differ in top-metal thickness. Either disqualifier alone
  is sufficient. The hands-on half is cancelled rather than deferred.
- [10 Measure the real logic area](issues/10-synthesis-area-baseline.md)
  — **311 kGE, and it does not fit.** The gate count was close to the estimate's 200 to 300
  kGE, but the estimate's NAND2 was wrong by 1.66x, so placed area is 9.76 mm² rather than 3
  to 5, and what is left for SRAM is **3.16 mm², not 7 to 9**. That is 7.7 KiB of foundry
  macro against a 16 KiB target, so ticket 07's OCD macro is now load-bearing for ticket 11
  rather than an optimisation. `make area` and `make sta` reproduce it. The area leaders are
  the uDMA at 30.1%, the interconnect at 22.0%, the core at 16.8% and **`apb_i2cs` at 11.3%**,
  the last being two behavioural FIFOs synthesised to 4,096 flops. The eFPGA tie-off does fold
  away, but **only when the flow flattens**, which is now a flow requirement rather than a
  free win. On timing, 25 MHz holds on logic depth at both voltages (35 stages, 19.9 ns at
  5.0 V and 29.1 ns at 3.3 V) but nothing else: the clock net has 10,130 loads and the reset
  net 4,841, with no trees built. The critical path starts in the AXI crossbar, which opened
  ticket 17.
- [14 Core supply voltage: 3.3 V or 5.0 V?](issues/14-core-supply-voltage.md)
  — **3.3 V core, and it costs nothing.** The premise that this was a library change was
  wrong: `gf180mcu_fd_sc_mcu7t5v0` carries all 229 cells at all fifteen corners with identical
  geometry (`nand2_1` is 10.976 um2 at `ss_125C_3v00` exactly as at `ss_125C_4v50`), so the
  `5v0` is the oxide and ticket 10's area baseline is supply-independent. 3.3 V keeps both SRAM
  families live where 5.0 V would have removed the OCD macro permanently, and the price is
  logic depth alone, 29.1 ns against 19.9. Re-measured at the new defaults, `make area` returns
  118,998 cells and 3,416,649 um2 identical to the cell, so the zero-area claim is measured
  rather than argued. The clock budget moves to 50 ns for 20 MHz, which puts 3.3 V at 58% of
  budget against 5.0 V's 40%, and ticket 05 owns the final number. 1.8 V is dead on
  measurement, not omission: the foundry SRAM needs 56.57 ns at `ss_125C_1v62`. **The IO ring
  did not resolve**, and the reason is a finding: the foundry pads short the core and IO
  domains deliberately, `gf180mcu_fd_io` having no core-supply pad cell at all, and the pads
  are 5 V capable but not 5 V tolerant, since every output PMOS has its bulk on DVDD. So 3.3 V
  single supply is the buildable baseline and a separated 5.0 V ring needs `gf180mcu_ocd_io`,
  which is unbuilt. That opened ticket 18 and widened ticket 15 from one library to three.
- [15 Build the pinned PDK from source with the optional libraries enabled](issues/15-pdk-rebuild-optional-libraries.md)
  — **All three built, variant-pure, but not with `ciel build`.** `make pdk` is now
  `flow/pdk/build.sh` driving open_pdks directly, because the flag that matters
  (`--with-gf180mcu-variants=D`) is one ciel hardcodes. Four defects sat in the way, each quiet
  on its own: `-l` is a whitelist so the ticket's own command would have emitted a PDK with **no
  foundry standard cells**; the image's `/headless/.magicrc` dereferences a `PDK_ROOT` that
  open_pdks deliberately unexports, killing every magic call; magic 8.3.678 segfaults
  **intermittently** on the efabless pad cell where the commit expects 8.3.674, so the build
  retries and the successful one took three attempts; and `run.sh` does not forward
  `PDK_COMMIT`. Building D alone also retires the map's mistyped-variant hazard, since A, B and
  C no longer exist as symlinks. The foundry libraries reproduce the prebuilt distribution
  file-for-file and `make area` still returns 118,998 cells and 3,416,649 um2. **The 3.3 V-native
  library is dead on measurement**: `gf180mcu_as_sc_mcu7t3v3` is 5.8% *larger* (3,614,711 um2),
  having no `_1` drive of anything, so do not switch. Ticket 11 gains four OCD SRAM sizes rather
  than one, plus an equal-capacity rebuild of the foundry 512x8 to check the 2.6x claim against.
  Ticket 18 gains its answer: `gf180mcu_ocd_io__vdd` bonds the core rail with DVDD and DVSS
  explicitly unconnected, against a foundry `dvdd` pad with no VDD port at all, and the library
  is characterised at 5.0 V as well as 3.3 V.
- [16 Write the GF180MCU clock cells](issues/16-clock-cells.md)
  — **Written and measured: 70 instances, three cells, `rtl/gf180mcu/gf180_clk_gate.sv`.**
  `icgtp_1` is a bit-exact match to upstream's own behavioural ICG, down to `E|TE` being ORed
  before the latch, and `TE` is a real pin so no test enable is ORed in RTL. `clkinv_1` for
  both inverter families. **There is no glitch-free clock mux and the design does not want
  one**: all eight instances select between phase variants of a single clock (SPI CPHA and
  CPOL, JTAG TCK, uDMA divider bypass), upstream's own implementations are the plain ternary,
  and break-before-make cannot be built behind a port list with no reset without patching every
  instantiation site and propagating X into the clock. All three cells are instantiated rather
  than inferred, which is what upstream's `tech_cells_generic` README instructs. One flow
  change makes that legal: `read_liberty -lib` before the RTL, since yosys-slang can only
  black-box a module some earlier yosys command loaded, now shared from `filelist.sh`; the
  price is that **`make area SCL=<other>` no longer resolves**. Cost is 3,776 um2, which the
  hierarchical pass returns exactly. The flattened pass came out 8,741 um2 *lower*, almost all
  ABC remapping, which sets a **precision floor of roughly 0.3% on `make area`** that every
  later ticket has to respect. Gate-level simulation is now pinned to a UDP-capable simulator:
  the ICG model is built on a Verilog primitive, so Verilator is out and the container's
  Icarus 14.0 is in.
- [11 Memory architecture: how much L2, in how many banks, from which macro?](issues/11-memory-architecture.md)
  — **16 KiB, sixteen OCD `sram1024x8` macros, two interleaved channels of 4 KiB plus two private
  banks of 4 KiB, contiguous from `0x1C00_0000`.** 2.49 mm2 of macro, about 2.79 mm2 of array. The
  private banks survive because the crossbar carrying them also carries the boot ROM, so dropping
  them would delete two of four ports on a structure that has to stay; the lever is
  `NB_L2_CHANNELS`, 4 to 2, not the macro size. Shrinking to `512x8` is a trap: 25% worse density
  cancels the saving and you get 12 KiB in the same floorplan. **Ticket 12's `apb_i2cs` cut is now
  a precondition**, since logic plus array is 97% of core without it and 89% with. The density
  claim is measured from LEF and the layout is real, foundry-reviewed and DRC clean under
  `gf180mcuD`. **The timing claim has nothing behind it**: every OCD Liberty is a foundry Liberty
  with the header swapped, the repo's own first commit says "timing has not been updated", and the
  one 3.3 V recharacterisation, in the `sram1024x8` specify block, is **2x optimistic** because the
  spec CSV row it read has column 1 overwritten by column 5. That opened ticket 20; ticket 21
  graduates the floorplan; ticket 19 writes the wrappers. Also settled: `L2_BANK_SIZE = 29184`
  becomes 1024 and agrees with `BANK_SIZE_INTL_SRAM`, and **there is no execute-in-place path**, so
  external flash never reduces the SRAM requirement.
- [19 Write the L2 SRAM wrappers and re-measure](issues/19-l2-sram-wrappers.md)
  — **Built, and it cost negative area, but `make sta` turned out to be measuring the wrong
  thing.** One file, `rtl/gf180mcu/gf180_l2_ram.sv`, binds both upstream names to one 1024 x 32
  body of four ganged macros; 1024 words is the macro's whole depth so there is no depth decoding
  and no output mux, and `ADDR_WIDTH` other than 10 is an elaboration error. Two black boxes left,
  `a2_bootrom` and `apb_pll`. The flattened netlist fell from 118,290 cells and 3,407,908 um2 to
  **114,244 and 3,349,208**, 1.7% and so well outside the 0.3% floor, but the saving is ticket
  11's parameters rather than the wrappers: `NB_L2_CHANNELS` 4 to 2 deletes two crossbar ports and
  `L2_BANK_SIZE` 29184 to 1024 narrows every uDMA address register from 15 bits to 10. Occupancy
  is **95.6%** against ticket 11's predicted 97%, so ticket 12 is still a precondition. `make
  area` now closes the whole budget itself, macro area from LEF `SIZE` because `stat -liberty`
  excludes the macros by construction. **The finding is timing**: `make sta` came back 84 stages
  and 135% of budget against ticket 10's 35 and 58%, so it was A/B'd. The baseline reproduces 35
  stages, but querying the baseline netlist directly returns a **90-stage path inside the
  CV32E40P** that lost the ranking by 13 ns of unbuffered fanout. `report_checks` ranks by
  pre-layout slack, not depth, so the headline was never logic depth and can move 2.4x on an
  unrelated change. That opened ticket 22.
- [09 What did lip6/core-v-180-mcu actually get working?](issues/09-lip6-prior-art.md)
  — Much less than advertised, and it corrects the research report: its CI has **zero
  recorded runs ever**, it builds only the bare CV32E40P with no memory or peripherals, and
  it has no LICENSE file so nothing may be reused. What transfers for free is the defines
  (`TOVERILOG`, `SYNTHESIS`, `DISABLE_EFPGA`) and a file-exclusion list, plus the useful fact
  that upstream RTL needed no source patches. The real find is **Basilisk**, a genuine
  tapeout through the Bender/Morty/SVase/sv2v chain, now required reading for ticket 03.
- [04 Boot architecture: how does the chip fetch its first instruction?](issues/04-boot-architecture.md)
  — **SPI-flash boot only, single-SPI, CRC32-checked, no ROM fallback, JTAG-only recovery.**
  Copy-then-jump via uDMA QSPI, never XIP: ticket 11 had already killed execute-in-place, and
  an XIP controller would be new hardware off this map. Upstream's bootsel-driven I2C fallback
  is dropped entirely, along with the `bootsel_i` pad, since the JTAG debug module
  (unconditionally present, independent of ROM cooperation) is now the sole recovery path on a
  CRC failure. Net pad cost for ticket 06 is **+3** (4 new QSPI pins, 1 freed), comfortably
  inside its 8-pad slack. ROM size is estimated, not yet measured, at **2 KiB**, for ticket 11's
  budget. `gf180_bootrom.sv` is a generated file, in `pad_control.sv`'s style; writing it,
  `sw/bootrom/`, and the generator script, and measuring the real area, is now ticket 23.
- [12 Which peripherals survive?](issues/12-peripheral-scope.md)
  — **Cut `apb_i2cs`, the uDMA filter and the uDMA camera; kept everything else, grilled
  against a game-console target.** PWM survives as the audio path (this config has no I2S at
  all), SDIO and a second SPI master survive for storage and sensors, GPIO is decided at 16 for
  a controller layout rather than upstream's 32. **Measured, not estimated**: flattened area
  fell from ticket 19's 114,244 cells / 3,349,208 um2 to **89,056 cells / 2,481,680 um2**
  (−25.9%), and core occupancy at 35% density fell from 95.6% to **76.4%**, 3.04 mm2 free
  against 0.57 mm2 — the biggest single move on the schedule-viability question of any ticket so
  far. Found and patched one latent upstream bug along the way: `udma_rx_channels.sv` /
  `udma_tx_channels.sv` part-select an "ext channel" slice that goes reversed-range-invalid
  rather than empty when `N_FILTER=0`, never hit before because no upstream configuration sets
  it to 0. Two decisions came out **unimplemented**: cutting the second uDMA I2C master
  (`N_I2CM` 2→1) and shrinking GPIO (`N_GPIO` 32→16) both turned out to require regenerating
  `pad_control.sv`'s literal-indexed mux table against a real `perdef.json`, which is ticket
  06's job, not this one's — handed over as decided inputs instead of implemented here.
- [06 Pad and IO budget: fit 57 signals into 56 pads](issues/06-pad-and-io-budget.md)
  — **39 of 40 general IO pins assigned, one spare.** `N_APBIO` drops to 24 (gpio 16 + pwm 8).
  Grilled live: PWM channels, a lever the ticket hadn't named, came out at 8 of 16 bonded, which
  forced UART to one instance and the second SPI master and SDIO to their narrowest useful mode
  (single-line, 1-bit) to fit the rest. `N_IO` 48→40, `N_GPIO` 32→16 and `N_I2CM` 2→1 (both
  ticket 12's, implemented here), `N_UART` 2→1 (new: a never-bonded second UART is silicon with
  no way to ever reach it). **Only some of the cuts save area**: `apb_adv_timer`, `udma_spim_top`
  and `udma_sdio_top` are all fixed-shape upstream IP with no channel-count parameter, so bonding
  fewer of their pins costs nothing; `N_UART` is a real generate-loop instance count, so it does.
  `bootsel_i` removed end to end (port, `REG_BOOTSEL`, the `dmactive_i` readback it was the only
  reader of). Elaboration surfaced two upstream bugs the resize exposed: `apb_gpio.sv`'s read
  path had a hardcoded `[31:0]` slice the write path already guarded against; `core_v_mcu.sv`'s
  eFPGA test-IO overlay had pad ranges hand-picked against `N_IO=48` and no real consumer left
  since the eFPGA is gone (ticket 03), so it's simplified rather than patched. **Measured**:
  flattened area fell from ticket 12's 89,056 cells / 2,481,680 um2 to **82,209 cells /
  2,281,302 um2** (−8.1%), core occupancy at 35% density fell from 76.4% to **72.0%**, 3.62 mm2
  free against 3.04 mm2 before. `safe_domain.sv` turned out not to be a generated file despite
  this map's own Notes and `rtl/chip/README.md` both saying so; corrected here, it's untouched.
- [22 `make sta` reports the wrong path, and the design is deeper than ticket 10 measured](issues/22-sta-reports-the-wrong-path.md)
  — **Fixed the metric, and the number it was hiding is real: 20 MHz does not close at 3.3 V.**
  `sta.sh` now asks OpenSTA for the 300 worst-slack candidates in one query and
  `path_summary.py` reports whichever is actually deepest, with its rank printed so an unstable
  winner stays visible (measured: the 5.0 V arm's deepest candidate ranked #39, not #1).
  Re-measured on ticket 06's netlist: **89 stages, a 62.3 ns floor, 125% of the 50 ns budget**
  at 3.3 V; the 5.0 V logic-only arm has real margin at 88%. The cheap experiment the ticket
  itself suggested, re-mapping at a 2.5x tighter `abc -D` target, produced a byte-identical
  netlist, so this is not slack synthesis left on the table. The floor already assumes zero
  wire RC, so real numbers only get worse from here, not better, until a first full harden
  exists. Ticket 10's "25 MHz survives on logic depth" is withdrawn. Options for ticket 05:
  a slower clock (defensibly below 16 MHz at 3.3 V), unproven retiming, or pipelining the
  CV32E40P decoder path, which would be new microarchitecture off this map.

- [05 Clock and reset architecture without a PLL](issues/05-clock-and-reset.md)
  — **External `ref_clk_i` bypass, undivided, at 10 MHz; `apb_pll` becomes an inert stub;
  `rstgen` reinstated for real async-assert/sync-deassert reset.** No PLL and no on-die
  oscillator: a self-clocked demo was investigated and rejected for this shuttle, since
  Mabrains' open ring-oscillator IP is fused into an unverified, possibly `gf180mcuC` analog
  macro rather than a standalone one, unscoped re-verification work left in the fog rather than
  pursued now. `gf180_clk_gen.sv` keeps `apb_pll`'s register offsets readable but functionally
  dead, matching `fpga_pll.sv`'s own precedent, and drops the five dangling analog supply ports.
  **10 MHz (100 ns)** is the target, roughly 60% margin over ticket 22's 62.3 ns idealized
  floor and a standard oscillator frequency now that a human has to wire one to the board; since
  the clock is external this is a synthesis/bring-up target, not a value burned into silicon.
  Reset synchronization **does not exist in the RTL today** — `safe_domain.sv` is a bare wire —
  so this reinstates upstream's own commented-out `rstgen` intent for real, one instance on the
  main clock covering both domains, no on-die debounce or POR (the pad library has no POR cell;
  an external supervisor is assumed). Writing `gf180_clk_gen.sv` and the reset wiring is new
  work, not a further decision, so it's spun off as ticket 24, the same shape as ticket 04
  spinning off ticket 23.

## Not yet specified

In scope, but not sharp enough to ticket. Each patch graduates when the ticket named as its
trigger resolves.

- **The remaining technology cells.** Ticket 03 replaced the guess with a measured list, ticket
  16 took the clock cells out of it, ticket 19 the two memories (landing as one
  `gf180_l2_ram.sv` rather than the two files the table expected), and ticket 04 the boot ROM's
  architecture. **Nothing here waits on a decision any more**: ticket 05 settled
  `gf180_clk_gen.sv` (external bypass, inert `apb_pll` stub, 10 MHz, reinstated `rstgen` reset),
  so both `gf180_clk_gen.sv` and `gf180_bootrom.sv` — the last two black boxes `make elaborate`
  reports — are waiting only on being built and measured, ticket 24 and ticket 23 respectively.
  Pad wrappers have left this patch: nothing in the SoC instantiates a pad cell, so
  `gf180_pads.sv` is `chip_top` work and graduates with the floorplan.
- **Timing closure.** Ticket 10 looked answered and was not: `make sta` ranked paths by
  pre-layout slack rather than depth, so "25 MHz holds on logic depth at both voltages"
  described a 35-stage path that was never the deepest. **Ticket 22 fixed the metric and
  re-measured**: 89 stages, 62.3 ns, 125% of the 50 ns budget at 3.3 V, and a tighter `abc -D`
  synthesis target changed nothing, so this is not slack synthesis left on the table. What
  stays in the fog is what still cannot be asked before there is a floorplan: how much hold
  fixing the flow needs, what the clock tree costs once one exists for the 10,122-load clock
  net, and how much of the (already negative) 3.3 V margin wire RC eats on top of the 25%
  shortfall ticket 22 measured. Graduates from the first full harden. Ticket 16 made one part
  concrete: the clock net has **54 real clock gates in it** rather than transparent black
  boxes, so they are 54 points CTS has to balance to rather than an abstraction. Ticket 19 made
  a second: the SRAM arcs are now real in `make sta`, 13.46 to 15.87 ns at `ss_125C_3v00`, but
  that is the foundry macro's timing under an OCD cell name, so it is a pessimistic placeholder
  ticket 20 has to justify or replace.
- **Hardening the macros.** `flow/config.yaml` does not exist, so nothing yet tells LibreLane
  the sixteen macros are there: `macros.yaml` pointing at their LEF, Liberty, GDS and SPICE, the
  `MAGIC_GDS_FLATGLOB` entries they will need, and `PDN_MACRO_HOOKS` for their Metal2/Metal3
  perimeter rings. Ticket 19 put the instances in the netlist and stopped at the flow boundary.
  Mostly ticket 21's, since placement and power routing are the same conversation.
- **Gate-level simulation harness.** The four tests in `sim/README.md` are the shape of it,
  but the harness cannot be written before the netlist exists. Graduates from the
  technology-cell work. Ticket 16 fixed the simulator: the PDK's `icgtp` model is built on a
  Verilog user-defined primitive, one of four in
  `libs.ref/gf180mcu_fd_sc_mcu7t5v0/verilog/primitives.v`, and carries a `specify` block with
  `$setup`/`$hold`/`$width` checks. **Verilator supports neither, so it is out.** The container
  ships Icarus Verilog 14.0, which handles both, and the harness will read
  `gf180mcu_fd_sc_mcu7t5v0.v` and `primitives.v` from the PDK rather than compiling the netlist
  standalone. Ticket 11 put a precondition on it: the SRAM model this harness will read,
  `gf180mcu_ocd_ip_sram__sram1024x8m8wm1.v`, has a specify block that is **2x optimistic on access
  time** at 3.3 V, so ticket 20 has to land first or the harness validates a chip that does not
  exist. Ticket 04 fixed the last unknown standing between the destination's "prints over UART"
  and this harness: boot is SPI-flash, copy-then-jump, CRC32-checked, so the hello-world image
  this harness boots is one more test image loaded exactly the way ticket 23's `sw/bootrom` loads
  any other, not a special case. Whether it needs its own `sw/app` directory or lives alongside
  the harness's other three tests is undecided and stays in this patch.
- **DRC, LVS and antenna.** In particular the `MAGIC_GDS_FLATGLOB` patterns each new macro
  needs, which are discovered by running into false errors. Graduates from a first full
  harden. Ticket 15 added one known input: `gf180mcu_ocd_io`'s LibreLane config sets
  `PAD_CDLS ""` where `gf180mcu_fd_io` inherits real CDL, so if ticket 18 picks the OCD pads
  the ring has no CDL netlist for LVS as shipped. The SPICE is a proper hierarchical netlist
  rather than a stub, so the data exists and the config is what needs pointing at it. How much
  work that is cannot be judged before there is a pad ring to run LVS on.
- **Marker cells and submission packaging.** The five `gf180mcu_ws_ip__*` cells, each present
  exactly once. Late, and mechanical once the floorplan is fixed.
- **Schedule viability.** Whether Run 3 in December is actually reachable, and what the
  fallback is if it is not. Ticket 10 set the stakes at 97% occupancy; ticket 19's parameter set
  brought that to 95.6%. **Ticket 12 changed the picture more than either did**: cutting
  `apb_i2cs`, the uDMA filter and camera (measured, not estimated) dropped occupancy to
  **76.4%**, 3.04 mm² free against 0.57 mm² before. The chip no longer looks area-critical, and
  the remaining question is no longer "does it fit" so much as whether it places cleanly at 35%
  density, which is still ticket 21's to answer, now with real margin behind it. What ticket 12
  did *not* touch is timing: **ticket 22 measured the design at 62.3 ns against the 50 ns
  budget at 3.3 V, 125%**, with a trustworthy metric behind the number this time and a ruled-out
  cheap fix (re-mapping at a tighter target changed nothing). That risk is untouched by area
  headroom and is now the more likely thing to take the December date away, pending ticket 05's
  clock decision and whatever a first full harden's real CTS numbers say.

## Out of scope

Ruled beyond the destination. These do not graduate; they would be a fresh effort.

- Post-silicon work: test board, bring-up firmware, characterisation, debug of returned dies.
- Submission mechanics: booking the slot, payment, packaging, and any wafer.space review
  loop after the GDS is handed over.
- The eFPGA. `quicklogic.com:ip:efpga` is not open, there is no GF180 implementation, and it
  is removed rather than ported.
- FPU and Xpulp support, already disabled upstream.
- Anything larger than one 1x1 slot: multi-die, reticle stitching, a second shuttle run.
- Publishing and hosting: a public fork, a remote for this repo, CI that clones it, and the
  ECA that goes with any of that. Ruled out by ticket 02. It follows that a fresh recursive
  clone cannot reproduce this checkout, and that no automation runs against the design.
