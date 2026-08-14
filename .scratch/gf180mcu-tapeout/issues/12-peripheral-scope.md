# Which peripherals survive?

Type: grilling
Status: resolved
Blocked by: 10

## Question

The uDMA subsystem carries UART, SPI, I2C, I2S, camera and SDIO interfaces, alongside GPIO,
PWM, timers, the event unit, the APB debug interface and the I2C slave. The full set will not
fit alongside the memory, and every peripheral kept is memory given up.

Cut with the numbers from ticket 10's per-module breakdown, not with intuition.

One number is already in. Ticket 03's elaboration found the design's **only two inferred
memories are both inside the I2C slave**: `FIFO_sync_256x8_apb_to_i2c` and
`FIFO_sync_256x8_i2c_to_apb`, 4,096 memory bits between them, with no macro behind them. At
256 bytes each they synthesise to roughly 2,048 flip-flops plus decoding, in a peripheral
that nothing in the bring-up plan uses and that ticket 06 already lists as competing for pads
it cannot have. It is the cheapest cut on the table. Note also that `apb_i2cs` is where the
one upstream source patch this port needed had to go (see ticket 03), and that its
`i2c_peripheral_interface.v` has a second, uncaught bug a few lines below the patched one:
the `scl_cnt` branch increments `sda_cnt`, so `scl_cnt` never advances.

**Ticket 11 turned the `apb_i2cs` cut from the cheapest option into a precondition.** The
committed memory configuration is sixteen SRAM macros at about 2.79 mm2 of floorplan, which
against ticket 10's 9.76 mm2 of placed logic puts the core at **97% occupancy** on the template's
35% density. `apb_i2cs` at 11.3% of cell area is worth about 1.10 mm2 placed, taking that to 89%.
So this peripheral is not on the table any more, and the question narrows to what else goes with
it. Resolving this ticket by keeping the I2C slave means reopening ticket 11.

Constraints on the answer:

- UART is not negotiable. It is the only practical bring-up and observability path, and it is
  the fourth test in `sim/README.md` for exactly that reason.
- JTAG and the debug unit are not negotiable either, for the same reason, and ticket 04 may
  make JTAG the boot path.
- SPI depends on ticket 04. If the answer there is flash boot, the SPI master stays.
- Every peripheral removed frees pads, which feeds back into ticket 06. Resolve the two
  together if the ordering allows.
- Removing a peripheral means removing it from `perdef.json`, the APB decode and the memory
  map, not just leaving it unconnected. A synthesised-but-unused block still costs area.

## Definition of done

A kept list and a removed list, each with the area recovered, and the resulting pad
allocation handed to ticket 06. The design still elaborates and the memory map is consistent.

## Answer

Grilled against a game-console target (the only concrete application this map has committed
to), which reframed several cuts: PWM survives because it's the audio path (this uDMA
configuration has no I2S at all, `N_I2SC=0` upstream, never something this ticket removed), SDIO
and a second SPI master survive for storage and external sensors, GPIO is sized for a
controller's buttons rather than upstream's full 32.

**Cut, built and measured:**

