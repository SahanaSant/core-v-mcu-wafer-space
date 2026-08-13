# Boot architecture: how does the chip fetch its first instruction?

Type: grilling
Status: open
Blocked by: none

## Question

Upstream's `a2_bootrom.sv` initialises itself with `$readmemh("mem_init/boot.mem")` over an
11-bit address space. That does not synthesise. Something has to replace it, and the choice
determines whether a `sw/` directory exists at all, how much L2 is reserved, and how
recoverable a software bug is after tapeout.

The realistic options:

- **Synthesised ROM as standard cells.** Simple and self-contained. Costs area, is fixed
  forever at tapeout, and a bug in it can brick every die.
- **JTAG load into L2.** No ROM at all. Unbrickable, and the JTAG pads are already in the
  budget. Requires a debugger attached at every single boot, which makes standalone demos
  impossible.
- **SPI flash boot.** Upstream already has `bootsel_i` and a uDMA SPI master. Field-updatable.
  Costs four pads that ticket 06 is already short of, and still needs a small ROM to hold the
  loader.
- **Hybrid.** A minimal synthesised ROM that samples `bootsel_i` and jumps to either the SPI
  loader or a JTAG wait loop. Most flexible, most work, and the ROM is still fixed.

Secondary questions this decision drags in: does the boot code live in this repo or the
fork, how is it built (which RISC-V toolchain, and is it in the container), and how much L2
does the boot process need to reserve.

## Definition of done

A named architecture, with the pad cost written down so ticket 06 can budget for it, and the
ROM size estimated so ticket 11 can budget area for it. If the answer implies a `sw/`
directory, sketch its contents and build entry point.

## Answer

<!-- filled on resolution -->
