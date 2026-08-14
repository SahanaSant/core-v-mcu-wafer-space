# Write gf180_clk_gen.sv and wire the reset synchronizer

Type: task
Status: open
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

<!-- filled on resolution -->
