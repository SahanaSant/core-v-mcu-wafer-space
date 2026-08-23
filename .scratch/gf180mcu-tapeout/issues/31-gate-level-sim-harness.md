# Write the gate-level simulation harness: boot from flash, print over UART

Type: task
Status: claimed
Blocked by: none

## Question

The map's destination is explicit: a GDS that passes `gf180mcu-precheck`, *with gate-level
simulation showing the hardened netlist boots and prints over UART*. That harness has never
been written — `sim/` holds only `README.md`, `make sim`/`make sim-gl` both hard-require
`sim/Makefile` (`$(call require,...)`) which doesn't exist, and the map's own fog entry says
so explicitly. This ticket graduates that fog entry and builds the harness for real, not just
plans it — this map carries execution.

Ticket 16 already pinned the simulator (Icarus 14.0, UDP-capable, needed for the PDK's
`icgtp` clock-gate primitive) and ticket 04 already pinned the boot architecture (SPI-flash,
single-SPI, CRC32-checked, copy-then-jump, no XIP). Ticket 23 built the boot ROM against that
architecture and proved ROM-contents-equal-compiled-image under Icarus (`sw/bootrom/tb/bootrom_tb.sv`)
but explicitly stopped short of the CPU actually fetching and running it, calling that "the
gate-level simulation harness (map fog entry, not built by this ticket)". This ticket is that
harness.

Concretely, this needs:

- A minimal application image (new `sw/app/`, since ticket 04's fog note left this open and
  nothing else claims it) that runs from `L2_IMAGE_BASE` after the boot ROM jumps to it, and
  proves the four things `sim/README.md` already asks for: reset/clock reaching the core,
  a read-write-read walk across L2 (byte-enable-sensitive), having gotten there via a real
  boot (not a backdoor load), and a UART character out. Bundling all four into one boot image
  the flash model serves is more realistic than four separate harnesses and cheaper to build
  under tonight's deadline.
- A SPI flash behavioral model on the `qspim0` pads (`bidir_PAD[35:38]`: CLK/CSN0/DATA0/DATA1,
  confirmed from `core-v-mcu/rtl/core-v-mcu/top/pad_control.sv`) serving that image. Don't
  write a BFM from scratch: `core-v-mcu/tb/qspi_model/GD25Q128B.v` is already vendored in the
  submodule (a real GigaDevice behavioral model, `$readmemh`-loadable), unlike the Spansion VIP
  upstream's own `tb_pulp.sv` uses, which isn't present and isn't open. Confirm it actually
  answers a JEDEC single-line READ (0x03) the way `sw/bootrom/spi.c` issues it before trusting
  it end to end.
- A UART0 decoder on `bidir_PAD[26]` (TX, confirmed from the same pad_control.sv:
  `PERIO_UART0_TX` at mux position 0, the reset default, so no pad-mux setup should be needed
  in software) to check the printed bytes against an expected string.
- `sim/Makefile`, wired to what the root `Makefile` already assumes (`make -C /foss/designs/sim`
  and `... GL=1`), and a cocotb testbench seeded from the wafer.space project template's
  `cocotb/chip_top_tb.py` per this map's own "seed from the template" preference, adapted to
  this design's actual port names and macro/library set (`gf180mcu_ocd_io`,
  `gf180mcu_ocd_ip_sram__sram1024x8m8wm1`, not the template's foundry defaults).
- `make sim` (RTL, `flow/chip_top.sv`/`chip_core.sv` sources) should work standalone, without
  waiting on a hardened netlist. `make sim-gl` needs a real netlist:
  `flow/final/pnl/chip_top.pnl.v` already exists from a completed prior run (10 MHz-era, but
  that's fine for proving the harness itself works — rerun against ticket 29's 6 MHz netlist
  once that lands, the same way ticket 30 is re-running precheck).

Known caveat to carry forward, not fix here: `gf180mcu_ocd_ip_sram__sram1024x8m8wm1.v`'s
specify block is 2x optimistic on access time at 3.3 V, on purpose (ticket 20). A pass here
demonstrates function, not that real silicon meets `make sta`'s signed-off margin.

## Definition of done

`make sim-gl` runs to completion against a real hardened netlist and reports, in its own
output: reset released and the core clocked from `ref_clk_i`, a successful boot from the SPI
flash model (CRC check passing, not bypassed), an L2 read-write-read pattern check passing
across bank boundaries, and the expected string received on UART0 TX. `make sim` passes the
same shape of test at RTL level. If any of the four checks can't be made to pass tonight, the
ticket records exactly which, why, and what's real vs. stubbed — not a harness that reports
green without actually checking.

## Answer

<!-- filled on resolution -->

## Comments

