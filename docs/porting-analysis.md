# Fabricating the CORE-V MCU on GF180MCU via wafer.space

Research report, 12 August 2026. Target: a working plan to take the OpenHW Foundation CORE-V MCU (`openhwgroup/core-v-mcu`) from its current 22FDX/FPGA form to a taped-out GF180MCU die on a wafer.space shuttle slot, using open-source EDA tools.

---

## Executive Summary

The CORE-V MCU cannot be ported to GF180MCU as-is. The blocker is memory density, not logic. The design carries 512 KiB of interleaved L2 SRAM plus 64 KiB of private banks [22], while the largest SRAM macro in the open GF180MCU PDK is 512 bytes and occupies 0.209 mm² [6]. Reproducing 576 KiB would take roughly 236 mm² of silicon against a 12.92 mm² core area on wafer.space's largest slot [3]. The memory must shrink by a factor of 30 to 70. A realistic target is 16 KiB of unified SRAM plus a small boot ROM.

Three other subsystems must be removed or replaced outright: the QuickLogic ArcticPro-2 eFPGA (proprietary hard macro with no GF180 implementation) [14], the FLL clock generator (analog, no open GF180 equivalent), and the behavioural `$readmemh` boot ROM [22]. Pad count must drop from 48 general-purpose IO to about 40 to fit the 56 signal pads a wafer.space slot provides [3].

What remains is genuinely feasible. The CV32E40P is already configured without FPU and without Xpulp extensions in this codebase [22], putting it near 50 kGE [13]. LibreLane plus the wafer.space `gf180mcu-project-template` gives a pre-configured RTL-to-GDS flow with automatic pad ring generation, DRC, LVS, and a submission precheck [4][5]. A full 1×1 slot costs $7,000 to $8,000 and returns 1,000 dies [2]. Expect roughly 25 MHz, which is the template's default clock target [18], against 100+ MHz for the 22FDX original.

---

## 1. What the CORE-V MCU actually is

The CORE-V MCU descends from ETH Zurich's PULPissimo and is maintained by the OpenHW Foundation. It pairs a CV32E40P RISC-V core with a uDMA-based peripheral subsystem, a large L2 memory, a RISC-V debug module, and a QuickLogic embedded FPGA. The reference silicon was fabricated in GlobalFoundries 22FDX [14].

Reading the RTL in this working copy establishes the concrete configuration:

- **Core**: CV32E40P instantiated in `rtl/core-v-mcu/fc/fc_subsystem.sv` with `.FPU(0)` and `.PULP_XPULP(0)`, so it is a plain RV32IMC machine. The `cv32e40p_fp_wrapper.sv` and the vendored `fpnew` tree exist but are not enabled.
- **Memory**: `rtl/core-v-mcu/soc/l2_ram_multi_bank.sv` declares `BANK_SIZE_INTL_SRAM = 32768` 32-bit words across `NB_L2_CHANNELS = 4` banks (512 KiB interleaved), plus `BANK_SIZE_PRI0` and `BANK_SIZE_PRI1` of 8192 words each (32 KiB apiece). The banks instantiate `core_v_mcu_interleaved_ram` and `core_v_mcu_private_ram`, which are technology wrappers with no ASIC implementation checked in. Only an FPGA version (`emulation/xilinx/rtl/fpga_interleaved_ram.sv`) and a behavioural simulation version (`rtl/simulation/core_v_mcu_sim_ram.sv`, backed by `generic_memory`) exist.
- **Boot ROM**: `rtl/core-v-mcu/soc/a2_bootrom.sv` is a 2048-word × 32-bit array (8 KiB) initialised with `$readmemh("mem_init/boot.mem")`. Not synthesizable for ASIC.
- **eFPGA**: `rtl/efpga/` contains `A2_design.sv` (4,379 lines) and `eFPGA_wrapper.sv` (590 lines), QuickLogic-copyright models of the ArcticPro-2 fabric with FCB programming ports. It consumes 43 IO (`N_FPGAIO`) and connects to the SoC through TCDM ports and an APB-T1 interface in `soc_domain.sv`.
- **Clocking**: `rtl/generic_FLL/` and `rtl/apb_fll_if/apb_pll.sv` model an analog frequency-locked loop.
- **IO**: `rtl/includes/pulp_soc_defines.svh` sets `N_IO = 48` pad-frame pins, `N_GPIO = 32`, `N_APBIO = 51`, `N_FPGAIO = 43`. The top-level `core_v_mcu.sv` additionally exposes 5 JTAG pins, `ref_clk_i`, `rstn_i`, `bootsel_i`, and `stm_i`.
- **Peripherals**: uDMA channels for 2× UART, 2× QSPI, 2× I2C, 1× SDIO, 1× camera, plus advanced timers, GPIO, interrupt controller, I2C slave, and filters.

The RTL is heavy SystemVerilog. It uses interfaces extensively (`XBAR_TCDM_BUS`, `APB_BUS`, `AXI_BUS` defined in `rtl/core-v-mcu/components/pulp_interfaces.sv`), packed structs, packages, and parameterised generate blocks across more than 50 files. This matters for tool selection.

## 2. What GF180MCU and wafer.space actually offer

GF180MCU is GlobalFoundries' 180 nm mixed-signal process, released as an Apache-2.0 open PDK by Google and GlobalFoundries [21]. wafer.space runs pooled multi-project shuttles on it [1].

**Process and PDK.** Five metal layers in the C and D variants; wafer.space targets `gf180mcuD` (5LM, 1.19 µm top metal), enforced by the precheck's `PDK=gf180mcuD` and Metal5 maximum-layer rule [5][8]. Routing directions alternate starting with Metal1 horizontal. There is no local-interconnect layer, so all intra-cell wiring competes with Metal1 routing [8]. MIM and MOS capacitors, poly and high-resistance resistors are available [1].

**Standard cells.** `gf180mcu_fd_sc_mcu7t5v0` (3.92 µm row height) and `gf180mcu_fd_sc_mcu9t5v0` (5.04 µm), both 5 V, 229 cells each, 0.56 µm site width, not mixable in one floorplan [7][8]. The wafer.space template also exposes 3.3 V alternatives such as `gf180mcu_as_sc_mcu7t3v3` through the `SCL` environment variable [4].

**SRAM.** `gf180mcu_fd_ip_sram` ships four macros: 64×8, 128×8, 256×8, 512×8, all byte-wide with write mask [21]. The largest, `gf180mcu_fd_ip_sram__sram512x8m8wm1`, measures 431.86 × 484.88 µm for 209,400 µm², holds 512 bytes, and needs only Metal1 through Metal3 [6]. Minimum clock period is 6.08 ns typical at 5.0 V, 9.24 ns typical at 3.3 V [6]. wafer.space additionally offers 3.3 V blocks from `gf180mcu_ocd_ip_sram` including a 1 KiB variant, and community macros from Tim Edwards and Tholin were used in Run 1 [1]. Custom shapes can be generated with OpenRAM [21].

