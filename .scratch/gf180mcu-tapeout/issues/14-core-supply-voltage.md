# Core supply voltage: 3.3 V or 5.0 V?

Type: grilling
Status: open
Blocked by: none

## Question

Surfaced by ticket 07, which found that the denser OCD SRAM macros have **no 5.0 V corner at
all**. They are characterised only at 1.8 V and 3.3 V.

Ticket 01 confirmed against the pinned PDK that `gf180mcu_fd_sc_mcu7t5v0`, despite the `5v0`
in its name, ships fifteen Liberty corners across three voltage families: 5.0 V, 3.3 V (3v00,
3v30, 3v60) and 1.8 V (1v62, 1v80, 1v98). The foundry SRAM carries the same three families,
so it follows the core supply either way. `gf180mcu_fd_io` is characterised at 2v50, 3v30 and
5v00. The `5v0` is the oxide, not the only supported supply, so both options are live.

The choice is straightforward to state and consequential to get wrong:

- **Core at 3.3 V.** The OCD SRAM drops in with a matched supply, no level shifters at the
  memory boundary, and 0.155 mm²/KiB instead of 0.409. Standard cells run slower at 3.3 V
  than at 5.0 V, which eats into the 25 MHz target in ticket 05.
- **Core at 5.0 V.** Faster cells, and the foundry SRAM works natively. But the OCD macros
  become unusable without a level shifter on every SRAM interface, which costs area, costs
  timing, and adds a whole class of things to get wrong on a first tapeout.

This is a power architecture decision that reaches into the memory choice (ticket 11), the
frequency target (ticket 05) and the pad ring (ticket 06, since IO supplies and the core
supply need separate pads and the slot only has so many).

Also decide what the IO ring runs at, whether the design is single-supply or multi-supply,
and if multi-supply, where the domain crossings are and what shifts them.

Three things ticket 01 turned up that shape how the answer gets implemented:

- **3.3 V is an override, not a default.** The PDK's LibreLane config for `gf180mcuD`
  hardcodes `VDD_PIN_VOLTAGE 5.00` and builds `CELL_LIBS`, `STA_CORNERS` and `DEFAULT_CORNER`
  from the 5v00, 4v50 and 5v50 corners only. Choosing 3.3 V means overriding all four in
  `flow/config.yaml`, and nothing warns you if you change the supply and leave the corners.
- **A native 3.3 V standard cell library exists.** `gf180mcu_as_sc_mcu7t3v3` ships a LibreLane
  config already pinned to 3v30. It is a lead, not a recommendation: it is not built into the
  pinned PDK, and its config writes `::env(LIB)` where the current `gf180mcuD` config writes
  `::env(CELL_LIBS)`, which suggests nobody has run it under LibreLane 3.x. Deciding to use it
  would need a ticket of its own.
- **1.8 V is characterised too.** Probably not wanted on a first tapeout, but it exists, and
  the OCD SRAM is characterised there as well, so rule it out deliberately rather than by
  omission.

## Definition of done

A named core supply with the reasoning written down, a statement of whether the design is
single or multi supply, the power pad allocation, and confirmation from the pinned PDK that
the chosen standard-cell corner actually exists. Feeds tickets 05, 06 and 11.

## Answer

<!-- filled on resolution -->