**Claimed and in progress.** Building now: `sw/app/` (uart.c against
`core-v-mcu/rtl/udma/udma_uart/data/udma_uart_reg_defs.csv`'s TX_SADDR/TX_SIZE/TX_CFG/UART_SETUP
registers, following `sw/bootrom/spi.c`'s uDMA driver style), a flash-image builder producing
the 8-byte `boot_header_t` + binary that `sw/bootrom/main.c` already expects at flash offset 0,
and the cocotb harness itself. Working in parallel with ticket 29's routing retry and ticket
30's precheck dry run, since none of the three depend on each other finishing first.

## Comments (continued)

**Built and compiling/running as of this update; result not yet in.** Wrote, in order:
`sw/app/` (crt0.S, app.ld, main.c, uart.c, sram_test.c, Makefile), `sw/app/gen_flash_image.py`
(8-byte `boot_header_t` + image, CRC-32/ISO-HDLC via `zlib.crc32`, confirmed to match
`sw/bootrom/crc.c`'s algorithm from `crc.h`'s own header comment rather than assumed),
`flow/synth/app.sh` (mirrors `bootrom.sh`, adds `udma_uart_reg_defs.h` generation to the
existing header-regen loop), `sim/tb/tb_top.sv`, `sim/tb/uart_rx.sv`, `sim/cocotb/tb_top_tb.py`,
`sim/Makefile`.

Two real bugs found and fixed by actually trying to build, not just written and assumed
correct:

- `sw/app/app.ld` linked a byte-for-byte empty binary (`text=0 data=0 bss=0`):
  `-Wl,--gc-sections` needs a GC root, and using a from-scratch `-T app.ld` (rather than
  extending the default script) drops the toolchain's implicit `ENTRY(_start)` along with it.
  `sw/bootrom/boot.ld` never hit this because it anchors `_start` via `KEEP(*(.vectors))`
  instead. Fixed with an explicit `ENTRY(_start)` in `app.ld`; app is now 551 bytes.
  `sw/bootrom/main.c`'s `L2_IMAGE_MAX_SIZE` budget is 15,872 bytes, so there's no area pressure
  here at all.
- `sim/tb/tb_top.sv` failed to elaborate under Icarus: an inout port's actual has to support
  continuous assignment, so `GD25Q128B`'s `wp`/`hold` pins can't be tied directly to a bare
  `1'b1` literal, and `$write`/`$fflush` inside an `always_ff` block (rather than plain
  `always`) is flagged too. Fixed by tying `wp`/`hold` through intermediate wires and moving the
  UART byte dump to a plain `always` block.

Currently running the actual cocotb test against the existing (10 MHz-era, but functionally
identical for this purpose) `flow/final/pnl/chip_top.pnl.v`. Gate-level sim of a ~150K-instance
netlist under Icarus (an interpreted simulator) is expected to be slow compared to RTL — this
is normal, not a sign of a hang, and this run's own value is proving the harness mechanically
works before rerunning it against ticket 29's real 6 MHz netlist once that lands.

## Comments (measured the real slowdown, resized the test, still no clean run)

**Measured, not assumed: gate-level Icarus sim of this netlist runs at ~5-6us of simulated time
per real second.** That number came from watching attempt 3 run for 6+ minutes of wall clock
with no UART output yet, then confirming from timestamps that the container itself completed
independently around the same time my own `kill -TERM` on the vvp PID landed (a no-op — rootless
podman's PID namespace means the host-side PID doesn't map to anything inside the container), so
that attempt's FAIL result is contaminated by the kill's timing and doesn't count as a real
result either way. Response: cut `TIMEOUT_NS` 200,000,000 -> 20,000,000 and `SRAM_TEST_BYTES`
~15KiB -> 512 B (see `sw/app/main.c`'s and `sim/cocotb/tb_top_tb.py`'s own comments for the
arithmetic) to make the debug loop tractable — still enough to catch a byte-lane/depth-mux bug,
not a real coverage claim.

**One non-fatal `$display` warning seen once, not yet root-caused, judged low-risk rather than
fixed:** `GD25Q128B.v`'s internal `acdc_watch.s_watch2` timing checker printed `tCHSH condition
violated` at simulated t=2ns in one run. The checker guards itself with `if ($time != 0)`, and
this is delay-free (zero-delay) gate-level simulation, so a report at t=2ns is consistent with
a startup-time X-propagation artifact in the flash model's own timing-check logic rather than a
real SPI protocol violation from the boot ROM's side — but this has not been confirmed clean by
watching a full natural-completion run, only reasoned about. Revisit if a real run's UART output
ever looks wrong in a way this could explain.

**No clean, natural-completion run has happened yet — every attempt so far ended by being
killed, not by finishing.** The most recent (`sim-gl4`) was stopped (`podman stop -t 3
eloquent_shaw`) specifically to protect the concurrently-running `make harden` attempt during a
real host memory/swap exhaustion event (confirmed via `free -h` and an actual OOM-kill of an
unrelated process via `dmesg`), not because of anything wrong with the harness itself. As of this
update, host memory is still under real pressure from the live detailed-routing run (OpenROAD
alone holding ~5.6GB RSS, system down to ~300MB free / ~2GB swap free), so a retry is
deliberately being held off rather than risked — restarting a killed `make harden` from a
mid-detailed-routing checkpoint would cost far more than this ticket losing more time. Retry once
memory allows, ideally against ticket 29's real 6 MHz netlist rather than the 10 MHz one used so
far, since that will exist by the time memory frees up anyway.

## Comments (first natural-completion run: a timeout mid-boot, not a boot failure)

**The harness ran to its own natural end for the first time in this ticket's history, and
failed.** Every previous attempt was killed by hand or by memory pressure, so a FAIL that the
harness itself produced is new information rather than another contaminated result. Measured
rate over the whole run: **20,001,000 ns of simulated time in 2340 real seconds, 8547 ns/s** --
close to the ~5-6 us/s estimated earlier from a partial run, so that estimate holds.

**The failure is the 20 ms `TIMEOUT_NS` being too small, not the design failing to boot.** Zero
UART bytes were decoded across the whole run (`tb_top.sv` already dumps every decoded byte, so
silence here means nothing was ever printed, not that something was printed and mis-decoded).
The SRAM models' own "CEN is just reset, memory is operational" reports are what pin the real
timeline, and they split cleanly along the L2 address map: `SOC_MEM_MAP_PRIVATE_BANK0/1` are
0x1C00_0000 and 0x1C00_1000, `SOC_MEM_MAP_TCDM_START_ADDR` (the interleaved `CUTS`) is
0x1C00_2000, so `boot.ld`'s stack/.bss at 0x1C00_3E00 lives in the interleaved banks and
`app.ld`'s image base at 0x1C00_0000 lives in the private ones. The interleaved banks are first
touched at **3.155 ms** (the boot ROM getting as far as its own stack) and the private banks not
until **18.261 ms** (the first flash DMA landing in the image region), 1.74 ms before the
deadline. "BOOT OK\r\n" alone is 0.78 ms at 115200 baud, and the image read, the CRC32 and the
app's SRAM walk all still had to happen first, so the run was cut off mid-boot with no chance to
print.

**Two real defects found and fixed, both exposed by this run rather than guessed at:**

1. `tb_top_tb.py`'s assert message blamed the wrong file. "BOOT OK" is printed by
   `sw/app/main.c`, not `sw/bootrom/main.c`, so the message sent the next reader to the boot ROM
   for a symptom that covers the app not starting *or* the boot ROM halting *or* a plain
   timeout. Reworded to name all three and point at the evidence that distinguishes them.
2. `TIMEOUT_NS` raised 20,000,000 -> 100,000,000 (about 3.25 real hours at the measured rate).
   The old value's justification costed boot as an SPI read plus two prints and omitted both the
   ~15 ms the design spends before the first flash DMA lands and `crcSlow()`, which is a
   bit-at-a-time CRC32 over the whole image. The new arithmetic is written out in the file
   against this run's measured numbers.

**Still open, and the reason a flash-CS trace was added to `tb_top.sv`:** the ~15 ms between the
boot ROM's first stack access (3.155 ms) and the first flash DMA (18.261 ms) is not explained by
anything found in the source. `udma_flash_reset_enable()`/`udma_flash_reset_memory()` contain no
delay loops and are fire-and-forget (they enable the command and return without waiting), and the
SPI transactions themselves are microseconds at any plausible divisor. 15 ms is ~90,000
periph_clk cycles, so something in that path is far slower than the code suggests, or the core is
not clocked at the 6 MHz `clk_PAD` is driven at. `tb_top.sv` now timestamps every flash
chip-select assertion so the next run shows this directly instead of leaving it to inference.

One consideration for whoever reruns this: the netlist used here is the Aug 16 one, which has the
**pre-6 MHz boot ROM baked into it** (`sw/bootrom/spi.c`'s `PERIPH_CLK_HZ` was changed to 6 MHz
after that harden). That makes the boot ROM's SPI divisor one step conservative, so the flash
clock is slower than `BOOT_SPI_CLK_HZ` asks for. It is a plausible contributor to the run being
slow, but not to it being wrong, and it disappears on its own once ticket 29's netlist lands.

**Not rerun in this session, deliberately.** Ticket 29's detailed-routing resume was started
right after this run finished and holds the machine; a 3.25-hour sim alongside it is exactly the
host-wide contention that caused the 2026-08-18 OOM. The rerun is the next thing to do once the
route releases the host, ideally against ticket 29's netlist.

## Comments (the netlist's boot ROM is stale, and it is not fixable from here)

The earlier note flagged a "stale pre-6MHz baked bootrom" as a caveat. It is
confirmed, and it is worse than a caveat: it cannot be fixed without
re-hardening.

`flow/final/pnl/chip_top.pnl.v` was written 2026-08-16 10:36. The last commit
touching `sw/bootrom/` is 41ec581 (2026-08-14), and the 6 MHz change to
`sw/bootrom/spi.c` is still uncommitted working-tree state. So the ROM compiled
into that netlist has `PERIPH_CLK_HZ 10000000u`, not 6000000u.

That ROM is genuinely frozen. `rtl/gf180mcu/gf180_bootrom.sv` is a generated
file (`sw/bootrom/gen_bootrom.py` via `flow/synth/bootrom.sh`) that replaces
upstream's `$readmemh`-based `a2_bootrom.sv` with a case statement over the
compiled image, precisely because `$readmemh` does not synthesise. In the
netlist it is gates. There is no sim-time override, no `+readmemh` plusarg, no
memory to poke. Rebuilding it means re-running the flow, and ticket 29 has now
established that the route does not close, so a fresh netlist is not available
on any near timescale.

The measurable effect is confined to the SPI clock. `udma_qspim_open()` derives
`divisor = PERIPH_CLK_HZ / (2 * spi_clk_hz)`, so the baked ROM asks for
10e6/(2*2.5e6) = 2, and at a real 6 MHz periph_clk that yields
6e6/(2*2) = 1.5 MHz rather than the intended 2.5 MHz. Every flash transfer in
this run is therefore ~1.67x slower than the silicon would be. For the 567
bytes actually read (8-byte header plus a 559-byte image) that is roughly 3.0ms
instead of 1.8ms: real, but nowhere near large enough to account for the ~15ms
gap this ticket is trying to explain.

Two consequences for reading any result out of this run. Boot timing is
pessimistic by that 1.67x on the SPI portion only, so a pass here is a genuine
pass and a timing number here is an upper bound rather than an estimate. And
the app's UART is unaffected: "BOOT OK" comes from `sw/app/main.c`, which is
loaded from flash rather than baked, so it is built from current sources and
its 6 MHz `APP_BAUD_HZ` still matches `tb_top.sv`'s `CLKS_PER_BIT(52)`. The
baud path is sound; only the boot ROM's own idea of the clock is stale.

Worth doing regardless: commit the `sw/bootrom/spi.c` change. It is correct, it
is currently only working-tree state, and leaving it uncommitted is how the
netlist and the source drifted apart in the first place.

## Comments (100ms run: not a timeout. The boot ROM never talks to the flash at all)

The 100ms rerun completed: 100,001,000 ns in 12,653 s, i.e. 7,903 ns/s (a bit
slower than the 8,547 ns/s the 20ms run measured, same order). It failed, and
the failure is far more informative than the previous one. Raising the timeout
was the right call and it was not the bug.

The decisive observation is a negative one, from the flash-CS trace added to
`tb_top.sv` for exactly this purpose: **chip select is never asserted, not once,
in 100 ms of simulated time.** The whole flash-side log is three lines. The
model loads its image at t=0 ("Load memory with Initial content" / "Initial
Load End", so `flash_image.hex` is found and valid: 571 bytes, an 8-byte header
plus a 563-byte image, crc32 0x5357bdf1). Then one `tCHSH condition violated`
at 2,000 ns, one microsecond after reset release, which is the pad settling out
of reset rather than a real transaction. Then silence for the remaining 100 ms.
Zero UART bytes decoded, consistent with that.

The SRAM models give the rest of the timeline, and it is byte-identical to the
20ms run: first access to the interleaved CUTS banks at **3,155,000 ns**, first
access to the private banks `bank_sram_pri0_i`/`bank_sram_pri1_i` at
**18,261,000 ns**, and then nothing whatsoever for the remaining 81.7 ms. Two
runs with different deadlines producing the same two timestamps means this is
deterministic and reproducible, not a flaky race.

So the picture is: the core comes out of reset and runs (it reaches its stack
and .bss in the CUTS banks at 3.155ms), it eventually touches the image region
at 0x1C000000 at 18.261ms, and then it stops doing anything observable. Since
no SPI transaction ever happened, whatever it read there was uninitialised
memory, which is exactly what would drive `sw/bootrom/main.c` into `halt()` on
a bad size or a CRC mismatch. The ~15ms gap this ticket has been chasing is
therefore not slow SPI. It is the boot ROM stalled waiting on a uDMA transfer
that never starts, and the 1.5 MHz vs 2.5 MHz clock staleness recorded above is
a real but entirely separate issue that cannot explain any of this.

Two candidate causes ruled out already, both from the RTL rather than
speculation:

- **Not a pad mapping or floating-pad problem.** `pad_control.sv` confirms
  35=`PERIO_QSPIM0_CLK`, 36=`PERIO_QSPIM0_CSN0`, 37=`DATA0`, 38=`DATA1`, which
  is what `tb_top.sv` assumes. More usefully, at `pad_mux == 2'd0` the output
  enables for 35 and 36 are hardwired `1'b1`, so CS is actively driven rather
  than floating. A quiet CS line means the uDMA is genuinely holding it
  deasserted, not that the TB failed to observe it.
- **Not a missing clock-gate release.** `udma_qspim_open()` does assert and
  release `reg_rst` and then set `reg_cg` for the QSPIM0 bit, in that order.

Still open, and the obvious next thing to check: whether `pad_mux` actually
resets to 0. Everything above assumes it, and the reset value has not been
found in `apb_soc_ctrl` yet. If it resets to something else, the qspim0 outputs
go nowhere and the pads are driven from another source, which would explain the
observation exactly.

Next step is the RTL run rather than another 3.5-hour gate-level one. It is
owed by this ticket's Definition of Done anyway, it exercises the same boot path
far faster, and it carries the *current* boot ROM instead of the stale baked
one, so it also isolates whether any of this is netlist-specific.

### `make sim` was broken, separately

The first RTL attempt never got to simulating: iverilog stopped at
`apb_gpio.sv:34`, `Include file pulp_soc_defines.svh not found`. The RTL is
full of `` `include `` directives that resolve only against the include path
fusesoc computed, `flow/build/sources.yaml` already records it as
`VERILOG_INCLUDE_DIRS` (five directories), and `tb_top_tb.py` was reading only
`VERILOG_FILES` from that manifest and discarding the rest. Fixed by reading
both and passing `includes=` to `runner.build()`, which keeps `make sim` and
`make harden` resolving includes from one source of truth. GL is unaffected,
since a flat netlist has no includes.

## Comments (what the silent-CS bug is not, and the one lead worth chasing)

Six candidate causes checked statically against the RTL and headers. All six
are dead, and they are recorded here so the next session does not re-walk them:

- **Pad mapping.** `pad_control.sv` gives 35=`PERIO_QSPIM0_CLK`, 36=`CSN0`,
  37=`DATA0`, 38=`DATA1`, matching `tb_top.sv`.
- **Floating pad.** At `pad_mux == 2'd0` the output enables for pads 35 and 36
  are hardwired `1'b1`. CS is actively driven, so a quiet line means the uDMA
  is holding it deasserted, not that the TB failed to see it.
- **Pad mux default.** `apb_soc_ctrl.sv:205` resets `r_padmux <= '0`, so
  qspim0 owns those pads out of reset with no software configuration needed.
- **uDMA clock gate.** `udma_qspim_open()` asserts `reg_rst`, releases it, then
  sets `reg_cg` for the QSPIM0 bit.
- **Peripheral ID shift from ticket 12.** This one looked genuinely promising,
  since uDMA IDs are positional and ticket 12 removed the filter and the camera.
  It is wrong: `udma_subsystem.sv` orders them `PER_ID_UART`, `PER_ID_SPIM`,
  `PER_ID_I2C`, `PER_ID_SDIO`, `PER_ID_I2S`, `PER_ID_CAM`, `PER_ID_FILTER`, so
  both cut peripherals sit *after* SPIM and cannot shift it.
- **Register base.** `UDMA_CH_ADDR_QSPIM0` is `0x1A102000 + 2*0x80` =
  `0x1A102100`, i.e. channel index 2, consistent with the control block at index
  0 and one UART at index 1.

The one real lead is in `sw/bootrom/spi.c` itself. All three command builders
share a single `static uint32_t auccmd[16]`, and each one opens by writing
`cmd_cfg_b.en = 0; cmd_cfg_b.clr = 1`, which aborts and clears whatever is in
flight. But `udma_flash_reset_enable()` and `udma_flash_reset_memory()` are
fire-and-forget: they start the command DMA and return immediately, with no
wait for completion. Only `udma_flash_read()` waits, and it waits on
`while (pqspim_regs->rx_size != 0) {}`.

So the three calls race over one buffer. `reset_memory` aborts `reset_enable`'s
command stream and overwrites the buffer underneath it, and `flash_read` then
does the same to `reset_memory`. Whether that merely loses the two reset
commands (harmless for a simulated part that needs no reset) or leaves the
command channel wedged so that `flash_read`'s own stream never issues is the
open question, and it fits the observation exactly: a wedged command channel
asserts no CS, `rx_size` never decrements, and the core spins in that `while`
loop forever, which is precisely the permanent silence after 18.261 ms.

Testing it is cheap and does not need a full run: make the two reset functions
wait for `cmd_size` to drain the way `flash_read` waits on `rx_size`, or give
each its own buffer. If CS then appears, the cause is confirmed.

One timing detail that does not fit any story yet and should not be forgotten:
the first stack access is at 3.155ms, about 19,000 cycles at 6 MHz after reset
release. That is a long time for `crt0.S` to set `sp` and clear a 512-byte
`.bss`. Something is delaying the core's start, and it is unexplained.

## Blocker: `make sim` cannot build this RTL under Icarus

With the include paths fixed, iverilog gets further and then fails with 21
errors, all inside the CV32E40P, in two construct classes it does not
implement: `unique case (...) inside` set-membership (9, in
`cv32e40p_decoder.sv`) and named structure assignment patterns like
`'{mpie: ..., mpp: ..., mprv: ...}` (12, across `cv32e40p_cs_registers.sv`,
`cv32e40p_hwloop_regs.sv` and the decoder). Yosys accepts both, which is why
`make harden` has never hit this.

There is no cheap way out, and the obvious one is closed. Switching the RTL run
to Verilator does not work, because `rtl/gf180mcu/gf180_clk_gate.sv`
instantiates `gf180mcu_fd_sc_mcu7t5v0__icgtp_1` by name unconditionally, with no
behavioural path under `FUNCTIONAL`, so an RTL run still pulls in the PDK cell
library and its UDPs. That is the same thing that ruled Verilator out for
gate-level in ticket 16.

Three options, none free: patch the vendored CV32E40P for Icarus (mechanical
but it makes sim and synthesis read different source); add a behavioural
`icgtp_1` model for RTL runs only, which unblocks Verilator but is a second
simulator to maintain and a clock cell that differs between sim and silicon; or
accept gate-level as the only sim path and instrument it instead, at roughly 40
minutes per iteration to reach the 18.261ms point. This needs a decision and is
not one to make silently.

## Comments (RTL simulation now works, under Verilator, and the bug reproduces there)

`make sim` runs. It took six distinct fixes, and the important outcome is at
the bottom: the failure is not a netlist artifact.

Icarus was abandoned for RTL rather than patched. It cannot compile the
CV32E40P (21 errors across `case (...) inside` and named assignment patterns),
and the fix would have meant editing vendored CPU RTL so that simulation and
synthesis read different source, which is the same class of drift that produced
the stale-boot-ROM problem. Verilator compiles all of it without complaint.
Gate-level stays on Icarus and is untouched: it reads the PDK cell models,
whose `icgtp` is a UDP, and that is still the constraint ticket 16 recorded.

What it took, in order:

1. **Include paths.** `tb_top_tb.py` read `VERILOG_FILES` from
   `flow/build/sources.yaml` and discarded `VERILOG_INCLUDE_DIRS`, so every
   `` `include `` failed. Now passes both.
2. **Clock cells.** `rtl/gf180mcu/gf180_clk_gate.sv` is the *only* file in the
   design that names a PDK standard cell, so RTL drops it and reads
   `tc_clk.sv`, `pulp_clk_cells.sv`, `cluster_clk_cells.sv` and
   `cv32e40p_sim_clock_gate.sv` instead, all already vendored. All six modules
   it defines have behavioural twins; nothing was written by hand. This is what
   frees RTL from `libs.ref` and therefore from Icarus.
3. **Pad cells.** `gf180mcu_ocd_io__bi_24t` builds its pull-up and pull-down out
   of `rnmos`, a Verilog-1995 gate primitive Verilator does not implement, with
   no `ifdef` around it. This corrects an earlier claim in this session that the
   pad model was Verilator-clean: it was checked for UDPs and `specify` blocks,
   and `rnmos` is neither. `sim/tb/gf180mcu_ocd_io_behav.sv` now provides the
   eight cells `chip_top` instantiates, transcribed from the real models rather
   than invented, function only and no timing.
4. **Port directions.** `chip_top` declares `clk_PAD`/`rst_n_PAD` as `inout`
   because they are pads. Wiring `tb_top`'s `input` ports straight into them
   reads as assigning to an input, which Verilator rejects. They now go through
   intermediate nets.
5. **The SRAM model's specify block.** `sram1024x8m8wm1.v` declares fifteen
   specparams inside `specify ... endspecify` and uses one of them, `Tdly`,
   from two always blocks outside it. Icarus keeps specparams module-visible.
   Verilator drops the block, fails on the outside uses, and once those are
   fixed goes on to generate the timing checks themselves, which need the other
   fourteen: 672 errors. Hoisting one parameter is not enough, so RTL reads a
   generated copy with the whole block stripped and `Tdly` as a localparam.
   Fair trade: ticket 20 already established this model is 2x optimistic on
   access time at 3.3 V and `make sta` never reads it, so its checks were never
   load-bearing.
6. **A real build-order bug in `sim/Makefile`, not a Verilator issue.** The RTL
   target was `all: app sources`, and `flow/synth/filelist.sh` line 84 does
   `rm -rf $BUILD` on `flow/build`. So the `sources` step deleted the
   `flash_image.hex` that `app` had just built, and the first RTL run came up
   with an empty flash (`$readmem file not found`). GL never hit it because its
   target is `app gl-netlist`, with no `sources` step, which is exactly why GL
   loaded the image and RTL did not. Order swapped.

### The result

100,001,000 ns in 2,528 s, i.e. **39,553 ns/s against gate-level's 7,903**, so
RTL iterates five times faster. That first run had the empty flash from item 6,
so its numbers are not a clean baseline. What it establishes anyway is the
thing that matters: **zero flash CS assertions and zero UART bytes, exactly as
gate-level.** An empty flash would still show CS being asserted if the boot ROM
had ever tried to read it. It never tried.

So the failure is not a netlist artifact, not a gate-level modelling artifact,
and not caused by the stale 10 MHz boot ROM, because RTL carries the current
6 MHz one and fails identically. It is in the design or the driver, and it is
now reproducible in a simulation that runs five times faster and exposes every
internal signal.

The rerun adds an SCLK edge counter alongside the CS trace, because CS silence
alone leaves two very different explanations open: a completely idle uDMA, or
one that is running and driving the wrong line. The qspim cannot shift a
command without toggling its clock, so that count separates them.

## Comments (the hang is located exactly: udma_flash_read's rx_size spin)

RTL simulation with a boot ROM fetch tracer pins the failure to a single
instruction pair, and corrects two earlier readings in this ticket.

**Where the core is.** `boot_main` never halts and never returns. It spins in
`udma_flash_read`'s `while (pqspim_regs->rx_size != 0) {}`, which compiles to

    1a000334:  lw   a4,4(a5)
    1a000336:  bnez a4,1a000334

Both are word address 205. The tracer reports a rock-steady 258 ROM fetches per
100 us from 300 us onward, with `last_A` sitting at 205 to 207. That rate is
about 2.3 cycles per iteration at 6 MHz, exactly a taken two-instruction loop,
and 206/207 are the prefetcher running one and two words past the branch.
`rx_size` is written 8 by the header read and never decrements.

**Two corrections.** An earlier comment reasoned about an asymmetry between the
first and second `udma_flash_read` calls, the first returning and the second
spinning. That was wrong: `last_A=206` is the `ret` at `0x1a000338` being
*prefetched* while the core loops at 205, not executed. There is no second
call. Separately, an instantaneous `CEN` sampler was useless here, reporting
`A=0` for most samples because `CEN` is only low during an active fetch;
latching every fetch and counting per interval is what made this legible.

**What has been eliminated, with evidence.** The `halt()` path is not taken:
that is `1a0000f0: j 1a0000f0` at word 60, never reached. The peripheral is
alive: `s_clk_periphs_per[1]` toggles a full 602-603 edges per 100 us at 6 MHz,
`s_per_rst[1]` is high and `s_rst_periphs[1]` is low, so `udma_qspim_open()`'s
reset pulse and `reg_cg` write both took effect. The clock-enable bit is right
too: `pulp_soc_defines.svh` sets `N_UART` to 1 (ticket 06 shrank it from 2), so
`PER_ID_SPIM` is 1, matching the header's `UDMA_CTRL_QSPIM0_CLKEN (1 << 1)`.
The register base agrees on the same arithmetic: control block at slot 0,
qspim0 at slot 1, hence `0x1A102000 + 2*0x80`.

So the peripheral is clocked, out of reset, addressed by a plausible base, and
does nothing whatsoever: no SCLK edge, no CS, no descriptor fetch, in 100 ms.

**Open question being measured now.** Whether the config writes reach the
peripheral at all. Inside the uDMA a peripheral only sees an access when
`s_periph_valid[PER_ID]` asserts, so counting that for index 1 against the
any-peripheral OR separates an address-decode fault (writes landing on the
wrong slot, which would make `UDMA_CH_ADDR_QSPIM0` wrong despite the arithmetic
above) from a peripheral that receives its writes and ignores them.

**Still unexplained, and worth not losing.** `boot_main`'s prologue writes the
stack near `0x1C003FF0` within microseconds of reset, yet the SRAM models
report first access to the interleaved banks at 3.155 ms. Those cannot both be
true. Either the stack writes are not landing where the linker script says, or
the SRAM model's first-access report means something other than assumed. It
matters because `auccmd`, the command descriptor the uDMA must fetch, lives in
that same `.bss` region at `0x1C003E00`.

**Iteration cost is now the good news.** `TIMEOUT_NS` is overridable and
`run.sh` forwards it, so a debugging run uses a 1 ms window (about 25 s) rather
than 100 ms (42 min). Everything above happens before 400 us.

## Comments (CORRECTION: every SRAM timestamp in this ticket is 1000x too large)

The SRAM model's first-access messages are in **picoseconds**, not
nanoseconds. `gf180mcu_ocd_ip_sram__sram1024x8m8wm1.v` line 48 declares
`` `timescale 1 ps / 1 ps `` and line 144 prints with `$realtime` and `%0t`.
Earlier comments in this ticket read those figures as nanoseconds. They are
wrong by three orders of magnitude, and the conclusions drawn from them are
wrong with them.

Corrected:

    reported          actually
    3.155 ms          3.155 us    first access, interleaved CUTS banks
    18.261 ms         18.261 us   first access, private banks
    3.154 / 3.984 ms  3.154 / 3.984 us   (RTL run)
    36.852 ms         36.852 us   (RTL run, private banks)

Three things follow.

**The 20 ms timeout was never the problem.** The comment titled "a timeout
mid-boot, not a boot failure" had it backwards: it was a boot failure, and the
run had already been hung for 19.98 ms of its 20 ms when it stopped. Raising
`TIMEOUT_NS` to 100 ms was unnecessary, and the ~3.5 hour gate-level run it
justified bought nothing that a 1 ms run would not have shown. The arithmetic
written into `tb_top_tb.py`'s comment to justify 100 ms is built on the same
error and should be rewritten.

**The "unexplained ~15 ms gap" never existed.** It is 15 us, which is an
entirely ordinary amount of time for `udma_qspim_open`, two fire-and-forget
reset commands and the descriptor writes. There is nothing to explain, and the
flash-CS trace added to hunt it was justified by a phantom. That trace turned
out to be the single most useful probe in this ticket anyway, so no loss.

**The stack anomaly dissolves.** The previous comment flagged that
`boot_main`'s prologue writes the stack within microseconds while the SRAM
reported 3.155 ms, and said both could not be true. Both are true: it is
3.155 us. The linker script, the memory map and the model all agree, and there
is no missing-write mystery to chase.

What does not change: the core spins forever in `udma_flash_read`'s
`while (rx_size != 0)`, the qspim is clocked and out of reset, and no SCLK edge
or CS assertion ever occurs. The diagnosis stands; only the timescale of the
evidence was misread.

The lesson worth keeping for this repo: PDK simulation models set their own
`timescale`, and `%0t` prints in the *printing module's* precision, not the
testbench's. `sim/tb/tb_top.sv` uses `1ns/1ps`, so its own probe output is in
picoseconds too, which is why "@ 100000000" there is 100 us and not 100 ms.

## Comments (ROOT CAUSE: L2_BANK_SIZE truncates every uDMA address above 8 KiB)

Found, with direct measurement rather than inference. `soc_domain.sv`'s
`L2_BANK_SIZE` is too small, which narrows every uDMA start-address register
to 13 bits, so the boot ROM's command descriptor at `0x1C003E00` is silently
truncated and the SPI command channel streams zeros forever.

### The measurement

Probing inside `i_udma` while the core spins:

    cmd startaddr = 0x00001e00     descriptor is at 0x1C003E00
    L2 read addr  = 0x1c000000
    L2 rdata      = 0x00000000
    cmd size      = 28  (correct: 7 words)
    cmd continuous= 0   (correct)
    l2_req = l2_gnt, climbing ~603 per 100 us, i.e. every cycle, forever

`0x3E00 & 0x1FFF == 0x1E00`: bit 13 is dropped, so the field is 13 bits wide.
Size and continuous-mode are both correct, which rules out the earlier
suspicion that the read-modify-write on `cmd_cfg` was picking up a stray
CONTINUOUS bit.

### Why zeros produce exactly this failure

`kSPIm_Cfg` is `(0x0 << 28)`, so a command word of `0x00000000` is a *valid*
Cfg command with clock divider 0, not an illegal opcode that would raise an
error. The interpreter therefore consumes an endless run of harmless no-ops:
the command FIFO stays hungry (`cmd_req` asserted every cycle), the channel
keeps fetching, and no SOT is ever reached, so no CS assertion and no SCLK
edge. That is precisely the "peripheral is clocked, out of reset, correctly
addressed, and does nothing" signature this ticket has been chasing.

### The arithmetic, and where it came from

    L2_MEM_ADDR_WIDTH = clog2(L2_BANK_SIZE * NB_L2_BANKS) - clog2(NB_L2_BANKS)
    soc_peripherals gets MEM_ADDR_WIDTH = L2_MEM_ADDR_WIDTH + clog2(NB_L2_BANKS)
    udma_subsystem  L2_AWIDTH_NOAL = L2_ADDR_WIDTH + 2

At `L2_BANK_SIZE = 1024`, `NB_L2_BANKS = 2`: 10, then 11, then **13 bits =
8 KiB**. Upstream's 29184 gives 18 bits, 256 KiB. This design's L2 is 16 KiB
(two 4 KiB private banks plus two 4 KiB interleaved, `0x1C000000` to
`0x1C004000`), so everything at or above `0x1C002000` is unreachable by the
uDMA, which is the entire interleaved region.

The regression is documented in the code's own comment, which reasoned that
`L2_BANK_SIZE` was safe to shrink to match the SRAM macro's bank depth because
"this only sizes uDMA address registers". That is true and it is the bug: those
registers must be sized to the L2 *address range*, not to a bank's depth. The
boot ROM's `.bss`, holding `spi.c`'s `auccmd`, is placed by `boot.ld` at
`0x1C003E00`, above the truncation boundary.

### Fix applied

`L2_BANK_SIZE` 1024 -> 2048, giving `L2_AWIDTH_NOAL = 14` and covering the full
16 KiB. It costs register bits only; the comment in `soc_domain.sv` now records
the derivation so the next person does not re-shrink it.

A software-only alternative exists (move `boot.ld`'s L2 region below
`0x1C002000` so the descriptor lands inside the 8 KiB window) and was **not**
chosen: it would leave the uDMA unable to reach half of L2 for every other
user, and `app.ld` already declares an L2 region of `0x3E00` that runs past the
boundary, so a DMA of any reasonably sized image would hit the same wall.

### Scope of the damage beyond the boot ROM

This is not boot-specific. Any uDMA transfer to or from an L2 address at or
above `0x1C002000` was silently reading or writing the wrong location. The RX
side happened to work in this ticket only because `L2_IMAGE_BASE` is
`0x1C000000`, offset zero, where truncation is a no-op.

### Not verifiable against the current netlist

`flow/final/pnl/chip_top.pnl.v` predates this fix and, separately, has the boot
ROM compiled into gates, so neither this RTL change nor any software change can
be tested against it. Validation is RTL-only until a re-harden, which is blocked
on [the fanout ticket](32-reduce-fanout-for-routability.md). One more reason the
L2-resident-boot idea in the map's fog is worth taking seriously.

## Comments (CORRECTION: L2_BANK_SIZE was a real bug but NOT the root cause)

The comment above is titled "ROOT CAUSE" and that claim was premature. The
`L2_BANK_SIZE` defect is real, the fix is correct and should stay, but boot
still fails with it applied. Verified directly: with `L2_BANK_SIZE = 2048`,
`cfg_cmd_startaddr` now reads `0x3E00` instead of the truncated `0x1E00`, and
over a full 3 ms run there are still **zero CS assertions and zero SCLK
edges**, with `l2_req` climbing to 17,822. The address truncation was genuine
and would have corrupted any uDMA transfer above `0x1C001FFF`; it simply was
not what stops boot.

Keep the fix on its own merits. Do not treat ticket 31 as closed by it.

### What the deeper probes now show

With the command channel correctly programmed (`sa3=0x3e00`, `sz3=28`,
`cont=0`):

- `s_tx_cfg_en` reads 0 at every sampling instant, but it pulsed 4 cycles
  during setup, so it is a start strobe into `udma_core` rather than a running
  level. The channel was started.
- `s_tx_ch_req` is `1111111`, all seven TX channels requesting. That is normal
  and uninformative: an empty peripheral FIFO always requests.
- **`s_tx_ch_gnt` is all zeros, always.** No TX channel is ever handed data.
- The uDMA's L2 read port asserts `L2_ro_req_o` and sees `L2_ro_gnt_i` on
  essentially every cycle, but `L2_ro_addr_o` never advances from
  `0x1C000000` and `L2_ro_rdata_i` is always `0x00000000`.

So the fault sits inside `udma_core`'s TX datapath: it is hammering the memory
side with a request whose address never increments, while delivering nothing to
any channel. A started channel with a correct start address and size should
walk 7 words from `0x1C003E00` and hand them to channel 3.

The wiring is not the problem and has been checked: `soc_peripherals.sv` binds
`L2_ro_*` to `l2_tx_master`, `soc_domain.sv` passes `s_lint_udma_tx_bus`, and
`soc_interconnect_wrap.sv` assigns it to `master_ports[2]`. The port is
connected.

### Caveat on the simulator, worth stating before chasing further

Verilator is 2-state. Uninitialised storage reads 0 where Icarus would give X,
so a reset bug that X-propagates under a 4-state simulator can look like
well-behaved zeros here. A request line stuck asserted with an address stuck at
0 is exactly the shape a missing reset would take. That said, the gate-level
run under Icarus shows the same end symptom (no CS, no SCLK), so the failure is
not a Verilator artifact even if some of these internal values are flattered by
2-state semantics.

### Next probe

Look at `udma_core`'s TX channel state directly rather than its boundary:
the per-channel address counter and remaining-size counter for channel 3, and
the arbiter's channel select. The question is whether channel 3 ever becomes
the active channel at all, or whether the arbiter is stuck on a channel that
was never programmed.

## Comments (ROOT CAUSE: the testbench never gave the uDMA a reset edge)

The caveat above turned out to be the answer, though not in the way it was
written: the missing reset is real, it is in the harness rather than the design,
and it is not a 2-state artifact. Icarus hits it too.

Probing `udma_tx_channels` directly, as the previous comment proposed, showed
the channel side is entirely healthy and the arbiter is dead:

```
chen=0x8  req=0x8  ca3=0x3e00  sa3=0x3e00  sz3=28   <- channel 3 enabled,
                                                       requesting, correct addr
gseen=0x0                                            <- never granted, ever
prio=0x0  any=1                                      <- arbiter says work
                                                       pending, grants nobody
```

`udma_arbiter` computes `grant_o = req_i & g[S]` where `g[0]` is `r_priority`,
a one-hot vector that resets to 1. With `r_priority` at zero every grant bit is
zero no matter what is requesting, while `anyGrant_o`, which is derived from the
request vector alone, keeps reporting that someone wants service. `udma_tx_channels`
believes `anyGrant_o` and pushes a request into its L2 FIFO every cycle, but the
address multiplexer is selected by `r_grant`, so with no grant set it emits the
`'h0` default. That is the source of the endless reads at `0x1C000000` returning
zeros. The zeros then decode as `kSPIm_Cfg` no-ops, so the SPI interpreter never
errors and never reaches SOT, which is why the symptom was silence rather than a
fault.

### Why `r_priority` never reset

Two things have to be true at once, and both are.

Every flop in this design resets with `always_ff @(posedge clk or negedge rstn)`.
That is level-sensitive in silicon but edge-sensitive in a simulator: the reset
branch runs only on a clock edge or on `rstn` falling. Most of the chip does not
care, because its clock is free-running and the clock edges arriving while reset
is asserted do the job.

`udma_core` is the exception. `udma_ctrl` drives `cg_core_o = |r_cg`, which is
zero out of reset, and that gates `s_clk_core` off until software enables a
peripheral. So every flop inside `udma_core` sees no clock at all while reset is
asserted, and depends entirely on the falling edge of `HRESETn`.

The harness never produced one. `reset()` drove `rst_n_PAD` to 0 at time zero,
which is where Verilator already had it, so there was no transition. The design
then ran from its power-on state, and `r_priority` sat at zero forever. Every
other uDMA register recovered because software writes it during setup;
`r_priority` is the one register whose only source of a value is reset.

A one-nanosecond high pulse is not enough either, and the first attempt at this
fix failed for that reason. `rst_n_PAD` does not reach the SoC directly:
`safe_domain` runs it through `rstgen_bypass`, a four-deep shift register
clocked by `ref_clk`, and only its output reaches `soc_domain`. That output
starts low and can only fall after it has first risen, which needs four clock
edges with `rst_n_PAD` held high. The fix holds it high for twelve clock
periods, then low, then high.

### This is a harness bug, not a silicon bug, and that was verified

Async reset is level-sensitive on real flops, so holding `rst_n` low resets
`r_priority` regardless of the gated clock. The question was whether synthesis
preserved the async reset, and it did: the netlist's flops are `dffrnq` (async
reset) and `dffsnq` (async set), 14,000 of them, with only 193 plain `dffq`.
`flow/final/pnl/chip_top.pnl.v` needs no change and no re-harden for this.