**IO.** `gf180mcu_fd_io` provides ESD-hardened bidirectional (`bi_24t`), input-only, analog, power, ground, corner, filler, and breaker pad cells for the 5 V wide-range inline non-CUP GPIO library [9].

**Slot geometry and pads** [3]:

| Slot | Die | Usable silicon | Core area | Signal pads (bidir / in / analog) | Power pads |
|---|---|---|---|---|---|
| 1×1 | 3.93 × 5.12 mm | 3.88 × 5.07 mm | 3.05 × 4.24 mm = 12.92 mm² | 56 (40 / 14 / 2) | 18 |
| 0.5×1 | 1.94 × 5.12 mm | 1.88 × 5.07 mm | 1.05 × 4.24 mm = 4.46 mm² | 56 (44 / 6 / 6) | 16 |
| 1×0.5 | 3.93 × 2.53 mm | 3.88 × 2.48 mm | 3.05 × 1.65 mm = 5.02 mm² | 56 (46 / 6 / 4) | 16 |
| 0.5×0.5 | 1.94 × 2.53 mm | 1.88 × 2.48 mm | 1.05 × 1.65 mm = 1.73 mm² | 48 (38 / 6 / 4) | 8 |

A 26 µm seal ring is reserved on each edge. Half-size slots have one bare cut edge, so the pad ring covers three sides only [3].

**Pricing and schedule (Run 3)** [2]:

| Slot | Early bird | Standard | Per die |
|---|---|---|---|
| 0.5×0.5 | $2,000 | $3,000 | $2–3 |
| 0.5×1 or 1×0.5 | $4,000 | $5,000 | $4–5 |
| 1×1 | $7,000 | $8,000 | $7–8 |

Every slot returns 1,000 dies, delivered bare in Gel-Pak or wire-bonded to breakout PCBs [1][2]. Run 3 dates as published: early bird ends 30 September 2026, purchase deadline 9 December 2026, clean GDS submission deadline 16 December 2026, parts shipped Q2 2027 [2]. Confirm these on wafer.space before committing, since shuttle dates move.

**Achieved density.** Run 1 designs landed at 3,000 to 14,000 logic cells per mm², with a best case of 22,000, which is 10 to 44 percent of theoretical maximum once routing overhead, infrastructure cells (about 75 percent of instances), power planning, and clock distribution are counted [1][10]. Plan against 8,000 to 12,000 cells/mm².

## 3. The memory problem, quantified

This is the finding that dictates the whole project.

At 209,400 µm² per 512 bytes, GF180MCU foundry SRAM costs **0.409 mm² per KiB** [6]. A 32-bit word requires four macros side by side, so the smallest useful bank is 512 words × 32 bits = 2 KiB across 4 macros = 0.838 mm².

| L2 size | Macros (512×8) | Area | Fraction of 1×1 core area (12.92 mm²) |
|---|---|---|---|
| 4 KiB | 8 | 1.68 mm² | 13% |
| 8 KiB | 16 | 3.35 mm² | 26% |
| 16 KiB | 32 | 6.70 mm² | 52% |
| 32 KiB | 64 | 13.4 mm² | 104% (does not fit) |
| 576 KiB (as-is) | 1,152 | 241 mm² | 1,870% |

Meanwhile the logic budget looks like this. CV32E40P without FPU is about 50 kGE with a latch-based register file [13]. A GF180 7-track NAND2 is roughly 6.6 µm² (3.92 µm row height × three 0.56 µm sites), so 50 kGE is about 0.33 mm² of raw cell area, or 0.7 to 0.9 mm² placed at the template's 35 percent target density [18]. Adding the uDMA subsystem, TCDM and APB interconnect, debug module, timers, and pad control plausibly brings total logic to 200–300 kGE, or 3 to 5 mm² placed.

**Conclusion**: on a full 1×1 slot, roughly 7 to 9 mm² remains for memory after logic. That is 16 to 21 KiB. Design for 16 KiB and treat 32 KiB as out of reach unless you move to denser community 3.3 V macros or an OpenRAM-generated compiler with a smaller cell.

## 4. Required RTL modifications

Ordered by how much they block progress.

### 4.1 Remove the eFPGA subsystem (mandatory)

The ArcticPro-2 fabric is a QuickLogic hard macro. There is no GF180MCU layout for it and no path to one [14]. Delete `rtl/efpga/` and `rtl/core-v-mcu/efpga_subsystem/` from the build, remove the `efpga_subsystem` instantiation from `soc_domain.sv`, tie off or delete the `s_lint_efpga_bus` TCDM ports and `s_lint_efpga_apbt1_bus`, strip the `efpga_test_*` signals from `core_v_mcu.sv`, and set `N_FPGAIO = 0`. This also frees the `0x1A30_0000` APB region and recovers 43 IO.

### 4.2 Replace L2 memory with GF180 SRAM macros (mandatory)

Write an ASIC implementation of `core_v_mcu_interleaved_ram` and `core_v_mcu_private_ram` that instantiates `gf180mcu_fd_ip_sram__sram512x8m8wm1`. Each 32-bit word needs four macros; deeper banks need depth-wise decoding plus an output mux. Map the existing port set as follows:

| Wrapper signal | SRAM pin | Notes |
|---|---|---|
| `clk_i` | `CLK` | rising edge |
| `csn_i` | `CEN` | already active-low, direct connect |
| `wen_i` | `GWEN` | global write enable, active low |
| `be_i[3:0]` | `WEN[7:0]` per macro | expand each byte enable to the 8-bit mask of its macro, active low |
| `addr_i` | `A[8:0]` | 512 words per macro; upper bits select depth slice |
| `wdata_i[31:0]` | `D[7:0]` × 4 | byte lane split |
| `rdata_o[31:0]` | `Q[7:0]` × 4 | byte lane concat, plus depth mux |

Then reduce the sizes in `l2_ram_multi_bank.sv`. A concrete 16 KiB configuration: keep `NB_L2_CHANNELS = 4`, set `BANK_SIZE_INTL_SRAM = 1024` words (4 KiB per bank, 8 macros each), and set `BANK_SIZE_PRI0` and `BANK_SIZE_PRI1` to 0 by removing the private banks entirely. A simpler alternative is to drop interleaving to a single bank, which cuts interconnect area but hurts nothing at this scale.

Update the address map in `rtl/includes/soc_mem_map.svh` to match, and regenerate the software headers with `make sw`. Note that `soc_domain.sv` also carries a stale `L2_BANK_SIZE = 29184` localparam that disagrees with `l2_ram_multi_bank.sv`; reconcile both.

