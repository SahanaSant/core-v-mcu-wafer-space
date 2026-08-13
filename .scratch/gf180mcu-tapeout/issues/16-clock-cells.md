# Write the GF180MCU clock cells

Type: task
Status: resolved
Assignee: yusefkarim
Blocked by: none

## Question

Graduated from ticket 03, which measured what the SoC actually instantiates. Six module
names, 70 instances, three technology cells behind them:

| Module | Instances | Cell behind it |
| --- | --- | --- |
| `pulp_clock_gating` | 55 | integrated clock gate |
| `cluster_clock_gating` | 1 | the same integrated clock gate |
| `cv32e40p_clock_gate` | 1 | the same integrated clock gate |
| `pulp_clock_mux2` | 8 | glitch-free clock mux |
| `pulp_clock_inverter` | 4 | clock inverter |
| `cluster_clock_inverter` | 1 | the same clock inverter |

They all live in one file, `rtl/gf180mcu/gf180_clk_gate.sv`, following upstream's
`pulp_clock_gating_xilinx.sv` in structure. Ports are in `flow/synth/stubs.sv`, taken from
the instantiation sites; delete each stub as its real module lands.

This is the one piece of technology-cell work that nothing blocks. It does not wait on the
memory architecture, the boot decision or the supply voltage, and it takes 70 instances out
of the black-box list, which makes ticket 10's synthesis measurement that much less
synthetic.

Decide, with evidence rather than by inspection of the cell name:

- **Which ICG cell.** `gf180mcu_fd_sc_mcu7t5v0__icgtp_*` is the candidate named in
  `rtl/gf180mcu/README.md`. Confirm it exists in the pinned PDK, at which drive strengths,
  and check its Liberty for a test-enable pin, because all three module families pass one
  (`test_en_i` / `scan_cg_en_i`) and a cell without it needs the enable ORing in RTL instead.
- **Whether to instantiate the cell or infer it.** Yosys can map `$dlatch`-based gating
  itself, and LibreLane's flow has its own clock-gating handling. An explicit instance is
  predictable and keeps the cell name in the netlist; inference risks the tool producing a
  latch plus AND that never becomes an ICG. Pick one deliberately and say why.
- **The clock mux.** GF180MCU may have no glitch-free mux cell. If it does not, this is
  ordinary RTL (a synchronised, break-before-make mux) rather than a cell instance, and it
  needs to be written rather than bound. Check before assuming a cell exists.
- **Whether the file is variant-neutral.** It instantiates cells by name only, so it should
  be, but state it: nothing here may hardcode a path into `pdk/`, and a cell name is not a
  variant assertion.

Upstream style applies, since this file is a ticket 13 candidate: `snake_case`, `_i` / `_o`
suffixes, and the SPDX header from `rtl/gf180mcu/README.md`.

## Definition of done

`make elaborate` reports the six modules gone from the missing list with no new errors, and
the stubs for them are deleted from `flow/synth/stubs.sv`. The answer records the cell chosen,
its drive strength, whether the test-enable pin exists, and what the clock mux turned out to
need.

## Answer

**Written and measured. Six modules, three cells, 70 instances, all in
`rtl/gf180mcu/gf180_clk_gate.sv`.** `make elaborate` reports zero errors and the six names are
gone, replaced by 57 `icgtp_1`, 5 `clkinv_1` and 8 `mux2_1`, which is exactly the 70 the ticket
counted. Their stubs are deleted from `flow/synth/stubs.sv`, four black boxes remain, and the
design has a real clock path for the first time.

| | decided | basis |
| --- | --- | --- |
| ICG cell | `gf180mcu_fd_sc_mcu7t5v0__icgtp_1` | bit-exact match to upstream's own behavioural model |
| test enable | **exists**, pin `TE` | `clock_gate_test_pin : true`; no ORing in RTL |
| inverter | `gf180mcu_fd_sc_mcu7t5v0__clkinv_1` | clock-optimised, same area as `inv_1` |
| clock mux | `gf180mcu_fd_sc_mcu7t5v0__mux2_1` | **no glitch-free cell exists, and none is wanted** |
| drive strength | `_1` throughout | CTS and the resizer size up from the minimum |
| instantiate or infer | **instantiate**, all three | upstream's own instruction; inference is unreliable |
| variant-neutral | yes | a library name is not a variant; no path into `pdk/` |

### The ICG is a bit-exact match, not an approximation

`icgtp` declares `clock_gating_integrated_cell : "latch_posedge_precontrol"`. Its state table
latches `E|TE` while `CLK` is low and its output carries `state_function : "(CLK&IQ2)"`, and
the PDK's own simulation model spells the same thing out structurally: `or(MGM_D0, E, TE)`
into a transparent-low latch, then `and(Q, CLK, IQ2)`.

Upstream's generic model in `tech_cells_generic/src/rtl/tc_clk.sv` is:

```systemverilog
always_latch begin
  if (clk_i == 1'b0) clk_en <= en_i | test_en_i;
end
assign clk_o = clk_i & clk_en;
```