The same fix applies to the gate-level run, which failed identically for the
same reason.

### Result

With the reset fixed, the command channel runs:

```
l2_req=15  addr=0x1c003e18  fifoad=0x3e18  gseen=0x8  prio=0x10
chen=0x0  ca3=0x0                                  <- completed and self-disabled
```

Fifteen L2 reads is exactly `udma_flash_reset_enable` (4 words) plus
`udma_flash_reset_memory` (4) plus `udma_flash_read` (7), so all three
descriptors were fetched, and the last one walked `0x3e00` to `0x3e18` and
stopped. There is still no chip select, so the SPI command interpreter is the
next thing to look at.

## Comments (second root cause: the PDK SRAM model drops every access in RTL)

With the arbiter alive, the command DMA fetched all three descriptors from the
right addresses and every word came back `0x00000000`. Probing both sides of the
interconnect showed the core writing real values and the uDMA reading the exact
addresses it wrote:

```
core writes 0x1c003e04 <= 0x10000000   (SOT)
core writes 0x1c003e08 <= 0x20070003   (SendCmd, JEDEC READ)
core writes 0x1c003e18 <= 0x90000001   (EOT)
udma reads  0x1c003e04 ... udma rdata 0x00000000
```

The tell was the first descriptor word. It is `kSPIm_Cfg | aucclkdiv` and should
be `0x00000001`, and the core stored `0x00000000`, meaning its own load of
`aucclkdiv` had already returned zero. Probing core reads confirmed it directly:
`core reads 0x1c003e40 => 0x00000000`, for a byte `udma_qspim_open` had stored 1
into. L2 reads zero for everybody. Nothing had ever been written to it.

