# Correct the OCD SRAM Liberty and gate-level model

Type: task
Status: open
Blocked by: none

## Question

Ticket 11 established that no timing, power or area data anywhere in `gf180mcu_ocd_ip_sram`
was derived from the OCD layout. Every Liberty file is a foundry Liberty file with the header
swapped and the address bus resized. The design is now committed to sixteen of these macros, so
the defects have to be handled rather than noted.

Four things to fix or consciously accept, in descending order of consequence.

- **The gate-level model is optimistic by about 2x.** `sram1024x8m8wm1.v`'s specify block was
  re-derived in May 2026 from `specs/5_AC_Characteristics2.csv`, whose `Tah`/`Tal` rows are
  corrupted: column 1 carries column 5's value, duplicating 13.974 at both ends. The
  recharacteriser dropped the true worst corner and promoted the typical 25 C figure, so `ta`
  reads `4230 : 6215 : 7177` ps where the SNSP 3.0 V 125 C value is about 13.97 ns. The 5.0 V
  and 1.8 V tables in the same file are clean and the 64/256 tables are clean, which is what
  makes the shift unambiguous. Ticket 16 pinned Icarus for gate-level simulation; this is the
  number it will use.
- **Liberty `area` is the foundry macro's area**, 209,400 declared against a real 155,414 um2 for
  the 1024x8. Either patch it or make sure nothing reads it.
- **`memory() { address_width }` is 9 against ten address pins** on the 1024x8. The pin bus is
  correct, so this bites memory-aware tools rather than STA.
- **The Liberty timing itself is the foundry 512x8's**, which is the part that cannot be fixed
  locally, only bounded. Decide whether to sign off against it as a pessimistic proxy, which is
  what quoting 15.87 ns at `ss_125C_3v00` amounts to, or to characterise the macro.

Then decide what goes upstream. These are defects in a library the project depends on and the
author is responsive, so a report is cheap. Note ticket 02: nothing is published from this
effort, so an upstream issue is a separate act from publishing this work, and needs the dev's
call.

## Definition of done

A local patch under `flow/` or `pdk/` that corrects what can be corrected, applied by
`make pdk` or documented as a post-build step, plus a recorded decision on the timing proxy and
on whether to report upstream.

## Answer

<!-- filled on resolution -->
