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

Ticket 11 added three constraints and killed one option that was never real.

**Every upstream boot address stops existing.** L2 is now 16 KiB contiguous from `0x1C00_0000`:
private bank 0 to `0x1C00_1000`, private bank 1 to `0x1C00_2000`, interleaved TCDM to
`0x1C00_4000`. `a2_boot/main.c` jumps to `0x1C00_8080` on hardware and `0x1C00_0880` under
Verilator, and `a2_boot/core-v-mcu2-rom.ld` puts the bootloader's own RAM at `0x1C07_C000`, which
was 448 KiB into a 512 KiB TCDM. All three have to move, along with `boot_code/link.ld`'s
`ORIGIN = 0x1C000000, LENGTH = 0x4000`. This is not a consequence of any answer here; it is true
already.

**There is no execute-in-place path.** `docs/porting-analysis.md:174` offers "programs must fit
in 16 KiB or execute in place from SPI flash", and the second half describes hardware that does
not exist: the uDMA QSPI is a DMA engine with a register interface, not a memory window, and the
AXI plug is commented out at `soc_interconnect_wrap.sv:93`. Flash boot means copying an image
into SRAM and jumping to it, so external flash changes how code arrives and not how much SRAM the
chip needs. An XIP controller would be new hardware and is not ticketed.

**The bank split gives this ticket something to use.** Ticket 11's recommended arrangement is
bootloader scratch in the interleaved half and the application image in the private half, which
puts them behind different crossbars and makes it structurally impossible for the loader to
overwrite the image it just copied in.

## Definition of done

A named architecture, with the pad cost written down so ticket 06 can budget for it, and the
ROM size estimated so ticket 11 can budget area for it. If the answer implies a `sw/`
directory, sketch its contents and build entry point.

## Answer

<!-- filled on resolution -->
