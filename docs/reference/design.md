# The design, as measured

What is in the signed-off 1x1 tile. Every number comes from the final run's
`metrics.json`, the precheck output, or the RTL. Nothing here is an estimate unless it says
so. Reproduce any of it by following [how-to/harden.md](../how-to/harden.md).

## Tile and process

|                |                                                             |
| -------------- | ----------------------------------------------------------- |
| Slot           | wafer.space **1x1**                                         |
| PDK            | **gf180mcuD**, open_pdks `f6eeac7d`, built from source      |
| Die            | **3,932 × 5,122 µm**, 20.14 mm²                             |
| Core           | **3,048 × 4,238 µm**, 12.90 mm²                             |
| Utilisation    | **53.3%** overall, **41.4%** standard cells alone           |
| Standard cells | `gf180mcu_fd_sc_mcu7t5v0`, 7-track, 5 V oxide, run at 3.3 V |

The gap between the two utilisation figures is the sixteen SRAM macros: 2.61 mm² of macro
against 4.26 mm² of standard cells.

## Supplies and clock

- Core: **3.3 V**, single rail
- IO ring: **5.0 V**, level shifter inside each `gf180mcu_ocd_io` pad
- Clock: **5 MHz / 200 ns**, one main domain (`clk_PAD`), external, no PLL
- JTAG `tck` is a second, asynchronous domain
- Total power: **1.84 mW** (1.27 internal, 0.54 switching, 0.03 leakage)
- Power grid: 0 violations, worst VDD drop 7.8 µV

## Compute

- **CV32E40P**, RV32IMC. FPU and Xpulp extensions are disabled upstream and stay off.
- PULPissimo-derived SoC: AXI crossbar interconnect, uDMA peripheral subsystem.
- **14,445 flip-flops** in 143,252 logic cells.

## Memory

**16 KiB L2 SRAM**, contiguous `0x1C00_0000` to `0x1C00_4000`: two interleaved channels of
4 KiB plus two private banks of 4 KiB.

Built from **16 × `gf180mcu_ocd_ip_sram__sram1024x8m8wm1`** (1024 × 8, 301.30 × 515.81 µm),
four side by side per 32-bit word. 1024 words is the macro's whole depth, so there is no
depth decoding and no output mux.

**Boot ROM**: 208 words / 832 bytes, synthesised to gates rather than a macro.

## Peripherals

Configured counts, from `core-v-mcu/rtl/includes/*.svh`:

| Block                                  | Count  | Note                                                  |
| -------------------------------------- | ------ | ----------------------------------------------------- |
| QSPI master                            | **2**  | `qspim0` is the boot flash, `qspim1` general purpose  |
| UART (uDMA)                            | 1      | second instance cut                                   |
| I2C master                             | 1      | second master cut                                     |
| SDIO                                   | 1      |                                                       |
| GPIO                                   | **16** | shrunk from 32                                        |
| Advanced timer (PWM)                   | yes    | 8 of 16 channels bonded; no I2S in this configuration |
| Timer unit, SoC control, FLL interface | yes    |                                                       |
| JTAG / debug                           | yes    | own asynchronous clock domain                         |

Cut deliberately: `apb_i2cs`, the uDMA filter (`N_FILTER 0`), the uDMA camera (`N_CAM 0`).
HyperBus is 0. Together those cuts took flattened area down 25.9% and core occupancy from
95.6% to 76.4%.

The eFPGA is stubbed out; its APB slot at `0x1A30_0000` is decoded and reads zeros.

## Pad ring

1,140 pad cells in total. As LibreLane classifies them in `metrics.json`:

| Class            | Count |
| ---------------- | ----: |
| input/output pad |    43 |
| input-only pad   |    13 |
| power pad        |    18 |
| pad spacer       | 1,066 |

By cell name in the netlist that is 41 `bi_24t` plus 2 `asig_5p0` (LibreLane counts the
analog pads as input/output), 12 `in_c` plus 1 `in_s`, 6 `dvdd` + 8 `dvss` + 2 `vdd` +
2 `vss`, and 1,062 fill cells plus 4 corner cells.

Function-by-function assignment is in [pinout.md](pinout.md).

## Boot

SPI flash, copy-then-jump, **CRC32-checked**. The boot ROM reads the image over QSPI into L2
at `0x1C00_0000`, verifies it, and jumps. A CRC mismatch calls `halt()`, so reaching the
application at all is the CRC passing. There is no bootsel fallback; JTAG is the only
recovery path.

## Cell count

