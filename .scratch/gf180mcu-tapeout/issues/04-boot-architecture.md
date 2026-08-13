# Boot architecture: how does the chip fetch its first instruction?

Type: grilling
Status: resolved
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

**SPI-flash boot only, single-SPI, CRC-checked, no ROM fallback branch, JTAG-only recovery.**

Grounding facts that shaped this, found rather than decided: the CPU always fetches from
`gf180_bootrom.sv` at the existing `0x1A00_0080` reset vector (`apb_soc_ctrl.sv`'s
`r_bootaddr` reset value; there is no hardware boot-address mux), so some ROM is unavoidable
under every option. `docs/porting-analysis.md` and ticket 11 had already killed
execute-in-place (`soc_interconnect_wrap.sv:93`'s AXI plug is commented out, and the uDMA
QSPI block is a DMA engine with a register interface, not a memory window), so SPI flash was
never going to mean the core executing directly out of flash. And the JTAG debug module
(`pulp_platform_riscv_dbg`, `dm_top.sv` / `dmi_jtag.sv`) is unconditionally present and can
halt the core and write L2 directly over the system bus, independent of anything the boot
ROM does or doesn't cooperate with.

Decisions, in the order they were made:

1. **SPI flash boot, copy-then-jump via uDMA QSPI, no XIP.** Matches upstream's own
   mechanism and needs no new hardware; an XIP controller would be new RTL and new scope not
   on this map.
2. **Single SPI mode**, not quad: 4 pins (`spi_clk`, `spi_csn0`, `spi_sdo0`, `spi_sdi`)
   against 6, simpler ROM code, and boot-time throughput does not matter enough on a one-shot
   image copy to justify quad flash and two more pads.
3. **No bootsel-driven ROM fallback.** Upstream's dual path (SPI flash or wait for an I2C
   host) is dropped entirely; the ROM always loads from flash. This decouples the boot ROM
   from ticket 12's `apb_i2cs` outcome, and makes the JTAG debug module the sole recovery
   path — reachable regardless of what's in ROM, so there was nothing left for a ROM-level
   fallback to add.
4. **`bootsel_i` is dropped**, pad and all, along with the `apb_soc_ctrl` `REG_BOOTSEL`
   readback: nothing reads it once the ROM fallback is gone.
5. **CRC32-checked before jump.** The ROM streams the flash image straight into its final L2
   address while accumulating a CRC32, checks it against a header value, and only then jumps.
   On failure it halts and spins; the debug module stays reachable over JTAG in that state, so
   recovery is "attach JTAG, push a good image into L2, resume," with no ROM-level retry or
   fallback logic needed.
6. **Full 16 KiB of L2 available to the application.** The ROM never becomes L2-resident (it
   executes from ROM throughout) and needs only a few tens of bytes of stack, so ticket 11's
   private/interleaved split no longer has to guard against a resident loader overwriting the
   image — that risk doesn't exist under this architecture. The application's linker script
   gets the full `0x1C00_0000`–`0x1C00_4000` span minus a fixed corner reserved for the ROM's
   boot-time stack.

**Pad cost for ticket 06:** net **+3** against its plan — 4 new QSPI pins (`spi_clk`,
`spi_csn0`, `spi_sdo0`, `spi_sdi`), minus 1 freed (`bootsel_i`). Comfortably inside the 8-pad
slack ticket 06's own plan already has (48 of 56 pads used before this ticket spends
anything).

**ROM size estimate for ticket 11:** **2 KiB**, matching `docs/porting-analysis.md`'s own
"shrink to 1–2 KiB" target for a minimal loader — down from upstream's 8 KiB. Comparable
single-SPI copy-and-jump loaders with a CRC32 check run a few hundred instructions; this
figure is an estimate for area budgeting, not yet measured.

**`gf180_bootrom.sv` is a generated file**, in the same style `pad_control.sv` already is
from `util/ioscript.py`: a script compiles the boot loader and converts the resulting binary
into synthesizable Verilog (a literal case statement / array, not `$readmemh`, which does not
synthesise). Writing that script, the ROM source, and measuring the real ROM area is now
[ticket 23](23-write-boot-rom.md).

**`sw/` directory implied:** a new `sw/bootrom/` — `crt0.S`, a trimmed `main.c` (QSPI init,
copy-with-CRC loop, jump; no `I2CProtocol.c`, `uartProtocol.c`, or `hal_apb_i2cs.c`, all of
which go away with the dropped I2C path), and `gen_bootrom.py` producing `gf180_bootrom.sv`
from the compiled image. The hello-world UART application the destination's gate-level sim
needs to boot and print is scoped separately, as part of the simulation harness (see the
map's "Gate-level simulation harness" fog entry), since it's really one of that harness's
test images rather than boot-architecture work.