### Why

`gf180mcu_ocd_ip_sram__sram1024x8m8wm1.v` does its work in
`always @(posedge clk_dly)`, where `clk_dly` is CLK delayed by 100 ps, and
samples CEN, GWEN, A and D at that later moment. It gates itself on
`write_flag`/`read_flag`, both combinational on CEN and GWEN.

In silicon, and in a gate-level run with SDF back-annotation, clock-to-Q delay
keeps those inputs at their pre-edge values 100 ps in, so the model commits the
access that was set up before the edge. That is a correct synchronous SRAM.

In RTL there is no clock-to-Q delay. By the time `clk_dly` rises every input has
moved on. For an isolated access (CEN low one cycle, high the next) the model
sees CEN already high, `write_flag` and `read_flag` are both zero, no write
happens and Q holds its previous value. Back-to-back accesses are no better,
being committed against the following transaction's address.

`rtl/gf180mcu/gf180_bootrom.sv` already models the ROM macro properly, with a
plain `always_ff @(posedge CLK) if (!CEN)`. That is why instruction fetch worked
perfectly throughout while every single L2 access was being silently discarded,
and it is a large part of why this took so long to see: the chip looked alive.

### Fix

`sim/tb/gf180mcu_ocd_ip_sram_behav.sv`, a behavioural stand-in on the same
pattern as `sim/tb/gf180mcu_ocd_io_behav.sv`, matching the vendor model's
one-cycle read latency, Q-holds-on-CEN-high, per-bit active-low write enables
and zeroed power-on contents. It drops the setup/hold/cycle checks, which mean
nothing without annotated delays. Ticket 20 already recorded this model's access
time as 2x optimistic at 3.3 V, and `make sta` is what signs off memory timing,
so nothing load-bearing is lost.

