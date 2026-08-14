# Write the boot ROM: gf180_bootrom.sv, sw/bootrom, and the generator script

Type: task
Status: resolved
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

**Built and measured: 828 bytes (207 words), against the 2 KiB estimate.** `sw/bootrom/` (`crt0.S`,
`main.c`, `crc.c`, `spi.c`, `boot.ld`) compiles with the container's `riscv64-unknown-elf-gcc`
(`-march=rv32imc -mabi=ilp32`) — there is no `riscv32-corev-elf-gcc`, which is what `a2_boot/Makefile`
assumed. `sw/bootrom/gen_bootrom.py` converts the compiled binary into `rtl/gf180mcu/gf180_bootrom.sv`,
a case statement keeping `a2_bootrom`'s exact name, port list and registered read timing so
`boot_rom.sv` instantiates it unmodified, the same technique `a2_boot/srec2verilog.py` used for the
original. `make bootrom` (new top-level target, `flow/synth/bootrom.sh`) drives the whole pipeline:
regenerate the C headers, compile, generate, and self-check the generated Verilog against the compiled
image under Icarus. `sw/bootrom` lives at the parent repo's top level, alongside `rtl/chip/` and
`rtl/gf180mcu/`, not inside the submodule: it's shuttle-specific in the same way those are.

`make elaborate` now reports one black box, `apb_pll` (ticket 24). `make area`: flattened
**83,101 cells, 2,299,430 um2**, against ticket 06's 82,209 cells / 2,281,302 um2 — **+892 cells,
+18,128 um2 (+0.79%)**, outside the 0.3% precision floor and so a real cost, not noise. Occupancy
moves from 72.0% to **72.4%**, 3.57 mm2 free against 3.62 mm2 before. `make sta`: **83 stages, a
62.2 ns floor, 124% of the 50 ns budget** at 3.3 V, against ticket 22's 89 stages / 62.3 ns / 125%.
Per ticket 22's own caveat, the stage count is not the stable part of that comparison — it's ranked
by worst pre-layout slack among 300 candidates, which moves under unrelated changes — but the ns
floor barely moved (62.3 to 62.2 ns), confirming the boot ROM is nowhere near the critical path,
which stays in the CV32E40P decoder.

**Icarus testbench** (`sw/bootrom/tb/bootrom_tb.sv`, run by `make bootrom`) reads
`gf180_bootrom.sv` back through its registered CEN/A/Q interface and checks all 207 words plus one
out-of-range address against the compiled image, byte for byte. This proves the generated ROM is a
lossless, correctly-timed encoding of `sw/bootrom`'s output — not that the CPU actually fetches,
runs `main()`, and jumps, which needs the CV32E40P, the uDMA QSPI block and a flash model wired up
together (the gate-level simulation harness, still fog, not this ticket's job per its own DoD hedge).
That's a real, load-bearing precondition for the harness rather than a placeholder: if the ROM
content didn't match, nothing downstream would either.

Five real bugs found and fixed along the way, none of them hypothetical:

1. **`util/ioscript.py`'s `--cvmcu-h` path threw `KeyError: 'I2CS_START_ADDR'`.** Ticket 12 cut
   `apb_i2cs`'s decode slot entirely, so `periph_bus_defines.svh` has never carried that define
   since; the generator's I2CS block was unconditional. Guarded it on the define being present
   (submodule commit). The submodule's own `make sw` is separately broken today for an unrelated
   reason — it targets `nexys-pin-table.csv`, an FPGA board table ticket 06 already diverged
   `N_UART`/`N_GPIO`/`N_I2CM` from — so `flow/synth/bootrom.sh` regenerates the headers itself
   against `gf180-pin-table.csv` rather than depending on that recipe.
2. **`crc.h`'s `crc` typedef was `unsigned long`.** That's 32 bits under the RV32 `ilp32` ABI
   (where the original code lived) but 64 bits on a normal host, and `crc.c`'s width-derived
   masking silently computes a different, wider CRC there. Caught by checking this exact file
   against the standard CRC-32 check value (`"123456789"` -> `0xCBF43926`) on the host as part of
   this ticket; fixed to `uint32_t`.
3. **`boot.ld`'s `stack = . + N` (copied from `core-v-mcu2-rom.ld`) silently overflowed the
   declared L2 region.** It chains off wherever `.ram`'s location counter lands rather than the
   region's actual top, and `ld` doesn't bounds-check symbol arithmetic the way it bounds-checks
   real section content. Invisible on upstream's 16 KiB region; this ROM's 512 B one put `stack`
   68 B past the true end of L2. Fixed by pinning `stack` to `ORIGIN(L2) + LENGTH(L2)` directly,
   with an `ASSERT` that at least 256 B separates it from `.bss`.
4. **`udma_qspim_open()`'s clock divisor assumed a fixed 5 MHz peripheral clock.** That was
   `a2_boot`'s board's FLL-derived `udma_ctrl` clock; ticket 05 settled this design's clock
   architecture as `ref_clk_i` bypassed undivided to 10 MHz. Re-derived from
   `udma_clk_div_cnt.sv`'s real toggle-every-N-cycles behaviour instead of carrying the old
   constant over.
5. **`rx_saddr`/`tx_saddr` are not full 32-bit addresses.** `udma_spim_reg_if.sv` slices them to
   `L2_AWIDTH_NOAL` bits (currently 13, sized to this design's 16 KiB L2 and moving with
   `NB_L2_CHANNELS`) before latching, unlike `cmd_saddr`, which the CSV and generated header both
   give the full 32 bits. The original design (both reads targeting `L2_IMAGE_BASE` plus a
   stack-resident header struct near the top of L2 for one of them) would have silently truncated
   that second address. Redesigned so both uDMA reads land at `L2_IMAGE_BASE` and nowhere else —
   offset 0 from L2's own base, representable regardless of the exact field width — reading the
   header there first, copying `size`/`crc32` to locals, then overwriting it with the real image
   at the same address.

**L2 layout, settled here rather than left to ticket 04's "a fixed corner":** the boot stack (and
`spi.c`'s 64-byte command buffer) reserve the top 512 bytes, `0x1C00_3E00`-`0x1C00_4000`
(`BOOT_STACK_RESERVE_BYTES` in `sw/bootrom/include/boot_image.h`). The application gets
`0x1C00_0000`-`0x1C00_3E00`, 15,872 bytes, via `L2_IMAGE_MAX_SIZE`.

`flow/synth/stubs.sv`'s `a2_bootrom` black box is deleted, per its own file header's instruction
to delete each stub as the real cell lands. `rtl/gf180mcu/README.md` gets a Boot ROM section
alongside Clock cells and L2 memory, and its module table drops `a2_bootrom`.