Add the macro LEF, LIB, and GDS to LibreLane via `MACROS` and `EXTRA_LIBS`/`EXTRA_LEFS`, and place them explicitly with `MACRO_PLACEMENT_CFG`. Macro placement is manual work at this count; budget real time for floorplanning 32 macros around the core.

### 4.3 Replace the boot ROM (mandatory)

`$readmemh` does not synthesize through the open flow. Three options, in increasing order of effort:

- Convert `a2_bootrom.sv` into a synthesized ROM (a `case` statement or a `wire [31:0]` lookup generated from `boot.mem` by a small Python script). At 8 KiB this is expensive in cells; shrink the boot code to 1–2 KiB first.
- Reuse SRAM macros and load over JTAG before release from reset. Costs area and changes the boot flow.
- Boot directly from external SPI flash through the uDMA QSPI channel, keeping only a minimal ROM stub. This is the best fit for a 180 nm part and matches how the `bootsel_i` pin already works.

### 4.4 Replace the FLL (mandatory)

There is no open-source GF180MCU PLL or FLL. Drive the core clock directly from `ref_clk_i` through an input pad, and either delete `generic_FLL` and `apb_fll_if` or replace the FLL with a simple programmable integer divider so the existing APB register interface and `freq_meter.sv` still respond. If an on-chip oscillator is genuinely wanted later, the Mabrains `gf180mcu_riscv_soc` project and OpenFASoC both provide GF180 oscillator and bandgap IP that could be integrated as analog macros [1].

### 4.5 Map technology cells (mandatory)

`rtl/vendor/pulp_platform_tech_cells_generic/src/rtl/tc_clk.sv` and the deprecated `pulp_clk_cells.sv` provide behavioural clock gates. Bind them to `gf180mcu_fd_sc_mcu7t5v0__icgtp_*` integrated clock-gating cells, or let Yosys infer them. Also confirm the reset synchronisers in `safe_domain.sv` synthesize cleanly and add a proper power-on-reset scheme, since there is no POR cell in the flow.

### 4.6 Reduce the pad count (mandatory)

Current top level needs 48 IO plus `jtag_tck/tdi/tdo/tms/trst`, `ref_clk_i`, `rstn_i`, `bootsel_i`, `stm_i`, which is 57 signals against 56 available on a 1×1 slot [3]. Set `N_IO = 40` in `pulp_soc_defines.svh` and map:

- 40 bidirectional pads to `io_in_i` / `io_out_o` / `io_oe_o`
- 8 of the 14 input-only pads to `jtag_tck`, `jtag_tdi`, `jtag_tms`, `jtag_trst`, `ref_clk_i`, `rstn_i`, `bootsel_i`, `stm_i`
- `jtag_tdo_o` onto one bidirectional pad configured as output

Trim `N_APBIO = 51` accordingly, since GPIO(32) + PWM(16) + I2CS(3) exceeds what 40 pads can mux. Dropping PWM channels or GPIO width is the natural cut. The pad multiplexer in `pad_control.sv` and `safe_domain.sv` must be regenerated to match, and `util/ioscript.py` plus `perdef.json` are the existing generators for that table.

### 4.7 Optional trims if area is tight

Remove `udma_camera`, `udma_sdio`, `udma_i2s` (already `N_I2SC = 0`), `udma_filter`, and `apb_adv_timer` channels. Delete the AXI plug (`SOC_MEM_MAP_AXI_PLUG`) and the vendored `axi`/`fpnew` trees, which are dead weight once the eFPGA and cluster are gone. A minimal target of core plus 2× UART, 2× QSPI, 2× I2C, GPIO, timers, and debug is a sensible first silicon.

## 5. Toolchain

wafer.space's flow is entirely open source, built on LibreLane (the successor to OpenLane 2) driving Yosys, OpenROAD, Magic, Netgen, and KLayout [1][4][12].

**Start from the template.** Clone `github.com/wafer-space/gf180mcu-project-template`. It provides a Nix development shell, `src/chip_top.sv` and `src/chip_core.sv`, a `librelane/config.yaml` pre-tuned for `gf180mcuD` and wafer.space slots, a cocotb testbench for RTL and gate-level simulation, PDN configuration, and Makefile targets [4]. Slot and library selection are environment variables: `SLOT=1x1 SCL=gf180mcu_fd_sc_mcu7t5v0 make librelane`. Slot values are `1x1`, `0p5x1`, `1x0p5`, `0p5x0p5` [4].

Notable settings already in the template config [18]: `CLOCK_PERIOD: 40` (25 MHz), `PL_TARGET_DENSITY_PCT: 35`, hold-slack overfix margins of 0.30 to 0.35 ns, PDN core ring on Metal3/Metal4 at 25 µm width (30 µm is the maximum before slotting is required), antenna repair over 10 DRT iterations, and `ERROR_ON_MAGIC_DRC: False` because Magic DRC is not a submission gate.

**SystemVerilog is the real integration risk.** Yosys alone will not read the CORE-V MCU's interfaces, packages, and structs. Two viable front ends:

- **yosys-slang / sv-elab** (`povik/sv-elab`, integrated into Yosys from v0.67, also available as a plugin). It has the best SystemVerilog coverage of the open tools and is documented as elaborating PULP Platform designs including Snitch-Cluster, MemPool, and Cheshire [15]. LibreLane exposes it through `USE_SLANG: True` and `SLANG_ARGUMENTS: ['--keep-hierarchy']`, both present but commented out in the template config [18]. Try this first.
- **The PULP chain**: Bender collects dependencies, Morty pickles the sources into one file, SVase pre-elaborates and propagates parameters, and sv2v converts down to Verilog-2005 [16][17]. This is the path PULP used for the Iguana and Basilisk tapeouts and is the proven fallback if slang chokes on specific constructs.

Either way, plan on a dedicated bring-up phase where you get the design through elaboration before worrying about physical design. This is where most of the schedule risk sits.

**Verification.** Keep the existing Verilator model (`make model-lib`) and Questa flows for functional regression. Use the template's cocotb harness for gate-level simulation of the hardened netlist (`make sim-gl`), which is the only practical check that the SRAM wrappers, pad ring, and clock gates behave after synthesis.

**Sign-off and submission.** Run `gf180mcu-precheck` locally before every submission attempt [5]. It verifies a single top cell named to match `--top`, origin at (0,0), 0.001 µm database units, Metal5 as the maximum layer, dimensions matching the declared slot, density, absence of zero-area polygons, KLayout antenna and DRC decks, and Magic DRC. For chip-on-board delivery it also checks for the wafer.space marker cells (`gf180mcu_ws_ip__qrcode_id`, `shuttle_id`, `project_id`, `marker`, `logo`), which the template already lists under `IGNORE_DISCONNECTED_MODULES` [18]. Submit through `platform.wafer.space` [2].

