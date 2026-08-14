# Write gf180_clk_gen.sv and wire the reset synchronizer

Type: task
Status: resolved
Blocked by: none

## Question

Ticket 05 decided the clock and reset architecture; this ticket builds it and measures the
result, the same shape as ticket 23 for the boot ROM.

Write `rtl/gf180mcu/gf180_clk_gen.sv`, replacing the `apb_pll` black box `make elaborate` still
reports. Per ticket 05's answer: keep the existing `apb_pll` APB register offsets
(`CTL`/`DIV`/`FRAC`/`SS1`/`SS2`/`SOC`/`PERIPH`/`CLUSTER`) readable and writable but functionally
inert, matching `emulation/xilinx/rtl/fpga_pll.sv`'s own precedent; wire `soc_clk_o`,
`periph_clk_o` and `cluster_clk_o` directly from `ref_clk_i`; keep `ref_clk_o`'s divide-by-40 via
the existing `clkdv` module, reused as-is; drop the five analog supply ports (`AVDD`, `AVDD2`,
`AVSS`, `VDDC`, `VSSC`) since nothing analog is instantiated.

Reinstate `safe_domain.sv`'s reset synchronization (currently `assign rst_no = rst_ni`, a bare
wire, no clock input at all). Add a clock input port and instantiate `rstgen` from
`rtl/vendor/pulp_platform_common_cells/src/rstgen.sv` (async assert, sync deassert), clocked by
the main SoC clock, producing the synchronized `rstn_glob_i`/`s_rstn_por` the rest of the SoC
already expects. One instance covers both the main clock domain and the `/40` slow domain.

Move the flow's `CLOCK_PERIOD` off its 50 ns placeholder (set by ticket 14, aimed at the old
20 MHz target) to the 100 ns / 10 MHz target ticket 05 settled on, in whatever LibreLane config
and `sta.sh`/`area.sh` defaults currently carry it.

## Definition of done

`make elaborate` no longer reports `apb_pll` as a black box. `make area` and `make sta` run clean
against the new module and the 100 ns clock period, and the flattened totals and stage count are
quoted, not estimated, per this map's standing "measure before committing" preference.

## Answer

**Built and measured: the design closes with real margin, and it is the budget that changed,
not the logic.**

`rtl/gf180mcu/gf180_clk_gen.sv` provides `apb_pll` for real. `soc_clk_o`, `periph_clk_o` and
`cluster_clk_o` are `ref_clk_i` wired straight through, no divider and no mux, per ticket 05's
bypass decision — which makes `ref_clk_i` the actual SoC clock rather than a stand-in for one
hidden behind a black box. The eight FLL registers (`CTL`/`DIV`/`FRAC`/`SS1`/`SS2`/`SOC`/
`PERIPH`/`CLUSTER`) stay APB-readable and -writable at `fpga_pll.sv`'s offsets, matching its
precedent exactly, but nothing they hold drives an output; the `PD`/`PDDP`/`MODE`/`DM`/`BYPASS`
decode that fed the ASIC version's `PLL18_TOP` hard macro is gone with it, since there is no
hardware left for those fields to configure. `LOCK` (bit 31 of `CTL`) reads back tied to 1, so
anything that polls "PLL locked" before proceeding never blocks — checked against the actual
software in this repo: neither `sw/bootrom` nor `a2_boot/main.c` reads it, only writes reset/
bypass bits, so this was a defensive choice rather than one fixing a live hang. `ref_clk_o`'s
divide-by-40 keeps `clkdv`, copied unmodified into this file the way both `apb_pll.sv` and
`fpga_pll.sv` each already carry their own copy. The five analog PLL supply ports (`AVDD`,
`AVDD2`, `AVSS`, `VDDC`, `VSSC`) are gone; `soc_peripherals.sv`'s instantiation drops the
connections to match, which were implicit wires going nowhere in the first place (ticket 05).

`safe_domain.sv` gained a `ref_clk_i` port (wired from `core_v_mcu.sv`'s own top-level port) and
a real `rstgen` instance (`rtl/vendor/pulp_platform_common_cells/src/rstgen.sv`, already
vendored, async assert / sync deassert), replacing an `assign rst_no = rst_ni` bare wire that
had stood unsynchronized since the file was written. That output fans out as `rstn_glob_i` into
several async resets inside `soc_domain` (`soc_peripherals`'s `rstpin_ni`, the debug module, the
JTAG DMI), so the raw pad-level deassert previously reached those flops with no recovery-time
guarantee. One `rstgen` instance covers both the main clock domain and the `/40` slow domain,
since a glitch-free deassertion on the fast clock stays glitch-free on the slow one too. No
test-mode bypass exists at this level, matching `core_v_mcu.sv`'s own `dft_test_mode_i` tied to
`'0`; no on-die debounce or power-on reset either, since `gf180mcu_fd_io`'s support-cell list has
no POR/brownout cell and an external supervisor is assumed (ticket 05).

`make elaborate` now reports **zero** black boxes — the last one, `apb_pll`, is gone.
`flow/synth/stubs.sv` no longer carries any stub module. `flow/synth/blackbox.lib` lost its
`apb_pll` cell entry, the last one doing real work; its already-dead `a2_bootrom` entry (an
oversight left over from ticket 23, which made the boot ROM real but never removed its
zero-delay model) came out in the same pass, since it was the same problem in the same file. The
library preamble and templates stay, ready for whatever the next black box turns out to be.

`CLOCK_PERIOD_NS` moved from 50 to 100 in `flow/synth/area.sh` and `flow/synth/sta.sh`, per
ticket 05's 10 MHz target. One thing found along the way: `run.sh` carries its own
`CLOCK_PERIOD_NS="${CLOCK_PERIOD_NS:-50}"` default and forwards it into the container
unconditionally, which shadows both scripts' own `${CLOCK_PERIOD_NS:-...}` fallback regardless
of what they default to — editing area.sh and sta.sh alone left the flow silently measuring
against 50 ns anyway on the first re-run. Fixed by moving `run.sh`'s default to 100 too. A couple
of comments describing `apb_pll` as a black box (`sta.sh`, `flow/synth/area_report.py`, which
writes directly into every generated `area.md`) were stale and are corrected.

**Measured**, both after the `run.sh` fix:

`make area`: **84,753 cells, 2,334,966 um2** (+1.55% over ticket 23's 83,101 / 2,299,430,
outside the 0.3% floor — the register file and `rstgen` are real cells now, not a zero-cost
black box), occupancy 72.4% to **73.2%**.

`make sta`, against the new 100 ns budget: **86 stages, a 77.4 ns floor, 77% of budget at 3.3 V**
(85 stages, 51.0 ns, 51% on the 5.0 V logic-only arm) — the first measurement to close with
margin instead of failing it. That is the budget catching up to what ticket 05 already settled,
not the logic getting faster: stage count and floor both moved again under this ticket's RTL
churn (83 to 86 stages, 62.2 to 77.4 ns floor), consistent with ticket 22's documented
instability of the ranked-#1-by-slack path under unrelated changes elsewhere in the design.
Whichever ticket last touches RTL still owns the current number.

Ticket 25 (`chip_top.sv`, routed against ticket 21's floorplan) is now the map's only frontier
ticket, unblocked by both 23 and this one.
