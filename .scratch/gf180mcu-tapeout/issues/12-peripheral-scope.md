# Which peripherals survive?

Type: grilling
Status: open
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

<!-- filled on resolution -->