`sram_model_for_verilator()`, which used to copy the vendor file with its
`specify` block stripped, is deleted: the stand-in replaces it outright.

### This affects gate-level too, and that is a problem for this ticket's DoD

The GL path still reads the PDK model, and runs without SDF annotation, so it
has exactly the same defect. Every L2 access in a gate-level run is being
dropped as well, which is why GL showed the same silent failure. A GL run in its
current form cannot validate anything that touches L2, which is all of boot.
The same stand-in should be used for GL, on the usual grounds that a hard macro
is simulated behaviourally and its timing is signed off by STA rather than by
simulation. Not done yet: RTL is being verified first.

## Comments (the remaining "stall" was the run being too short)

With the SRAM fixed the boot ROM reaches the flash and stays there. Four chip
selects, all four flash operations, correct descriptor words, and the header's
size field arriving in L2 as `0x233`, which is 563, the real image size.

The apparent hang after that was a measurement artifact. Sampling the receive
channel's own counters shows steady progress rather than a stall:

```
@200us  left=539  curr=0x18  beats=8   sclk=342
@300us  left=503  curr=0x3c  beats=17  sclk=643
@400us  left=467  curr=0x60  beats=26  sclk=944
```

That is 36 bytes per 100 us and 301 SCLK edges per 100 us, so a 3 MHz SPI clock
moving data at its full rate. `udma_qspim_open` computes
`6 MHz / (2 * 2.5 MHz) = 1`, and `udma_clk_div_cnt` turns a divisor of 1 into
`periph_clk / 2`, so 3 MHz rather than the 2.5 MHz asked for. That is rounding,
not a fault.

