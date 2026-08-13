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
`flow/build/area/area.md`: totals, kGE, placed area, the implied SRAM budget, and a
per-module breakdown by instance path. The second reports the critical path as logic depth
at both supply corners. Any ticket that removes or reconfigures RTL should quote the new
flattened total rather than describing what it expects to have saved.

As of ticket 14 both default to the **3.3 V** signoff corner `ss_125C_3v00` and a **50 ns**
clock, so what they measure is the chip that is actually being built. `sta.sh` still reports
5.0 V as a second arm, because that margin is what the design gave up to reach the denser
SRAM and it should stay visible. Note that arm is hardcoded to two corners, so `make sta` only
works against a library carrying both; ticket 15 measured `gf180mcu_as_sc_mcu7t3v3` on area
alone for that reason.

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

Ticket 11 committed the memory and left one standing trap behind it. The configuration is
**16 KiB of L2: sixteen `gf180mcu_ocd_ip_sram__sram1024x8m8wm1`, two interleaved channels of
4 KiB plus two private banks of 4 KiB, contiguous from `0x1C00_0000` to `0x1C00_4000`.** The trap
is that **nothing in `gf180mcu_ocd_ip_sram` was characterised**: every Liberty file is a foundry
Liberty file with the header swapped and the address bus resized, so its timing, power and
`area` all describe a different macro. Take macro area from LEF `SIZE`, never from Liberty, where
the error runs to 3.2x. Never conclude that an OCD macro matches a foundry one on timing, because
that compares a file with itself. And the `sram1024x8` Verilog specify block, the one piece of
3.3 V data that exists, is 2x optimistic on access time. Ticket 20 owns all of it.

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
- [09 What did lip6/core-v-180-mcu actually get working?](issues/09-lip6-prior-art.md)
  — Much less than advertised, and it corrects the research report: its CI has **zero
  recorded runs ever**, it builds only the bare CV32E40P with no memory or peripherals, and
  it has no LICENSE file so nothing may be reused. What transfers for free is the defines
  (`TOVERILOG`, `SYNTHESIS`, `DISABLE_EFPGA`) and a file-exclusion list, plus the useful fact
  that upstream RTL needed no source patches. The real find is **Basilisk**, a genuine
  tapeout through the Bender/Morty/SVase/sv2v chain, now required reading for ticket 03.

## Not yet specified

In scope, but not sharp enough to ticket. Each patch graduates when the ticket named as its
trigger resolves.

- **The remaining technology cells.** Ticket 03 replaced the guess with a measured list, ticket
  16 took the clock cells out of it, and ticket 11 specified the two memories, so
  `gf180_interleaved_ram.sv` and `gf180_private_ram.sv` are ticket 19 rather than fog. Two files
  are left, each waiting on a decision rather than on sharpness: `gf180_bootrom.sv` from ticket
  04, and `gf180_clk_gen.sv` from ticket 05, which provides `apb_pll` in its entirety rather than
  a PLL cell inside it. Pad wrappers have left this patch: nothing in the SoC instantiates a pad
  cell, so `gf180_pads.sv` is `chip_top` work and graduates with the floorplan.
- **Software and the boot image.** Whether `sw/` exists at all, what it contains, and how it
  is built and loaded. Graduates from ticket 04. Ticket 11 fixed the target it has to hit: 16 KiB
  contiguous from `0x1C00_0000`, **no execute-in-place path anywhere in the design**, and every
  upstream boot address (`0x1C00_8080`, `0x1C00_0880`, and the `0x1C07_C000` linker origin) now
  outside the memory that exists.
- **Timing closure.** Ticket 10 answered the first two thirds: 25 MHz holds on logic depth at
  both voltages, and the critical path lands in the AXI crossbar, which is now ticket 17.
  What is left is genuinely not sharp yet, because it cannot be asked before there is a
  floorplan: how much hold fixing the flow needs, what the clock tree costs once one exists
  for the 10,130-load clock net, and whether wire RC eats the 50% margin at 5.0 V or the 27%
  at 3.3 V. Graduates from the first full harden. Ticket 16 made the first of those concrete:
  the clock net now has **54 real clock gates in it** rather than transparent black boxes, so
  they are 54 points CTS has to balance to rather than an abstraction. Ticket 11 added a second:
  the SRAM access path is roughly 16 ns of the 50 ns budget at `ss_125C_3v00`, but that number is
  the foundry macro's, quoted for a macro nobody characterised, so it is a placeholder that
  ticket 20 has to either justify or replace.
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
  exist.
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
  fallback is if it is not. Ticket 10 set the stakes: the logic wants 9.76 mm² of a 12.92 mm²
  core at the template's 35% density, and that density is the optimistic end of what Run 1
  achieved. At 8,000 cells/mm² instead of the measured 12,190 the logic alone wants 14.9 mm² and
  there is no chip. Ticket 11 closed the memory half of it and left the arithmetic exact rather
  than open: logic plus a 2.79 mm² SRAM array is **97% of core**, and 89% once ticket 12 cuts
  `apb_i2cs`. So the remaining question is no longer how much has to be cut, it is whether 89% at
  35% density actually places, which is ticket 21's to answer and the first thing that could
  still take the December date away.

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