## 6. Expected results

Set expectations against the 22FDX reference part, which runs above 100 MHz with 512 KiB of SRAM [14].

- **Frequency**: 20 to 40 MHz. The template default is 25 MHz [18]. The SRAM macro itself supports 164 MHz typical at 5.0 V and 108 MHz at 3.3 V [6], so the limit is standard-cell delay and open-tool timing closure, not the memory.
- **Memory**: 16 KiB, possibly 8 KiB if the logic overruns. This changes the software story completely. Programs must fit in 16 KiB or execute in place from SPI flash.
- **Area**: full 1×1 slot, $7,000 to $8,000, 1,000 dies [2].
- **Precedent**: Run 1 successfully shuttled several RISC-V designs including KianV (RV32IMA with MMU, full slot), the Racquet family (up to 23 SERV cores with SRAM on a full slot), RISCBoy-180, and TinyQV on a quarter slot [19]. None is as large as a reduced CORE-V MCU, but the flow is proven for RISC-V SoCs with SRAM macros on this shuttle.

## 7. Getting started, in order

1. **Reserve nothing yet.** Confirm current Run 3 deadlines and pricing directly on wafer.space and in the Crowd Supply campaign, then decide on 1×1 [2].
2. **Set up the flow on the template.** Install Nix, clone `gf180mcu-project-template`, run `nix-shell`, then `make librelane` on the stock 42-bit counter to confirm the environment produces a GDS. Run `gf180mcu-precheck` on the result. Do this before touching the MCU.
3. **Get the MCU through elaboration.** In a scratch branch, remove `rtl/efpga/` and `rtl/core-v-mcu/efpga_subsystem/` from `rtl/core-v-mcu/src_files.yml` and `soc_domain.sv`, then try `read_slang` with `--keep-hierarchy` on the remaining sources. Fix constructs until Yosys elaborates. Fall back to Morty plus SVase plus sv2v if needed [15][17].
4. **Build the SRAM wrapper.** Write the GF180 implementation of `core_v_mcu_interleaved_ram` and `core_v_mcu_private_ram` against `sram512x8m8wm1`, verify byte-enable and depth-mux behaviour in Verilator or cocotb against the existing `generic_memory` model, then shrink `l2_ram_multi_bank.sv` to 16 KiB.
5. **Replace clocking and boot.** Bypass the FLL to `ref_clk_i`. Convert the boot ROM to a synthesized ROM under 2 KiB, or move to SPI-flash boot.
6. **Rework the pad frame.** Set `N_IO = 40`, trim `N_APBIO`, regenerate the pad mux with `util/ioscript.py` and `perdef.json`, and map the top-level ports onto the template's `chip_top.sv` pad list.
7. **Synthesize and measure.** Run synthesis alone first and read the cell count. If total logic exceeds roughly 5 mm² placed at 35 percent density, start cutting peripherals per section 4.7 before attempting place and route.
8. **Floorplan the macros.** Write `MACRO_PLACEMENT_CFG` for the 32 SRAM macros, leaving routing channels. Expect several iterations against congestion; `GRT_ALLOW_CONGESTION: true` is already set in the template but is not a substitute for a good floorplan.
9. **Close timing at 25 MHz**, then push if there is slack. Watch hold violations, which the template overfixes for a reason.
10. **Gate-level simulate** the hardened netlist through cocotb, boot a hello-world image, then run precheck and submit.

## 8. Structuring the work for upstream contribution

Yes, this can be done in an upstreamable way, and the repository is already organised for it. The decisive design rule is **parameterise, never edit constants**, because every change described in section 4 is a reduction of a default that upstream still wants for its 22FDX target.

### 8.1 The existing target-abstraction pattern

`core-v-mcu.core` already separates technology-independent RTL from technology-specific implementations [22]:

- `files_rtl_generic` holds the portable design and depends on `quicklogic.com:ip:efpga` among other IP.
- `rtl-simulation` supplies behavioural stand-ins: `core_v_mcu_sim_ram.sv`, `a2_bootrom.sv`, `PLL18_TOP.sv`, `sram512x64.v`.
- `emulation-rtl` supplies the Xilinx implementations of exactly the cells this project must reimplement: `fpga_interleaved_ram.sv`, `fpga_private_ram.sv`, `fpga_pll.sv`, `pad_functional_xilinx.sv`, `pulp_clock_gating_xilinx.sv`, `cv32e40p_clock_gate.sv`.
- `not_emulation-rtl` carries `apb_fll_if/apb_pll.sv` for non-FPGA targets.
- Targets (`default`, `sim`, `model-lib`, `lint`, plus the board targets) compose these filesets.

The GF180 port is therefore a third sibling of `rtl-simulation` and `emulation-rtl`. Create `asic/gf180mcu/rtl/` mirroring `emulation/xilinx/rtl/` file for file, add a `gf180mcu-rtl` fileset, and add an `asic-gf180mcu` target. Nothing in the FPGA or simulation flows changes. This is the single most important structural decision, and it makes most of the work mergeable rather than a permanent fork.

### 8.2 Split into upstream PRs and a downstream repo

**Upstreamable to `openhwgroup/core-v-mcu`, in dependency order:**

