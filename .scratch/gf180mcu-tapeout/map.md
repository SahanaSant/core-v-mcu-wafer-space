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

Standing preferences for this effort:

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
  before spending time on it. Note also that `pdk/` carries `gf180mcuA` through `gf180mcuD`
  as symlinks into a single ciel version, so a mistyped or copy-pasted variant name resolves
  to a real populated directory rather than failing. Anything that takes a variant name
  should assert it is `gf180mcuD`.
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

- **The remaining technology cells.** Ticket 03 replaced the guess with a measured list and
  ticket 16 took the clock cells out of it. Four files are left, and each is waiting on a
  decision rather than on sharpness: `gf180_interleaved_ram.sv` and `gf180_private_ram.sv`
  from ticket 11, `gf180_bootrom.sv` from ticket 04, and `gf180_clk_gen.sv` from ticket 05,
  which provides `apb_pll` in its entirety rather than a PLL cell inside it. Pad wrappers
  have left this patch: nothing in the SoC instantiates a pad cell, so `gf180_pads.sv` is
  `chip_top` work and graduates with the floorplan.
- **Software and the boot image.** Whether `sw/` exists at all, what it contains, and how it
  is built and loaded. Graduates from ticket 04.
- **Floorplan, PDN and macro placement.** Sixteen to thirty-two SRAM macros will not place
  themselves, and `macro_placement.cfg` has to be written explicitly with routing channels
  between rows. Graduates from ticket 11.
- **Timing closure.** Ticket 10 answered the first two thirds: 25 MHz holds on logic depth at
  both voltages, and the critical path lands in the AXI crossbar, which is now ticket 17.
  What is left is genuinely not sharp yet, because it cannot be asked before there is a
  floorplan: how much hold fixing the flow needs, what the clock tree costs once one exists
  for the 10,130-load clock net, and whether wire RC eats the 50% margin at 5.0 V or the 27%
  at 3.3 V. Graduates from the first full harden.
- **Gate-level simulation harness.** The four tests in `sim/README.md` are the shape of it,
  but the harness cannot be written before the netlist exists. Graduates from the
  technology-cell work.
- **DRC, LVS and antenna.** In particular the `MAGIC_GDS_FLATGLOB` patterns each new macro
  needs, which are discovered by running into false errors. Graduates from a first full
  harden.
- **Marker cells and submission packaging.** The five `gf180mcu_ws_ip__*` cells, each present
  exactly once. Late, and mechanical once the floorplan is fixed.
- **Schedule viability.** Whether Run 3 in December is actually reachable, and what the
  fallback is if it is not. Still waiting on ticket 11, but ticket 10 sharpened the stakes:
  the logic wants 9.76 mm² of a 12.92 mm² core at the template's 35% density, and that
  density is the optimistic end of what Run 1 achieved. At 8,000 cells/mm² instead of the
  measured 12,190 the logic alone wants 14.9 mm² and there is no chip. So this patch is now
  about how much has to be cut and whether cutting it is a December-sized job, not about
  whether anything needs cutting at all.

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