Those are the same circuit, down to the enable being ORed with the test enable *before* the
latch, which is what "precontrol" names. So the three wrappers are a rename and nothing more,
and no behaviour changes between simulation, the FPGA emulation and the ASIC.

`TE` is a real pin, so the ticket's fallback (ORing the test enable into the enable in RTL) is
not needed. All three families pass one under three different names, and `cv32e40p`'s
`scan_cg_en_i` reaches the same `TE`.

The negedge sibling `icgtn` exists (`latch_negedge_precontrol`, 68.0512 um2) and is unused.
Every gated domain here is posedge, which is forced rather than assumed: upstream binds all
three families to one behavioural model, and that model gates the rising edge. The negedge
logic that does exist, the JTAG TAP and the SPI master phase inversion, inverts the clock
rather than gating it, and takes `clkinv`.

### Instantiate, not infer, and upstream says so

Yosys has no dependable route from a `$dlatch` plus AND to an integrated clock gate. If the
mapping does not fire you get a latch sitting in the clock path and a separate AND, which is
functionally identical and physically worse: two cells for CTS to reason about instead of one,
a latch that every downstream check will flag, and a clock path the mapper is free to
restructure into gates with unbalanced arrival. The whole reason these cells are drawn as one
cell is that this does not happen to them.

Upstream is explicit about it in `tech_cells_generic/README.md`: "Clock cells usually are
carefully designed cells which do not exhibit any glitches. Therefore they need to be manually
instantiated in ASIC designs." The wrapper modules exist precisely so a target can bind them.

The side benefit is that the cell name survives into the netlist, so `make area`'s per-module
breakdown and any clock-tree review can find all 70 by name.

### There is no glitch-free clock mux, and the design does not want one

GF180MCU's only clock-specific cells are `clkbuf`, `clkinv`, `icgtp` and `icgtn`. `mux2` and
`mux4` are ordinary data muxes, `Z = (I0 & !S) | (I1 & S)`. Nothing in the library mentions
glitch-free muxing. So the ticket's "check before assuming a cell exists" resolves to: it does
not exist.

The ticket's fallback was to write a synchronised break-before-make mux in RTL. **That would be
wrong, and it also cannot be built.**

Wrong, because of what the eight live instances actually select between. All eight pick between
phase variants of a single clock, never between unrelated clocks:

| Site | Instances | Selects between |
| --- | ---: | --- |
| `udma_spim_txrx` (2 SPI masters, 2 each) | 4 | CPHA: a clock and its gated self. CPOL: a clock and its own inversion |
| `udma_clkgen` (2 SPI, 1 SDIO) | 3 | a divided clock and the source it was divided from |
| `dmi_jtag_tap` | 1 | TCK and inverted TCK, for test mode |

Break-before-make on the SPI CPOL mux would stall the SPI clock for a synchroniser's worth of
cycles mid-transfer on a configuration change, which is worse than the runt it prevents.
Upstream agrees with the plain mux twice over: its generic implementation is
`assign clk_o = clk_sel_i ? clk1_i : clk0_i`, and every one of these sites carries an
`ifndef PULP_FPGA_EMUL` alternative that is the same ternary written inline. Note this also
corrects the ticket's own framing and the entry in `rtl/gf180mcu/README.md`, both of which
called `pulp_clock_mux2` a glitch-free mux. It never was one, in any upstream target.

Cannot be built, because **the port list has no reset**. Glitch-free muxing needs synchroniser
flops. Adding a reset port means patching every instantiation site upstream, which gives up
ticket 03's result that the SoC needs no source patches and ticket 13's hope of contributing
this file. Reset-less synchronisers would power up unknown and propagate X straight into the
clock, which is precisely what the gate-level boot simulation in this map's destination has to
survive.

The residual hazard is real and belongs to software, unchanged from upstream: `cfg_cpha_i`,
`cfg_cpol_i` and the uDMA `r_clockout_mux` are APB-writable at any time, so a peripheral must
be configured before it is enabled. Worth carrying into whatever ticket 04 produces as boot
software.

### What it cost, measured

The cells themselves are 3,776 um2: 57 × 61.4656 + 5 × 8.7808 + 8 × 28.5376. The
**hierarchical pass returns exactly that**, 4,723,425 um2 against ticket 14's 4,719,649, on an
identical 172,017 cells. That is the clean number, because nothing optimises across a module
boundary in that pass: 0.08% of the design, for the whole clock cell set.

The flattened pass, which is the one the budget uses, went the other way.

| | ticket 14 baseline | now | delta |
| --- | ---: | ---: | ---: |
| flattened cells | 118,998 | 118,290 | −708 |
| flattened area (um2) | 3,416,649 | 3,407,908 | −8,741 |
| kGE | 311.3 | 310.5 | −0.8 |
| placed at 35% (mm2) | 9.76 | 9.74 | −0.02 |
| **left for SRAM (mm2)** | **3.16** | **3.18** | **+0.02** |
| hierarchical area (um2) | 4,719,649 | 4,723,425 | +3,776 |