1. **Reconcile the L2 size inconsistency.** `soc_domain.sv` declares `L2_BANK_SIZE = 29184` while `l2_ram_multi_bank.sv` uses `BANK_SIZE_INTL_SRAM = 32768` [22]. This is a latent bug independent of any port, and fixing it is an easy first PR that establishes contact with the maintainers.
2. **Promote the bank sizes to parameters.** `BANK_SIZE_INTL_SRAM`, `BANK_SIZE_PRI0`, and `BANK_SIZE_PRI1` are `localparam` today. Make them module parameters with the current values as defaults and plumb them from `soc_domain.sv`. Also parameterise the number of private banks so they can be reduced to zero. Behaviour for existing targets is bit-identical.
3. **Make the eFPGA optional.** `quicklogic.com:ip:efpga` is currently a hard dependency of `files_rtl_generic`. Move it into its own fileset and guard the `efpga_subsystem` instantiation with a `USE_EFPGA` parameter, following the pattern already established by the `USE_FPU` and `USE_HWPE` parameters on `core_v_mcu` [22]. This is likely the most welcome contribution of the set, since the eFPGA is the one non-open component in an otherwise open project and its removal unblocks every open-PDK port, not just this one.
4. **Add the `asic/gf180mcu/` fileset and target**: the SRAM wrappers instantiating `gf180mcu_fd_ip_sram__sram512x8m8wm1`, the GF180 clock-gate binding, the FLL bypass, and the pad mapping.
5. **Replace `$readmemh` in the boot ROM for synthesis targets.** Add a generator script producing a synthesizable ROM from `boot.mem`, selected by target, leaving the behavioural version for simulation.
6. **Parameterise the pad frame.** `N_IO`, `N_APBIO`, and `N_FPGAIO` are `` `define ``s in `pulp_soc_defines.svh`. Rather than hand-editing them, add a target-selected defines overlay and regenerate the pad mux with the existing `util/ioscript.py` and `perdef.json` generator. Respecting that generator matters, because hand-edited pad tables will not be accepted.

**Keep downstream in your own repository:** the LibreLane `config.yaml`, SDC constraints, pad ring configuration, macro placement files, slot marker cells, precheck CI, container definitions, and submission artifacts. These are shuttle-specific and slot-specific, have no meaning to upstream, and would be rejected.

### 8.2.1 How the downstream repository should consume upstream

Upstream's own choice of mechanism should decide this, and it is unambiguous. `rtl/vendor/` contains eight `.vendor.hjson` descriptors, matching `.lock.hjson` files pinning exact upstream commits, a `patches/` directory, and `util/vendor.py`, which is lowRISC's vendoring tool [22]. There is **no `.gitmodules` anywhere in the repository**. The CORE-V MCU maintainers deliberately chose vendoring with lock files and a patch stack over git submodules for their own dependencies, and `ips_list.yml` confirms the outcome: "No external dependencies. Everything has been flattened into `rtl/`" [22].

Mirror that idiom. Three options, ranked:

1. **`vendor.py` with a `.vendor.hjson`, a `.lock.hjson`, and a patches directory (recommended).** It pins an upstream commit, and critically it carries local patches on top of vendored code. That patch stack becomes a self-documenting ledger of your upstream PR backlog: each patch is a change you intend to submit, and when one merges you delete the patch and bump the lock. Divergence is visible and bounded rather than accumulating silently.
2. **Git submodule.** Simple and workable, but it gives you no patch mechanism, so uncommitted changes have to live on a fork branch you rebase by hand. It also departs from upstream's convention.
3. **fusesoc library dependency.** Semantically the most correct, since the design is a CAPI2 core named `openhwgroup.org:systems:core-v-mcu` [22]. But LibreLane does not consume fusesoc; it takes a flat `VERILOG_FILES` list [18], so a file-list generation step is required regardless.

That last point makes this decision lower-stakes than it appears. Whichever front end you choose, slang or the Morty/SVase/sv2v chain, the artifact handed to LibreLane is a flattened or pickled source set. The coupling between the two repositories is therefore just "produce a file list from an upstream checkout," which is a thin and well-defined seam. The choice is cheap to reverse, so pick option 1 and move on rather than deliberating.

**Do not vendor PDK files.** The SRAM wrapper may instantiate `gf180mcu_fd_ip_sram` cells by name, but the LEF, LIB, and GDS must be referenced through `PDK_ROOT`, not committed. The PDK is Apache-2.0 [21] so vendoring is legally permissible, but it bloats the repo and pins a version upstream cannot maintain.

### 8.3 Process

Contributors must be covered by the Eclipse Contributor Agreement, or the Eclipse Member Committer and Contributor Agreement for employees of member companies. OpenHW membership is strongly encouraged but not required. The mechanics are the standard fork, feature branch, pull request flow with reviewers selected on the PR [22, `CONTRIBUTING.md`]. Sign the ECA before the first PR. The README explicitly invites opening an issue to discuss involvement, so socialise the plan in an issue before writing code, particularly the eFPGA-optional change, which touches the top level.

## 9. Containerised build environment

Both candidates were evaluated. One is sufficient, one is not, and neither alone is the complete answer.

### 9.1 oss-cad-suite: not sufficient for tapeout, excellent for the front end

OSS CAD Suite ships Yosys with the Slang plugin, ABC, Verilator, iverilog, cocotb, GTKWave, Surfer, the formal tools, and nextpnr [26]. It contains **no OpenROAD, no Magic, no KLayout, no netgen, no LibreLane, and no PDKs** [26]. It cannot produce a GDS and cannot run DRC or LVS, so it cannot carry this project to submission.

It is however the fastest way to do the highest-risk step. Section 7 step 3 is getting the CORE-V MCU's SystemVerilog through elaboration, and oss-cad-suite has exactly the tool for that (`read_slang`) in a small archive with no PDK baggage. Use it for the RTL and simulation loop.

### 9.2 IIC-OSIC-TOOLS: yes, this is the implementation container

IIC-OSIC-TOOLS is an all-in-one Docker image built on Ubuntu 24.04 carrying LibreLane, OpenROAD, Yosys with the GHDL and Slang plugins, Magic, KLayout, netgen, OpenSTA, ngspice, xschem, and CVC, with **gf180mcuD** among its bundled PDKs alongside Sky130A and the IHP nodes [27]. AMD64 and ARM64 are both natively supported. The image is roughly 4 GB compressed and about 20 GB on disk. It runs under Docker or Podman and offers VNC, noVNC in a browser, local X11, Jupyter, and VS Code devcontainer access modes [27]. Tool versions are recorded in `tool_metadata.yml`, and the project has moved from Volare to Ciel for PDK management [27].

This covers every tool the wafer.space flow needs and satisfies the no-host-installs requirement.

### 9.3 The caveat that matters: version pinning

The wafer.space template does not merely require these tools, it pins them. The repository ships `flake.nix` and `flake.lock` for the toolchain, and its Makefile pins the PDK by commit:

```
PDK_ROOT ?= $(MAKEFILE_DIR)/gf180mcu
PDK      ?= gf180mcuD
PDK_COMMIT ?= f6eeac7dad085ffcc829ccfd721f7b4ce39edcf7
```

`make clone-pdk` runs `ciel enable` to materialise that exact commit under `$(PDK_ROOT)/ciel/gf180mcu/versions/$(PDK_COMMIT)/$(PDK)` [4]. IIC-OSIC-TOOLS ships its own LibreLane build and its own PDK build, so both can drift from what wafer.space validates against.

The PDK half of this is easy to fix and should be fixed. IIC-OSIC-TOOLS also uses Ciel, defaults to `PDK_ROOT=/foss/pdks`, and documents that you can bypass its download and point at a custom PDK root; LibreLane accepts `--pdk-root` explicitly [27]. So inside the container, run the template's `make clone-pdk` against a writable mounted volume and pass that path as `PDK_ROOT`. You then get the exact pinned PDK regardless of what the image bundles.

The LibreLane half is harder. Compare the image's `tool_metadata.yml` against the template's `flake.lock` and be aware that `librelane/config.yaml` declares `meta.version: 3` with named substituting steps [18], which is the part most likely to break across versions.

### 9.4 Recommended setup: three containers, nothing on the host

- **Front end (fast loop):** `oss-cad-suite` or IIC-OSIC-TOOLS. Yosys with `read_slang`, Verilator, cocotb. Use this until the MCU elaborates and simulates.
- **Implementation (daily driver):** IIC-OSIC-TOOLS, with `PDK_ROOT` bound to a volume holding the Ciel-fetched pinned PDK. Good ergonomics, ARM64 support, everything in one image.
- **Sign-off and submission (bit-exact):** two options, both fully containerised. First, `gf180mcu-precheck` ships its own `Dockerfile` [5], so the submission gate runs as a container and the Nix instruction in its README can be bypassed entirely. Second, for the final hardening run, build an image `FROM nixos/nix`, clone the template, and run `nix-shell` inside it. That reproduces the template's exact pinned toolchain with nothing installed on the host, at the cost of a slow first build.

Run the final GDS through the precheck container before every submission attempt, and treat a pass there, not a pass in IIC-OSIC-TOOLS, as the definition of done.

## 10. Evaluating c4m-arrakeen-memgen and other memory options

Since memory density is the binding constraint, any credible SRAM generator deserves scrutiny. This section also corrects two claims made earlier in this report.

### 10.1 What memgen actually is today

`c4m-arrakeen-memgen` (invoked as `arra-mem`) is Project Arrakeen's memory generator, built on Chips4Makers' PDKMaster framework [30]. Reading the source on the `dev` branch establishes its exact capabilities, because the entire tool is two files, `__init__.py` and `_main.py` [30]:

- **Technologies**: IHP SG13G2, Sky130, and **GF180MCU**, via `c4m-pdk-ihpsg13g2`, `c4m-pdk-sky130`, and `c4m-pdk-gf180mcu` [30].
- **Configurations**: single or dual port (`SPSRAMFactory` / `DPSRAMFactory`); word size freely selectable at 8 or above; write-enable bits selectable subject to `word_size / we_bits >= 8`.
- **Depth**: hardcoded to `words_vals = (128, 256, 512)`. **512 words is the maximum.**
- **Outputs**: GDS, LEF, an ngspice netlist, and a Verilog simulation model.
- **Interface**: an interactive prompt loop only. No API, no config file, no batch mode. Scripting it means piping stdin.
- **Maturity**: the repository's own disclaimer, printed on every run, reads "This is pre-alpha quality software; just above proof-of-concept level. Don't use it for production; no support is provided and use is at own risk!" The whole repo has six commits. The first is dated 25 May 2026, and **GF180MCU support was added on 1 July 2026**, six weeks before this report [30].

### 10.2 The genuine opportunity

There is a real architectural argument in its favour, and it is not about depth.

The CORE-V MCU's TCDM interface is 32 bits wide with four byte enables. memgen accepts arbitrary word size, so `word_size=32, we_bits=4` satisfies its `word_size/we_bits >= 8` constraint exactly and produces a native 32-bit macro. At 512 words that is a **2 KiB macro that maps one-to-one onto a TCDM bank port**, replacing the four `sram512x8` foundry macros that section 4.2 requires you to gang together for 0.838 mm².

The area case rests on periphery sharing. Four separate 8-bit macros replicate the row decoder, timing, and control logic four times. One 32-bit macro shares them across all 32 bits. That plausibly recovers a meaningful fraction of the 0.838 mm², perhaps 20 to 40 percent on the periphery, which at 16 KiB would be worth 1.5 to 2.5 mm² on a 12.92 mm² core area. That is not nothing.

It is also, at this stage, speculation. Chips4Makers publishes no density figures for the GF180MCU memories, and this report found none. **The decisive experiment is cheap and takes an afternoon**: run `uvx --refresh git+https://gitlab.com/Chips4Makers/c4m-arrakeen-memgen.git@dev`, select GF180MCU, single port, word size 32, 4 write-enable bits, 512 words, then measure the resulting GDS bounding box in KLayout and compare against 0.838 mm². Do this before forming any opinion, including the one above.