At that rate the 563-byte image needs about 1.5 ms, finishing near 1.6 ms.
Every run before this one had a timeout at or below 2 ms, so the transfer was
still in flight when the test gave up, and `l2_req` sitting still looked like a
stall because the read port is idle during a receive.

### Boot takes tens of milliseconds, and that is worth knowing

After the image lands, `crcSlow` runs over all 563 bytes. It is the bit-at-a-time
implementation, and `reflect()` inside it is another bit loop, so it is roughly
sixteen loop bodies per byte with no table and no cache. Order 20 ms at 6 MHz,
against 1.6 ms for the transfer itself.

For a one-shot boot that is fine and ticket 04 already decided boot-time
throughput does not matter. It does matter for this harness: a full boot needs a
simulated 25 ms or so, which is about ten minutes of wall time per run on top of
the Verilator rebuild. Any future `make sim` default timeout has to allow for
that, and it is a reason to keep a shorter smoke test alongside the full one.

## Comments (third defect: a boot image whose length is not a multiple of four hangs boot)

The full-length run got the whole image across and then stopped three bytes
short:

```
rx: cfgsize=563 left=3 curr=0x230 beats=142 | spi: state=0 dones=4 sclk=4648
```

`state=0` is IDLE and `dones=4` means the SPI finished all four transfers, with
4648 SCLK edges, so every one of the 563 bytes was clocked in off the wire. The
receive DMA still had 3 bytes outstanding and never reached zero, so
`udma_flash_read`'s `while (rx_size != 0)` spun forever.