Two things are mixed in there and only one is a real effect.

**Three of the 57 clock gates have no load once flattened, and drop out.** The flat netlist
carries 54 `icgtp_1` against the hierarchy's 57. The three are
`ep_pf_evt_i.i_sync_clkb`, and the uDMA `i_udmacore.genblk1[7]` and `[8]` per-channel
peripheral gates, whose `periph_per_clk_o` outputs reach no flop. This is safe and it is
checkable: flop counts are unchanged (`dffrnq_1` 16,317 against the baseline's 16,318, `dffq_1`
4,287 against 4,287), so nothing lost a clock. It is the same class of effect as ticket 10's
eFPGA tie-off, and it is worth 184 um2.

**The rest, about 8,900 um2, is ABC remapping.** Removing 70 opaque hierarchy boundaries
perturbs what the mapper sees, and it made different choices across the whole design:
`aoi22_1` up 1,160 instances, `oai21_1` down 414, `aoi21_1` down 253, `nand2_1` down 83. None
of that is attributable to the clock cells.

So the honest reading is that **`make area`'s flattened total is not stable to better than
roughly 0.3% under a structural change**, and the clock cells cost 3,776 um2 while the flat
total happened to land 8,741 um2 lower. Do not bank the 0.02 mm2: ticket 11 should treat the
SRAM remainder as 3.16 to 3.18 mm2 and not read a difference at that scale as real. This is a
new constraint on how future tickets quote `make area`, and the map's "measure before
committing" preference now has a precision floor attached to it.

`make sta` still links and reports 35 logic stages at both corners, unchanged. The 3.3 V floor
moved from 29.1 ns to 31.2 ns, 58% to 62% of the 50 ns budget, and 5.0 V from 19.9 to 19.7.
That is the same remapping and not clock cell delay: the reported critical path contains no
`icgtp` and still starts and ends on flops in the crossbar. The only STA warnings are the
pre-existing ones about the remaining black boxes, the SRAM address widths and `apb_pll`'s
analog supplies.

### What it took to make an instantiation legal

One flow change, and it is not incidental. yosys-slang stops on an unknown module, so it
cannot see a PDK cell name unless some earlier yosys command loaded the module. `read_liberty
-lib` does exactly that, and slang then imports the instance as a black box. So
`flow/synth/filelist.sh` grew a `gf180_liberty` function that resolves the standard-cell
liberty and asserts the variant, `elaborate.sh` and `area.sh` both call it and both open their
yosys script with `read_liberty -lib`, and `area.sh`'s own copy of that resolution is gone.
LibreLane's synthesis already reads liberty before RTL, so nothing follows for the flow config.
Reading the liberty is also what gives these cells real area in `stat -liberty` rather than a
silent zero.

Two consequences worth stating.

**`make area SCL=<other library>` no longer works.** The cell names bind this file to
`gf180mcu_fd_sc_mcu7t5v0`, so the override ticket 15 built stops resolving. Nothing needs it
today: `gf180mcu_as_sc_mcu7t3v3` is dead on measurement and there is no third candidate. If
something ever does, the fix is a per-library binding file, not a parameter, because Verilog
cannot parameterise a module name.

**`flow/synth/blackbox.lib` lost its clock cell section.** Those six zero-delay models were
placeholders for exactly this ticket. `make sta` now gets real arcs for the clock cells from
the PDK liberty it already reads, so the clock is one step less ideal than it was.

### What this hands the tickets downstream

**Gate-level simulation needs a simulator with UDP support, which rules out Verilator.** The
PDK's `icgtp` simulation model is built on `gf180mcu_fd_sc_mcu7t5v0__udp_n_iq_latch`, one of
four Verilog user-defined primitives in
`libs.ref/gf180mcu_fd_sc_mcu7t5v0/verilog/primitives.v`, and it carries a `specify` block with
`$setup`/`$hold`/`$width` checks against a `notifier`. Verilator supports neither. This is not
a blocker: the container ships **Icarus Verilog 14.0**, which handles both. But it settles a
question the gate-level simulation fog patch would otherwise have discovered late, and it means
the harness will read `gf180mcu_fd_sc_mcu7t5v0.v` and `primitives.v` from the PDK rather than
compiling the netlist standalone.

**Ticket 05 inherits a clock generator whose consumers are now real.** `apb_pll` is still a
black box, but everything downstream of it is a technology cell, so whatever `gf180_clk_gen.sv`
produces is the last ideal thing in the clock path.

**The floorplan patch gains 70 fixed points.** 57 clock gates are 57 places CTS has to balance
to, and the 10,130-load clock net ticket 10 measured now has gates in it rather than
transparent black boxes.

Nothing new is opened, nothing is ruled out of scope, and no fog graduates: the four remaining
technology cells were already blocked on decisions rather than on sharpness, and this ticket
resolved none of those decisions.
