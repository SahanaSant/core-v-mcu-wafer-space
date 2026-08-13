# Write the boot ROM: gf180_bootrom.sv, sw/bootrom, and the generator script

Type: task
Status: open
Blocked by: none

## Question

Ticket 04 settled the architecture: SPI-flash boot only, single-SPI, no ROM fallback branch,
CRC32-checked before jump, JTAG-only recovery on failure, full 16 KiB of L2 available to the
application. That answer estimated a 2 KiB ROM; this ticket builds the real thing and measures
it, per this map's standing rule that a ticket resolves when the thing works and is measured,
not when it's been decided.

Scope:

- `sw/bootrom/`: `crt0.S`, a `main.c` that brings up the uDMA QSPI master in single-SPI mode,
  reads a header (image size + CRC32) plus the image from a fixed flash offset, streams it into
  L2 at `0x1C00_0000` while accumulating CRC32, checks it, and jumps on success or halts and
  spins on failure. No I2C or UART code (`I2CProtocol.c`, `uartProtocol.c`, `hal_apb_i2cs.c` are
  not needed and should not be carried over from `a2_boot/`).
- `gen_bootrom.py` (or similar): compiles `sw/bootrom/`, and converts the resulting binary into
  the synthesizable body of `gf180_bootrom.sv` — a literal case statement or array, not
  `$readmemh`, matching how `pad_control.sv` is already generated from `util/ioscript.py`.
- `rtl/gf180mcu/gf180_bootrom.sv`: the wrapper module (port list, addressing) that includes or
  invokes the generated content, replacing the black box `make elaborate` currently reports.
- Which RISC-V toolchain builds it, and whether it's already in the container, needs checking
  rather than assuming.

## Definition of done

`gf180_bootrom.sv` exists, is instantiated, and `make elaborate` no longer lists it as a black
box (one line left: `apb_pll` from ticket 05). `make area` re-run and the actual ROM area quoted
against ticket 04's 2 KiB estimate. The ROM boots a trivial image (does not need to be the
hello-world UART application) far enough to prove the CRC-and-jump path works, ideally under the
Icarus Verilog setup ticket 16 pinned, though full gate-level sim harness integration is not
this ticket's job.

## Answer

<!-- filled on resolution -->