### 10.3 Why it should not go on the critical path

Four blockers, in order of severity:

1. **No Liberty file.** memgen emits GDS, LEF, spice, and a Verilog model, but no `.lib` [30]. LibreLane needs Liberty timing for any macro in order to run STA, and timing closure around SRAM is exactly where you need it. The ngspice netlist means you could characterize the macro yourself, but writing and validating a characterization flow is a project in its own right and is not on the path to a December tapeout.
2. **Six weeks of GF180MCU support, pre-alpha by the author's own statement.** Not silicon proven on this node. The predecessor `c4m-flexmem` describes itself as experimental and notes that "the library now progresses at the need of tape-outs" [31], which implies C4M memories have seen silicon, but not this generator on GF180MCU.
3. **DRC risk against the wafer.space precheck.** The submission gate runs KLayout DRC decks plus Magic DRC [5]. Note that even the *foundry* SRAM macros need an extensive list of `MAGIC_GDS_FLATGLOB` workarounds in the wafer.space template config to avoid false positives [18]. A macro from a non-foundry generator will need its own set, discovered the hard way.
4. **`c4m-pdk-gf180mcu` is itself pre-alpha**, describing itself as "pre-alpha development" with a README that "still needs to be written" [32]. It also carries its own standard cell library rather than using `gf180mcu_fd_sc_mcu7t5v0`. A generated macro is just GDS plus LEF and should still drop into a foundry-cell design, but this has not been demonstrated on a wafer.space run.

Crucially, **memgen does not change the conclusion of section 3.** The 512-word depth cap means it improves the constant, not the order of magnitude. Best case it moves a full slot from roughly 16 KiB to perhaps 20 to 24 KiB. 512 KiB remains impossible either way.

**Recommendation**: timebox one day to generate a 512×32 macro and measure it. If the area win is real, keep it as a phase-two optimisation for a second tapeout, once someone has solved the Liberty problem. Build first silicon on the foundry `gf180mcu_fd_ip_sram` macros, which have datasheets, timing, and Run 1 silicon behind them [6][10].

### 10.4 A better near-term lead: the 3.3V SRAM library

Section 3's open question about `gf180mcu_ocd_ip_sram` now has a partial answer, and it is more promising than memgen. R. Timothy Edwards is presenting "Finally Testing Silicon Again: Chipalooza and Wafer.Space!" at ORConf 2026, reporting that packaged parts arrived in summer 2026 including "new 3.3V support for GF180MCU on the first Wafer.Space shuttle run," with characterization results for "3.3V SRAM and I/O library components" [33]. These are silicon-validated parts from the shuttle you are targeting, including a 1 KiB block [1]. A 1 KiB macro that is less than twice the area of the 512 B foundry macro would beat both alternatives with none of memgen's tooling risk.

ORConf 2026 runs 11 to 13 September 2026 in Ghent, roughly one month from now and three months before the Run 3 submission deadline [33]. Three talks on the programme bear directly on this project: the Chipalooza and wafer.space characterization talk above, "A Look Back at Two Successful wafer.space Shuttle Runs" by Leo Moser, and "The state of project Arrakeen" by Staf Verhaegen, which covers SRAM generator progress from the IHP FlowSpace project [33]. Attending or following up on those three talks is the single highest-value information-gathering action available, and the timing works.

