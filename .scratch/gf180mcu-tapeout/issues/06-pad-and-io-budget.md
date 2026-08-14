# Pad and IO budget: fit 57 signals into 56 pads

Type: grilling
Status: resolved
Blocked by: 02

## Question

A 1x1 slot provides 56 signal pads: 40 bidirectional, 14 input-only, 2 analog. Upstream needs
57. `core_v_mcu.sv` exposes `N_IO = 48` general-purpose pads plus `jtag_tck`, `jtag_tdi`,
`jtag_tdo`, `jtag_tms`, `jtag_trst`, `ref_clk_i`, `rstn_i`, `bootsel_i` and `stm_i`.

The proposal in `rtl/chip/README.md` is to drop `N_IO` from 48 to 40 and put the eight
remaining signals on input-only pads, with `jtag_tdo_o` sharing a bidirectional pad as an
output. That leaves `N_APBIO` overcommitted: GPIO(32) plus PWM(16) plus I2CS(3) is 51
functions competing for 40 pads.

So the real question is which functions lose their multiplexer entries. That is a product
decision, not a mechanical one, and it interacts with two other tickets: ticket 04 is resolved —
net **+3** pads (4 new QSPI pins for SPI flash boot, 1 freed by dropping `bootsel_i`), well
inside the 8-pad slack this plan already has. Ticket 12 is also resolved, and most of its
peripheral cuts (`apb_i2cs`, uDMA filter, uDMA camera) didn't need `N_APBIO`/pad-frame surgery
to land, since they either had zero `perio` footprint or tied off in place — **except two
decided-but-unimplemented inputs handed to this ticket specifically**: `N_GPIO` 32→16 (kept for
a game-console d-pad/buttons, not upstream's full GPIO count) and `N_I2CM` 2→1 (the second uDMA
I2C master cut). Both stalled on ticket 12's own attempt to implement them, because doing so
shifts `apbio`/`perio` bit positions that the checked-in (Nexys-board) `pad_control.sv` hardcodes
as literal indices — exactly the kind of regeneration this ticket exists to do, now against a
real GF180 `perdef.json` instead. With those two folded in, `N_APBIO` becomes GPIO(16) +
PWM(16) + I2CS(0) = **32**, comfortably inside 40 rather than 11 over it, so this ticket may no
longer need to cut anything itself, only assign.

`pad_control.sv` and `safe_domain.sv` are generated files. The answer has to be expressed as
a modified `perdef.json` with the multiplexer regenerated through upstream's
`util/ioscript.py`. Hand-edited pad tables will drift from the software headers `make sw`
produces and will not be accepted upstream.

## Definition of done

A `perdef.json` on the fork that describes 40 bidirectional and 8 input-only signal pads,
with `pad_control.sv` and `safe_domain.sv` regenerated from it, `N_IO` and `N_APBIO` updated
in `pulp_soc_defines.svh`, and the design still elaborating. The answer records which
functions were cut and why.

## Answer

**39 of 40 general IO pins assigned, one spare. `N_APBIO` drops to 24 (gpio 16 + pwm 8).** Grilled
live: PWM channels (a real, previously-unconsidered lever) came out at 8 of 16, which forced UART
down to one instance and both the second SPI master and SDIO down to their narrowest useful mode
to fit the remainder. `N_IO` 48→40, `N_APBIO` 51→24, `N_GPIO` 32→16 (ticket 12), `N_I2CM` 2→1
(ticket 12), `N_UART` 2→1 (new cut, this ticket).

Two facts, found rather than assumed, shaped the implementation:

1. **The IO library has exactly three pad types**: `bi_t`/`bi_24t` (bidirectional, the only ones
   that can drive output), `in_c`/`in_s` (input-only) and `asig_5p0` (analog, not usable as
   digital output). Every function that ever drives out — GPIO, PWM, I2C, UART tx, SPI, SDIO —
   has to live in the 40-wide bidirectional array; there is nowhere else for it to go.