- `apb_i2cs` (I2C slave) — ticket 11's precondition, confirmed here. Removed entirely: the
  instantiation, its APB decode slot (`periph_bus_wrap`'s `NB_MASTER` 11→10, re-indexed), its
  event bit, and its 3 `apbio` pins tied off. **533,232 um2** at ticket 19's baseline.
- uDMA filter (`N_FILTER` 1→0) — no camera or I2S source left to feed it. **268,225 um2.**
- uDMA camera (`N_CAM` 1→0) — no sensor on this map's destination. **79,367 um2.**

**Kept, unchanged:**

- Both SPI masters (`N_QSPIM=2`) — boot flash (ticket 04) plus external sensors.
- Both UART channels (`N_UART=2`).
- SDIO (`N_SDIO=1`) — general storage flexibility.
- `apb_adv_timer` (PWM) — the console's audio/rumble/LED output. Whole-block keep; how many of
  its 16 channels reach pads is ticket 06's call, not an area question.
- `apb_timer_unit` — system tick.
- `soc_event_generator` — turned out not to be a real decision: it's the interrupt/event
  aggregator every kept peripheral (uDMA, timers, debug) depends on to signal the CPU. Flagged
  as fixed infrastructure rather than put to a vote.
- `apb_soc_ctrl`, `periph_bus_wrap`, debug module/`dmi_jtag`, `i_udmacore` — fixed
  infrastructure.

**Decided but NOT implemented here, handed to ticket 06 instead:**

- Second uDMA I2C master cut (`N_I2CM` 2→1, keep `i2c_gen[0]`).
- GPIO width cut (`N_GPIO` 32→16, sized for a d-pad/buttons plus a handful spare).

Both looked like this ticket's job but turned out to be pad decisions, not area ones, discovered
the hard way: reducing either shifts `apbio`/`perio` bit positions that `pad_control.sv`'s
generated mux table hardcodes as literal indices against the checked-in (Nexys-board) pin
table. Confirmed empirically — sanitizing `nexys-pin-table.csv`'s two `i2cm1` references and
regenerating `pulp_peripheral_defines.svh` with `N_I2CM=1` elaborates cleanly on its own, but
the *unregenerated* `pad_control.sv` then fails with out-of-range and undefined-macro errors.
`N_GPIO` has the identical exposure (`pad_control.sv` line 129 onward indexes `apbio_in_o[0..50]`
literally). Implementing either here would silently desync the pad multiplexer rather than
actually shrink it; regenerating `pad_control.sv`/`safe_domain.sv` against a real GF180
`perdef.json` is exactly ticket 06's job, so both numbers are handed to it as decided inputs
instead. Cutting `apb_i2cs`, filter and camera needed no such regeneration: `apb_i2cs`'s 3
`apbio` pins are tied off in place without changing the bus width, and filter/camera have zero
`perio` footprint (confirmed from the RTL: filter is pure L2 DMA, no pad-facing signals; the
`PERIO_CAM0_*` positions are pre-reserved dummy slots regardless of instance count, so `N_CAM`
1→0 doesn't shift anything).

**One latent upstream bug found and patched.** Cutting `N_FILTER` to 0 broke
`udma_rx_channels.sv`/`udma_tx_channels.sv`: both unconditionally part-select the "ext channel"
slice of a few internal buses as `[N_CHANNELS-1:N_LIN_CHANNELS]`, which is a reversed, invalid
range rather than an empty one once `N_EXT_CHANNELS` (== `N_FILTER`) is 0. No upstream
configuration ever sets `N_FILTER=0`, so this was never hit before. Fixed with a
`generate if (N_EXT_CHANNELS > 0)` guard around the four affected assigns, in both files.

**Measured result.** `make elaborate` passes, same two black boxes as before (`a2_bootrom`,
`apb_pll`). `make area`:

| pass | cells | area (um2) | vs. ticket 19 baseline |
| --- | ---: | ---: | ---: |
| flattened | 89,056 | 2,481,680 | −25,188 cells, −867,528 um2 (−25.9%) |
| hierarchical | 142,011 | 3,698,005 | — |

`soc_peripherals` fell from 2,674,818 to 1,749,844 um2 (−924,974). `udma_subsystem` fell from
1,371,087 to 984,455 um2 (−386,632) — more than filter+camera's own 347,592 um2, because
`i_udmacore` itself shrank 38,403 um2 once the ext-channel arbitration logic those two fed had
nothing left to arbitrate.

**This changes the schedule-viability picture the map has been carrying since ticket 10.**
Occupancy at the template's 35% density drops from ticket 19's 95.6% to **76.4%** — 3.04 mm2
free against 0.57 mm2 before. The chip no longer looks area-critical; ticket 12's cuts alone did
more for the budget than ticket 11's memory-side optimisation did. This doesn't touch the
pad-count motivation for the two ticket-06-deferred cuts (GPIO/I2C-master reduction was never
about area, `apb_gpiov2` is 61,171 um2, a rounding error in a 3.7M um2 design), and it doesn't
touch ticket 22's timing finding, which is a separate and still-live risk to the December date.

Pad allocation handed to ticket 06: `apb_i2cs`'s 3 `apbio` pins are gone from the functional
design (not yet from `N_APBIO`'s declared width). `N_GPIO=16` and `N_I2CM=1` are decided,
unimplemented pad-frame inputs.