### 10.5 Correction: OpenRAM

Section 2 of this report stated that custom SRAM shapes can be generated with OpenRAM, citing the GF180MCU PDK ecosystem documentation [21]. That claim is contested. OpenRAM's own documentation indicates it **does not support gf180mcu** for SRAM generation, while the VLSIDA GF180MCU tutorial recommends it for custom shapes [8]. The sources conflict, and this report did not resolve which is current. Verify against OpenRAM's `stable` branch technology directory before relying on it. Do not treat OpenRAM as an available fallback until you have confirmed it.

### 10.6 Correction: prior CORE-V work on GF180MCU exists

The Limitations section originally stated that no prior port of PULPissimo or the CORE-V MCU to an open PDK was found. That is wrong. **`lip6/core-v-180-mcu`** is a CORE-V implementation targeting GF180MCU from the LIP6 laboratory at Sorbonne Université [34]. Its characteristics:

- Scope is currently the **CV32E40P core only**, described as "only a demonstrator on the RISC-V component," not the full MCU [34].
- Toolchain is **Yosys for synthesis and Coriolis for place and route**, with **sv2v and svase** handling SystemVerilog translation, using the **Chips4Makers `c4m-pdk-gf180mcu`** standard cells rather than the foundry library [34].
- GDS generation runs in GitHub Actions CI, about one hour cold and eight minutes warm [34].
- The README states "no checks have been performed, it is just to set up the design flow for now" [34]. No die size, results, or tapeout plans are documented.

This does not displace the plan in this report. Coriolis and C4M cells are a different flow from LibreLane with foundry cells, and a core-only demonstrator is a long way from a wafer.space submission. But it matters for two reasons. First, it is **independent evidence that the sv2v plus svase front-end path works on CV32E40P specifically**, which de-risks the highest-risk step in section 7. Their CI is a working reference to read before attempting step 3. Second, LIP6 is doing overlapping work, and contacting them before starting is plainly worthwhile.

## Limitations and open questions

Several numbers here are engineering estimates rather than measured results. The 200–300 kGE figure for the full SoC logic is extrapolated from the published 50 kGE CV32E40P figure [13] and typical PULPissimo peripheral sizes; it has not been verified by synthesizing this codebase. Run a synthesis-only pass early, since the entire area budget hinges on it. Similarly, the 20–40 MHz frequency range comes from the template default and Run 1 density data, not from a timing run on this design.

The 3.3 V options deserve investigation before committing to the 5 V `gf180mcu_fd_sc_mcu7t5v0` library. wafer.space has test chips for `gf180mcu_ocd_ip_sram` 3.3 V macros including a 1 KiB block [1], and a 1 KiB macro that is less than twice the area of the 512 B macro would meaningfully improve the memory budget. This was not quantified because the `gf180mcu_ocd_ip_sram` datasheet was not located during this research. Ask on the wafer.space Discord or the `gf180mcu-pdk-users` group.

This report initially concluded that no prior port of PULPissimo or the CORE-V MCU to an open PDK existed. Section 10.6 corrects that: `lip6/core-v-180-mcu` targets CV32E40P on GF180MCU with Yosys, Coriolis, and sv2v/svase [34]. It is a core-only demonstrator on a different flow, so the plan here stands, but it is a useful reference and LIP6 is worth contacting. PULP's own Basilisk and Iguana efforts remain the best documented precedent for driving commercial-grade SystemVerilog IP through open tools [17].

Finally, Run 3 dates as fetched from wafer.space showed an early bird deadline of 30 September 2026 alongside text implying early bird had ended. Treat all dates as needing direct confirmation.

---

## Bibliography

[1] wafer.space (2026). "Technology". https://wafer.space/technology.html (Retrieved: 2026-08-12)

[2] wafer.space (2026). "Budget silicon manufacturing". https://wafer.space/ (Retrieved: 2026-08-12)

[3] wafer.space / Tim Ansell (2026). "GF180MCU Slot Sizes". http://mith.ro/gf180mcu-project-template/ (Retrieved: 2026-08-12)

[4] wafer-space (2026). "gf180mcu-project-template". GitHub. https://github.com/wafer-space/gf180mcu-project-template (Retrieved: 2026-08-12)

[5] wafer-space (2026). "gf180mcu-precheck: Precheck for wafer.space MPW runs using the gf180mcu PDK". GitHub. https://github.com/wafer-space/gf180mcu-precheck (Retrieved: 2026-08-12)

[6] GlobalFoundries (2026). "gf180mcu_fd_ip_sram__sram512x8m8wm1". GF180MCU PDK documentation. https://gf180mcu-pdk.readthedocs.io/en/latest/IPs/SRAM/gf180mcu_fd_ip_sram/cells/gf180mcu_fd_ip_sram__sram512x8m8wm1/gf180mcu_fd_ip_sram__sram512x8m8wm1.html (Retrieved: 2026-08-12)

[7] GlobalFoundries (2026). "Standard Cells". GF180MCU PDK documentation. https://gf180mcu-pdk.readthedocs.io/en/latest/digital/standard_cells/standard_cells.html (Retrieved: 2026-08-12)

[8] UCSC VLSI-DA (2026). "GF180MCU PDK". Chip Tutorials. https://vlsida.github.io/chip-tutorials/gf180mcu.html (Retrieved: 2026-08-12)

[9] GlobalFoundries (2026). "gf180mcu_fd_io 5V Inline non-CUP GPIO Datasheet". GF180MCU PDK documentation. https://gf180mcu-pdk.readthedocs.io/en/latest/IPs/IO/gf180mcu_fd_io/datasheet.html (Retrieved: 2026-08-12)

[10] Crowd Supply (2025). "wafer.space GF180MCU Run 1". https://www.crowdsupply.com/wafer-space/gf180mcu-run-1 (Retrieved: 2026-08-12)

[11] Crowd Supply (2026). "wafer.space GF180MCU Run 3". https://www.crowdsupply.com/wafer-space/gf180mcu-run-3/ (Retrieved: 2026-08-12)

[12] Crowd Supply (2025). "Easier Design Flow: LibreLane and the gf180mcu Project Template". wafer.space GF180MCU Run 1 update. https://www.crowdsupply.com/wafer-space/gf180mcu-run-1/updates/librelane-template (Retrieved: 2026-08-12)

[13] OpenHW Group (2026). "CV32E40P User Manual". https://docs.openhwgroup.org/projects/cv32e40p-user-manual/en/latest/ (Retrieved: 2026-08-12)

