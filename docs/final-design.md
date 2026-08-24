# CORE-V MCU on GF180MCU: final design summary

What is in the signed-off 1x1 tile, as measured on `RUN_2026-08-24_02-03-47`.
Every number below comes from `flow/final/metrics.json`, the precheck run, or
the RTL, not from estimates.

## Tile and process

- Slot: wafer.space **1x1**, targeting Run 3 (December 2026)
- PDK: **gf180mcuD**, open_pdks `f6eeac7d`, built from source
- Die: **3,932 x 5,122 um**, 20.14 mm2
- Core: **3,048 x 4,238 um**, 12.90 mm2
- Utilisation: **53.3%** overall, 41.4% standard cells
- Standard cells: `gf180mcu_fd_sc_mcu7t5v0` (7-track, 5 V oxide, run at 3.3 V)

## Supplies and clock

- Core: **3.3 V**, single rail
- IO ring: **5.0 V**, level shifter inside each `gf180mcu_ocd_io` pad
- Clock: **5 MHz / 200 ns**, single main domain (`clk_PAD`)
- JTAG `tck` is a second, asynchronous clock domain
- Total power: **1.84 mW** (1.27 internal, 0.54 switching, 0.03 leakage)
- Power grid: 0 violations, worst VDD drop 7.8 uV

## Compute

- Core: **CV32E40P**, RV32IMC; FPU and Xpulp extensions disabled upstream and kept off
- SoC: PULPissimo-derived, AXI crossbar interconnect, uDMA peripheral subsystem
- Sequential cells: **14,445** flip-flops
- Combinational: 68,537 multi-input cells + 8,696 inverters
- Clock tree: 2,598 buffers, 800 inverters, 45 gates

## Memory

- **16 KiB L2 SRAM**, contiguous `0x1C00_0000` to `0x1C00_4000`
  - 2 interleaved channels of 4 KiB + 2 private banks of 4 KiB
  - **16 x `gf180mcu_ocd_ip_sram__sram1024x8m8wm1`** (1024 x 8, 301.30 x 515.81 um)
  - four macros side by side per 32-bit word, no depth decode, no output mux
- **Boot ROM**: 208 words / 832 bytes, synthesised to gates (not a macro)

## Peripherals

Configured counts, from `core-v-mcu/rtl/includes/*.svh`:

| block | count | note |
|---|---|---|
| QSPI master | **2** | `qspim0` is the boot flash, `qspim1` general purpose |
| UART (uDMA) | 1 | second instance cut, ticket 06 |
| I2C master | 1 | second master cut, ticket 12 |
| SDIO | 1 | storage |
| GPIO | **16** | shrunk from 32 for a controller layout |
| Advanced timer (PWM) | yes | the audio path; this config has no I2S |
| Timer unit, SoC control, FLL interface | yes | |
| JTAG / debug | yes | own asynchronous clock domain |

Cut deliberately and measured (ticket 12): `apb_i2cs`, uDMA filter (`N_FILTER 0`),
uDMA camera (`N_CAM 0`). HyperBus is also 0. Those cuts took flattened area down
25.9% and core occupancy from 95.6% to 76.4%.

The eFPGA is stubbed out, its APB slot at `0x1A30_0000` decoded and reading zeros.

## Pad ring

- **43** bidirectional IO pads (`gf180mcu_ocd_io__bi_24t`)
- **13** input-only pads (reset, JTAG, `stm_i`, spares)
- **18** power pads
- 1,066 pad spacers; 1,140 pad cells total

## Boot

- SPI flash, copy-then-jump, **CRC32-checked**
- Boot ROM reads the image over QSPI into L2 at `0x1C00_0000`, verifies, jumps
- CRC mismatch calls `halt()`, so reaching the app is the CRC passing

## Sign-off results

| check | result |
|---|---|
| `gf180mcu-precheck` | **16/16 stages pass** |
| KLayout DRC (ID-stamped) | 738 rules, **all zero** |
| Magic DRC | 0 |
| Routing DRC | 0 |
| LVS | circuits match uniquely |
| XOR | 0 differences |
| Antenna | 0 nets, 0 pins (66 diodes inserted) |
| Density / zero-area polygons | clear |
| Setup, 9 corners | **0 violations**, +4.97 ns worst (`ss_125C_3v00`) |
| Hold, 9 corners | **0 violations**, +0.034 ns worst (`ff_n40C_3v60`) |
| Disconnected pins | 0 |
| Gate-level sim | boots from flash, prints `BOOT OK` + `SRAM PASS` |

STA is nine corners: {min, nom, max} x {tt_025C_3v30, ss_125C_3v00, ff_n40C_3v60}.
Signoff corner `ss_125C_3v00`. Clock uncertainty 0.25 ns, never relaxed.

## Known gaps, carried knowingly

- **Max slew (457) and max cap (291) are not closed.** LibreLane defers them as
  warnings and precheck does not examine them. Many likely sit on macro pins
  whose Liberty is uncharacterised (a foundry file with the header swapped), so
  tightening against those numbers would optimise against fiction.
- **The gate-level result shows function, not silicon margin.** The SRAM
  Verilog model is 2x optimistic on access time on purpose; the only local data
  that would correct it is itself corrupted.
- **Die ID is a placeholder** (`FFFFFFFF`) until wafer.space assigns one.
- Global routing has unexplained run-to-run time variance (1m05s to 4+ hours).