The receive channel runs at 32-bit datasize, and `udma_spim_txrx` only hands a
word to the DMA once it has assembled four bytes. 563 is 140 words plus a
three-byte tail. That tail is received, sits in the shift register, and is never
delivered. 560 of 563 bytes land, the counter stops at 3, and boot hangs.

This one is a real defect rather than a harness artifact: it would hang the same
way in silicon, for any image whose length is not a multiple of four.

### Fix, and why it went in the image builder

`sw/app/gen_flash_image.py` now pads the image with zero bytes to a 32-bit word
boundary before computing the CRC, so the header's size and the ROM's
`crcSlow()` cover the same padded bytes.

The more robust place for this is the boot ROM, rounding the DMA length up to a
multiple of four while CRC-ing only `size` bytes. That is not available: the ROM
is compiled into the netlist, so a ROM change needs a re-harden, which is
blocked on [the fanout ticket](32-reduce-fanout-for-routability.md). The
generator fix needs no hardware change and works today.

Worth carrying into the next re-harden regardless, because a silent forever-hang
on a mis-sized image is a poor failure mode to ship, and the ROM is the only
place that can defend against an image it did not build.

## Comments (RTL passes end to end)

```
** tb_top_tb.test_boot_and_uart   PASS    23602992.00         303.54      77758.01 **
** TESTS=1 PASS=1 FAIL=0 SKIP=0
```