[14] OpenHW Group (2026). "CORE-V-MCU Overview" and "eFPGA SubSystem". CORE-V MCU documentation. https://docs.openhwgroup.org/projects/core-v-mcu/doc-src/overview.html (Retrieved: 2026-08-12)

[15] Popoloski, M. and Povik, M. (2026). "sv-elab: SystemVerilog design elaborator into word-level netlist form" (formerly yosys-slang). GitHub. https://github.com/povik/sv-elab (Retrieved: 2026-08-12)

[16] Snyder, Z. (2026). "sv2v: SystemVerilog to Verilog conversion". GitHub. https://github.com/zachjs/sv2v (Retrieved: 2026-08-12)

[17] Sauter, P. et al. (2024). "Industry-Grade SystemVerilog IPs And The Open Flow: How We Synthesized Iguana". F-Si wiki. https://wiki.f-si.org/index.php?title=Industry-Grade_SystemVerilog_IPs_And_The_Open_Flow:_How_We_Synthesized_Iguana (Retrieved: 2026-08-12)

[18] wafer-space (2026). "librelane/config.yaml". gf180mcu-project-template. https://github.com/wafer-space/gf180mcu-project-template/blob/main/librelane/config.yaml (Retrieved: 2026-08-12)

[19] wafer-space (2025). "ws-run1: wafer.space GF180MCU Run 1". GitHub. https://github.com/wafer-space/ws-run1 (Retrieved: 2026-08-12)

[20] VLSIDA (2026). "OpenRAM memory compiler". Referenced via GF180MCU PDK documentation. https://github.com/VLSIDA/OpenRAM (Retrieved: 2026-08-12)

[21] Google / GlobalFoundries (2026). "globalfoundries-pdk-ip-gf180mcu_fd_ip_sram: SRAM macros created for the GF180MCU". GitHub. https://github.com/google/globalfoundries-pdk-ip-gf180mcu_fd_ip_sram (Retrieved: 2026-08-12)

[22] OpenHW Group. CORE-V MCU RTL source, local working copy at `core-v-mcu/`. Specifically `rtl/core-v-mcu/soc/l2_ram_multi_bank.sv`, `rtl/core-v-mcu/soc/a2_bootrom.sv`, `rtl/core-v-mcu/fc/fc_subsystem.sv`, `rtl/core-v-mcu/top/core_v_mcu.sv`, `rtl/includes/pulp_soc_defines.svh`, `rtl/includes/soc_mem_map.svh`, `rtl/efpga/`. (Inspected: 2026-08-12)

[23] LinuxGizmos (2025). "wafer.space Launches GF180MCU Run 1 for Custom Silicon Fabrication". https://linuxgizmos.com/wafer-space-launches-gf180mcu-run-1-for-custom-silicon-fabrication/ (Retrieved: 2026-08-12)

[24] CNX Software (2025). "wafer.space lets you design your custom silicon just for $7 per die". https://www.cnx-software.com/2025/10/07/wafer-space-lets-you-design-your-custom-silicon-just-for-7-per-die/ (Retrieved: 2026-08-12)

[25] Crowd Supply (2025). "wafer.space GF180MCU Run 2". https://www.crowdsupply.com/wafer-space/gf180mcu-run-2 (Retrieved: 2026-08-12)

[26] YosysHQ (2026). "oss-cad-suite-build". GitHub. https://github.com/YosysHQ/oss-cad-suite-build (Retrieved: 2026-08-12)

[27] Institute for Integrated Circuits, JKU Linz (2026). "IIC-OSIC-TOOLS: all-in-one Docker image for SKY130/GF180/IHP130-based analog and digital chip design". GitHub. https://github.com/iic-jku/IIC-OSIC-TOOLS (Retrieved: 2026-08-12)

[28] LibreLane (2026). "Docker-based Installation". LibreLane Documentation. https://librelane.readthedocs.io/en/latest/installation/docker_installation/index.html (Retrieved: 2026-08-12)

[29] wafer-space (2026). "gf180mcu: development repository for the gf180mcuD PDK variant" (deprecated, upstreamed to open_pdks). GitHub. https://github.com/wafer-space/gf180mcu (Retrieved: 2026-08-12)

[30] Chips4Makers (2026). "c4m-arrakeen-memgen (arra-mem), `dev` branch". GitLab. README, `pyproject.toml`, `c4m/arrakeen/memgen/_main.py`, and commit history inspected directly. https://gitlab.com/Chips4Makers/c4m-arrakeen-memgen/-/tree/dev (Retrieved: 2026-08-12)

[31] Chips4Makers (2024). "c4m-flexmem: Flexible, scalable memory macro generators". GitLab. https://gitlab.com/Chips4Makers/c4m-flexmem (Retrieved: 2026-08-12)

[32] Chips4Makers (2026). "c4m-pdk-gf180mcu: PDKMaster based GF180MCU PDK". GitLab. https://gitlab.com/Chips4Makers/c4m-pdk-gf180mcu (Retrieved: 2026-08-12)

[33] FOSSi Foundation (2026). "ORConf 2026 programme", Ghent, Belgium, 11–13 September 2026. Talks: R. Timothy Edwards, "Finally Testing Silicon Again: Chipalooza and Wafer.Space!"; Leo Moser, "A Look Back at Two Successful wafer.space Shuttle Runs"; Staf Verhaegen, "The state of project Arrakeen". https://fossi-foundation.org/orconf/2026 (Retrieved: 2026-08-12)

[34] LIP6, Sorbonne Université (2026). "core-v-180-mcu: CORE-V Implementation on GF 180 MCU node". GitHub. https://github.com/lip6/core-v-180-mcu (Retrieved: 2026-08-12)

[35] Chips4Makers / Staf Verhaegen (2024). "Project Arrakeen: a PDKMaster based framework for scalable and portable digital and analog circuits". F-Si wiki. https://wiki.f-si.org/index.php?title=Project_Arrakeen:_a_PDKMaster_based_framework_for_scalable_and_portable_digital_and_analog_circuits (Retrieved: 2026-08-12)

## Methodology

Findings combine direct inspection of the CORE-V MCU RTL in this repository with web research on wafer.space's shuttle offering and the GF180MCU open PDK. Architectural claims about the MCU (memory sizes, core configuration, IO counts, eFPGA integration) were read from the source files rather than documentation, since documentation and RTL disagree in places, notably the L2 bank size. Process and shuttle claims were taken from primary sources: the GF180MCU PDK documentation for cell and macro specifications, the wafer.space site and project template repository for slot geometry and flow configuration, and the precheck repository for submission requirements.

Area and frequency estimates are derived arithmetic, not measurements. The SRAM density figure comes directly from the published macro dimensions. Logic area is extrapolated from the published CV32E40P gate count and GF180 cell geometry, and is the weakest number in this report. It should be replaced with a real synthesis result as the first substantive step of the project.