`design__instance__count` is **508,806**, but quoting that as a cell count would mislead:
five sixths of it is fill and tap. The useful number is **143,252 logic cells**.

|                 |       Count |
| --------------- | ----------: |
| total instances |     508,806 |
| fill            |     294,662 |
| tap             |      66,939 |
| endcap          |       2,712 |
| pad cells       |       1,140 |
| antenna diodes  |          80 |
| macros          |          21 |
| **logic cells** | **143,252** |

Of those 143,252:

| Class                     |      Count |     Share |
| ------------------------- | ---------: | --------: |
| multi-input combinational |     68,537 |     47.8% |
| **timing repair buffers** | **48,025** | **33.5%** |
| sequential (flip-flops)   | **14,445** |     10.1% |
| inverters                 |      8,696 |      6.1% |
| clock buffers             |      2,598 |      1.8% |
| clock inverters           |        800 |      0.6% |
| tie cells                 |        105 |           |
| clock gates               |         45 |           |

A third of the logic is repair buffering, and that is the price of closing this design. Only
48 of them are hold buffers; the rest come from `repair_design` fixing transition and
capacitance on the RTL's own broadcast nets. It is also where the remaining max-slew and
max-cap warnings live. See [explanation/timing.md](../explanation/timing.md).

## Timing

**WNS is 0 at every corner and TNS is 0.0 for both setup and hold.** What the flow reports is
worst slack, positive throughout.

| Corner                         | Worst setup | Worst hold |
| ------------------------------ | ----------: | ---------: |
| **max_ss_125C_3v00** (signoff) |   **+4.97** |      +1.65 |
| nom_ss_125C_3v00               |      +11.46 |      +1.81 |
| min_ss_125C_3v00               |      +16.70 |      +1.95 |
| max_tt_025C_3v30               |      +38.41 |      +0.54 |
| nom_tt_025C_3v30               |      +39.16 |      +0.65 |
| min_tt_025C_3v30               |      +39.78 |      +0.75 |
| **max_ff_n40C_3v60**           |      +46.82 | **+0.034** |
| nom_ff_n40C_3v60               |      +47.30 |      +0.11 |
| min_ff_n40C_3v60               |      +47.71 |      +0.19 |

All figures in ns. The two binding constraints are **setup +4.97 ns at `max_ss_125C_3v00`**
and **hold +0.034 ns at `max_ff_n40C_3v60`**.

That 34 ps of hold margin is thin. It is positive against a propagated clock tree with the
0.25 ns `CLOCK_UNCERTAINTY_CONSTRAINT` applied on top, and that uncertainty was never relaxed
to reach it, so the margin is real rather than arranged. It is the number to watch if
anything downstream perturbs placement.

Setup margin is large everywhere except the signoff corner because 200 ns is set by the slow
corner; the fast corners are nowhere near limited by it.

STA runs nine corners: {min, nom, max} × {`tt_025C_3v30`, `ss_125C_3v00`, `ff_n40C_3v60`}.

## Sign-off results

| Check                       | Result                                             |
| --------------------------- | -------------------------------------------------- |
| `gf180mcu-precheck`         | **16/16 stages pass**                              |
| KLayout DRC (ID-stamped)    | 738 rules, **all zero**                            |
| Magic DRC                   | 0                                                  |
| Routing DRC                 | 0                                                  |
| LVS                         | circuits match uniquely                            |
| XOR                         | 0 differences                                      |
| Antenna                     | 0 nets, 0 pins (66 diodes inserted)                |
| Density, zero-area polygons | clear                                              |
| Setup, 9 corners            | **0 violations**, +4.97 ns worst                   |
| Hold, 9 corners             | **0 violations**, +0.034 ns worst                  |
| Disconnected pins           | 0                                                  |
| Gate-level simulation       | boots from flash, prints `BOOT OK` and `SRAM PASS` |

## Known gaps, carried knowingly

- **Max slew (457) and max cap (291) are not closed.** LibreLane defers them as warnings and
  the precheck does not examine them. Many likely sit on macro pins whose Liberty is
  uncharacterised, so tightening against those numbers would optimise against fiction.
- **The gate-level result shows function, not silicon margin.** The SRAM Verilog model is 2x
  optimistic on access time on purpose; the only local data that would correct it is itself
  corrupted. See [explanation/known-issues.md](../explanation/known-issues.md).
- **Die ID is a placeholder** (`FFFFFFFF`) until wafer.space assigns one.
- Global routing has unexplained run-to-run time variance, 1m05s to 4+ hours.
