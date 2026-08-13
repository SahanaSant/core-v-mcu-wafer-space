# Which peripherals survive?

Type: grilling
Status: open
Blocked by: 10

## Question

The uDMA subsystem carries UART, SPI, I2C, I2S, camera and SDIO interfaces, alongside GPIO,
PWM, timers, the event unit, the APB debug interface and the I2C slave. The full set will not
fit alongside the memory, and every peripheral kept is memory given up.

Cut with the numbers from ticket 10's per-module breakdown, not with intuition.

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