2. **Only some of the pad-forced cuts save real silicon.** `apb_adv_timer` (PWM), `udma_spim_top`
   (QSPI) and `udma_sdio_top` are all fixed-shape upstream IP — hardcoded port widths, no
   parameter controls channel/data-line count — so bonding fewer of their pins to pads costs
   nothing in area; the unbonded lines stay internally driven and simply unconnected. `N_UART` is
   different: it genuinely instantiates a separate `udma_uart` per count via a generate-for loop,
   so a never-bonded second instance is silicon with no way to ever reach it, and cutting it to
   one is a real area saving, not just a pad one. That distinction is why this ticket cuts
   `N_UART` but only re-wires PWM's bonding.

Pin assignment (`gf180-pin-table.csv`, io\_num 0-39, each function fixed to `pad_mux=0` with no
alternates offered — a fixed ASIC doesn't need the runtime remapping flexibility a generic FPGA
dev-board pin table exists for):

| io_num | function | io_num | function |
| --- | --- | --- | --- |
| 0-15 | GPIO 0-15 | 28-31 | qspim1 (storage/sensors), single-line: clk/csn0/data0/data1 |
| 16-23 | PWM, timer0+timer1 (8 of 16 channels) | 32-34 | sdio0, 1-bit: clk/cmd/data0 |
| 24-25 | i2cm0: scl/sda | 35-38 | qspim0 (boot flash, ticket 04), single-line, fixed mux slot |
| 26-27 | uart0: tx/rx | 39 | spare |

`jtag_tck/tdi/tdo/tms/trst`, `ref_clk`, `rstn` and `stm` stay separate `core_v_mcu.sv` ports
outside this array, unchanged from upstream — they never occupied `pad_mux` table entries even in
the stock Nexys table; that table's `io_num` column for them existed only for Xilinx XDC
generation, which this build doesn't invoke. `bootsel_i` is fully removed instead: the port, the
`perdef.json` sysio entry, `REG_BOOTSEL`, `apb_soc_ctrl`'s `r_bootsel` register, and the
`dmactive_i` threading that only ever fed that register's readback (now orphaned three files deep,
so it comes out too).

`perdef.json` and `gf180-pin-table.csv` regenerated `pad_control.sv` and
`pulp_peripheral_defines.svh` through `util/ioscript.py`, unchanged. `safe_domain.sv` turned out
**not** to be a generated file despite the map's Notes and `rtl/chip/README.md` both saying so —
it only references `N_APBIO`/`N_GPIO` parametrically, no literal indices, so it needed no
regeneration and the diff confirms it (untouched).

Elaboration surfaced two real bugs the resize exposed, both upstream, both fixed:

- `apb_gpio.sv`'s register *read* path (`REG_OUT0`/`REG_PIN0`) hardcoded `PRDATA[31:0] <=
  r_gpio_out[31:0]`, out of range once `N_GPIO` drops under 32. The *write* path already had an
  `N_GPIO > 32` guard; the read path didn't. Mirrored the same guard.
- `core_v_mcu.sv` carried upstream's eFPGA test-IO overlay: `stm_i`-gated logic stealing specific
  `io_out_o`/`io_oe_o`/`io_in_i` bit ranges for eFPGA scan-test access, hand-picked against
  `N_IO=48` (e.g. `io_out_o[`N_IO-1:43]`, reversed once `N_IO=40`). The eFPGA is gone (ticket 03),
  so `testio_i`/`testio_o` have no real consumer or driver left. Simplified to what the block
  actually still does: `stm_i` forcing every pad to a safe zero state, generalized across the full
  bus rather than eFPGA-specific sub-ranges.

`make elaborate` passes clean, same two black boxes as before (`a2_bootrom`, `apb_pll`). **Measured,
not estimated**: flattened area fell from ticket 12's 89,056 cells / 2,481,680 um2 to **82,209
cells / 2,281,302 um2** (−8.1%, the `N_UART` cut's real saving), and core occupancy at 35% density
fell from 76.4% to **72.0%**, 3.62 mm2 free against 3.04 mm2 before.

DoD note: the `perdef.json`/pin-table pair describes 40 bidirectional pins (all of `N_IO`) and,
separately, the 8 sysio-class signals (7 pure-input plus `jtag_tdo`) that were always outside that
array and stay untouched — matching the ticket's original framing once "8 input-only signal pads"
is read as that fixed sysio set rather than something this ticket needed to construct.

Submodule commit `63537c4`.