All four things the Definition of Done asks for, at RTL:

- Reset released and the core clocked from `ref_clk_i`: it fetches from the boot
  ROM and runs.
- A real boot from the SPI flash model with the CRC checked, not bypassed:
  four chip selects, 4656 SCLK edges, all 564 bytes into L2 at `0x1C000000`, and
  `crcSlow()` running to a match. A mismatch calls `halt()`, so reaching the app
  at all is the CRC passing.
- The L2 read-write-read walk: "SRAM PASS" over UART.
- The expected string on UART0 TX: "BOOT OK" and "SRAM PASS", both matched byte
  for byte by the FSMs in `tb_top.sv`, including the trailing CR LF.

One thing to know when reading a log by hand. The UART bytes are dumped one
character at a time with `$write`, so with a periodic probe also printing they
end up scattered one letter per line: at 115200 baud a byte lands every 87 us
while the probe fired every 100 us. `grep "BOOT OK"` finds nothing on such a
log even though the string was received. Reconstructing it needs the first
character of each line:

```
sed -n '805,845p' run.log | cut -c1-1 | tr -d '\n' | tr -d 't'   ->  BOOT OK^M
```

The debug instrumentation has since been cut back to a transition-triggered
tracer for exactly this reason, so a normal run's UART output reads straight.

### Cost

24 ms of simulated time, about five minutes of wall clock at 78,000 ns/s, on top
of a Verilator rebuild of similar length whenever the testbench changes. Almost
all of the 24 ms is `crcSlow()`.

## Comments (it passes: the netlist boots and prints)

**`make sim-gl` passed.** Against `RUN_2026-08-22_23-39-37`'s post-PnL netlist, from the first
run in this project's history to complete every step with DRC, LVS, density, antenna, XOR and
illegal-overlap all clear, the harness decodes **`BOOT OK`** and **`SRAM PASS`** over UART0 and
the cocotb test reports PASS. First gate-level run in this ticket's history to end by passing
rather than by being killed or timing out.

**What was actually stopping it was the waveform trace, not the design, and not the timeout.**
`waves=True` was hardcoded in both `runner.build()` and `runner.test()`. Measured on an RTL run
started to validate the 5 MHz software: **7.43 us of simulated time cost 1.5 GB of VCD and about
seven minutes**, an effective ~18 ns/s against the 39,553 ns/s this file recorded for Verilator.
A full boot needs 28.204 ms, so that run was heading for something on the order of terabytes of
trace and could not have finished on this disk at any timeout setting. Every performance number
this ticket ever recorded was measured through that overhead, which is why boot kept looking
like it was hanging when it was only crawling.

Nothing in the test reads the VCD: both assertions poll cocotb handles (`boot_ok_seen`,
`sram_pass_seen`) and the UART bytes come from `tb_top.sv`'s own `$display`. So it is purely a
debugging aid, and it is now opt-in with `WAVES=1`.

Re-measured with it off, and corrected every place carrying the old figures:

| | rate | 28.204 ms boot |
|---|---|---|
| RTL, Verilator | 233,439 ns/s | 121 s |
| gate level, Icarus | 23,360 ns/s | 1,207 s |

That is 5.9x and 2.7x faster respectively, and it turns this ticket's debug loop from hours
into a 21-minute gate-level run and a 3-minute RTL one.

**Also corrected: "boot either completes or hangs within tens of microseconds"**, which is why
20 ms once looked like a generous deadline when it was not. The SPI phase does finish in tens of
microseconds, but `crcSlow()` is a bit-at-a-time CRC32 over the whole image and the app then
walks 512 B of L2 twice. That is where the other 28 ms goes. Do not size this timeout off the
flash trace. `TIMEOUT_NS=45000000` is the useful setting, about 1.6x real boot time.

**Two observations recorded rather than fixed:**

- The flash model prints `False instruction (66)` and `(99)` early in every run. Those are
  0x66/0x99, JEDEC Enable-Reset and Reset-Device, which `sw/bootrom/spi.c` issues on purpose and
  the `GD25Q128B` model does not implement. Boot proceeds correctly through both. Cosmetic.
- The gate-level liveness probe works. Its escaped identifier resolves in the netlist and the L2
  access counter climbs exactly as expected: flat during the ROM's SPI phase, then steeply from
  20 ms once the app starts walking L2.

**Not resolved yet.** This is the 166.67 ns netlist, driven at 5 MHz. That combination is
functionally valid (the only clock-dependent thing baked into the netlist is the boot ROM's SPI
divisor, which lands on 1 at either frequency), but the netlist that ships is the 200 ns one
ticket 29 is re-hardening for. The harness and the design are proven; what remains is repeating
this against the final netlist.
