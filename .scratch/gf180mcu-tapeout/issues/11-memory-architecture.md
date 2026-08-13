# Memory architecture: how much L2, in how many banks, from which macro?

Type: grilling
Status: resolved
Assignee: yusefkarim
Blocked by: 07, 08, 10, 14

## Question

This is the decision the whole design bends around. Memory density, not logic, is the binding
constraint.

Upstream wants 512 KiB interleaved (`BANK_SIZE_INTL_SRAM = 32768` across 4 banks) plus two
8192-word private banks. At the foundry macro's 0.409 mm² per KiB, 576 KiB would need roughly
241 mm² against 12.92 mm² of core area. The cut is a factor of thirty-six, not a trim.

Decide:

- **Interleaved L2 size.** 16 KiB was the working assumption at the foundry macro's
  0.409 mm²/KiB, costing 6.70 mm² and 52% of core area. Ticket 07 changed the picture: the
  OCD `sram1024x8m8wm1` measures 0.155 mm²/KiB, which puts 16 KiB at 2.49 mm² (19%) and
  makes **32 KiB reachable** at 4.97 mm² (39%). Ticket 10's measured logic area says what is
  actually affordable. Size a foundry-macro fallback at the same time, because the OCD
  timing data is simulation-derived and not yet silicon-correlated. Ticket 01 added a cost to
  the OCD route that was not visible before: the macros are **not built into the pinned PDK**
  and getting them means `ciel build -l gf180mcu_ocd_ip_sram` against the same open_pdks
  commit, which is a from-source PDK build rather than a tarball fetch and has not been
  attempted. Choosing the OCD macro buys that rebuild, and the rebuild has to work before the
  memory architecture can rest on it.
- **Do the private banks survive at all?** `rtl/gf180mcu/README.md` names them as the first
  thing to drop. If they go, `gf180_private_ram.sv` is never written and the memory map at
  `0x1C00_0000` changes.
- **Bank count.** `NB_L2_CHANNELS` is 4. Fewer, wider banks share periphery and place more
  easily; more banks preserve upstream's interleaving behaviour and TCDM throughput.
- **Which macro**, given the answers to tickets 07, 08 and 14. Note that the OCD macros are
  also 8 bits wide, so a 32-bit word still means ganging four of them; the win is depth
  (1024 words against 512) and a better-amortised periphery, not width. Their LEFs are
  missing `ANTENNAGATEAREA` (upstream issue #3, still open), which will matter at routing.
- **The stale parameter.** `soc_domain.sv:101` has `localparam L2_BANK_SIZE = 29184`, which
  contradicts `l2_ram_multi_bank.sv`. Whatever is decided, these two must agree, and the
  discrepancy should be fixed on the fork regardless.

Then the memory map: reduced L2 changes the linker script, the boot code's assumptions, and
anything upstream that hardcodes sizes from `soc_mem_map.svh`.

## Definition of done

A committed bank configuration expressed as concrete parameters, a macro count, an area
number, and an updated memory map. Enough that `gf180_interleaved_ram.sv` can be written and
`macro_placement.cfg` can be planned. This resolution graduates the floorplan work out of the
fog.

## Answer

**16 KiB, sixteen `gf180mcu_ocd_ip_sram__sram1024x8m8wm1` macros, laid out as two interleaved
channels of 4 KiB plus two private banks of 4 KiB, contiguous from `0x1C00_0000`.** Macro area
2,486,624 um2 (2.49 mm2); array footprint about 2.79 mm2 with routing channels. The private
banks survive, `NB_L2_CHANNELS` drops from 4 to 2, and no interconnect surgery is needed.

### The macro: OCD, and the foundry part is not a fallback

Measured from the LEFs in the PDK ticket 15 built, all nine macros in both families:

| macro | W x H (um) | area (um2) | KiB | mm2/KiB |
| --- | --- | ---: | ---: | ---: |
| `fd__sram64x8` | 431.86 x 232.88 | 100,572 | 0.0625 | 1.609 |
| `fd__sram128x8` | 431.86 x 268.88 | 116,119 | 0.125 | 0.929 |
| `fd__sram256x8` | 431.86 x 340.88 | 147,212 | 0.25 | 0.589 |
| `fd__sram512x8` | 431.86 x 484.88 | 209,400 | 0.5 | 0.419 |
| `ocd__sram64x8` | 301.30 x 152.21 | 45,861 | 0.0625 | 0.734 |
| `ocd__sram256x8` | 301.30 x 224.93 | 67,771 | 0.25 | 0.271 |
| `ocd__sram512x8` | 301.30 x 321.89 | 96,985 | 0.5 | 0.194 |
| `ocd__sram1024x8` | 301.30 x 515.81 | 155,414 | 1.0 | 0.155 |

Ticket 07's 2.6x is two effects, and only one of them is the process. At **equal capacity** the
OCD win is **2.16x** (`ocd 512x8` 96,985 against `fd 512x8` 209,400); the rest comes from the
1024-word part amortising its periphery over twice the depth, giving 2.70x against the largest
foundry macro. Both are real, but the map should quote 2.16x when comparing families.

Against ticket 10's 3.16 mm2 SRAM budget the foundry part does not reach a useful size: 16 KiB
needs 6.70 mm2, and even 8 KiB at 3.35 mm2 is 6% over. **4 KiB is the largest foundry
configuration that fits**, so the "size a foundry-macro fallback at the same time" instruction
in the question cannot be satisfied as intended. The fallback is a degraded mode, not an
equivalent.

The macros are otherwise near-interchangeable: pin-identical apart from `A[9]`, so one wrapper
covers both families and switching costs a parameter rather than a rewrite.

### The OCD Liberty is not characterisation, and this is the finding

The map believed, from ticket 07, that OCD timing was "simulation-derived". It is not derived at
all. **Every OCD Liberty file is a foundry Liberty file with the header swapped and the address
bus resized.** Normalising cell names away:

| OCD file | is | diff |
| --- | --- | ---: |
| `ocd__sram256x8` | `fd__sram256x8` | 11 lines, all header |
| `ocd__sram512x8` | `fd__sram512x8` | 11 lines, all header |
| `ocd__sram1024x8` | `fd__sram512x8` + `bit_width` 9 to 10 | 13 lines |
| `ocd__sram64x8` | `fd__sram256x8` + `bit_width` 8 to 6 | 17 lines |

Traced to source, and the repo says so itself. Its first commit, 18 November 2025: "Timing has
not been updated from the original yet." The spec CSVs are versioned `1.0, 2014/06/20, Release`.
The Liberty numbers match the 2014 GlobalFoundries 5 V datasheet exactly, 13.974 ns at
`ss_125C_3v00` appearing in both. There are no re-characterised Liberty files anywhere, and the
open_pdks changelog has no entry mentioning characterisation for this library.

Three concrete defects follow.

**The one piece of 3.3 V timing that exists is wrong, and it is in the gate-level model.** In May
2026 the `sram1024x8` Verilog specify block was re-derived from the spec CSVs, giving CLK->Q of
`4230 : 6215 : 7177` ps. The CSV row it read is corrupted: in the 3.3 V table for the 512 and
1024 parts, column 1 has been overwritten with column 5's value, duplicating 13.974 at both
ends. The 5.0 V and 1.8 V tables in the same file are clean, and the 64/256 tables are clean, so
the shape is unambiguous. The true worst corner, SNSP 3.0 V 125 C, is that 13.974 ns; the
recharacteriser dropped it and promoted the **typical** 25 C figure, 7.177 ns, to max. So the
model ticket 16 pinned Icarus for is **optimistic by about 2x on access time**, in the only macro
carrying 3.3 V data, at the only voltage this design uses. The other three OCD macros have no
re-derived timing at all: their specify blocks still carry the foundry's 55.6 ns cycle and 45 ns
access.

**The `area` field in every OCD Liberty is the foundry macro's area.** `ocd__sram1024x8`
declares 209,400 where the LEF says 155,414 (1.35x); `ocd__sram64x8` declares 147,212 where the
LEF says 45,861 (3.2x). Anything deriving area from Liberty rather than LEF over-reports SRAM,
`area_report.py` included once macros enter the netlist.

**`memory() { address_width }` disagrees with the pin bus on both resized parts**:
`sram1024x8` declares 9 against 10 address pins, `sram64x8` declares 8 against 6. The pin bus
itself is correct in both.

Net effect on this decision: the **density** claim is solid, because it comes from LEF geometry
and the layout is real. The **timing** claim has no support in either direction, and the honest
planning number is the copied foundry Liberty's 15.87 ns worst case at `ss_125C_3v00`, which is
close to the 13.97 ns the corrupted CSV's true worst corner implies. That is affordable against a
50 ns clock but it is a different path from ticket 10's 29.1 ns logic path and needs measuring.
This opened ticket 20.

### Manufacturability, which is the part that is verified

Variant purity passes, and this is the check that killed ticket 08. OCD's own `run_drc.sh`
invokes the klayout deck with `PDK=gf180mcuD` explicitly, `feol=True beol=True conn_drc=True
wedge=True`, deep mode. The 1024x8, 512x8 and 256x8 report **zero items**. LVS matches uniquely
on all four; the 1024x8 only against a hand-drawn schematic, since the foundry never made a
1024-word part and there is no vendor netlist to compare against.

The layout is a genuine thin-oxide redraw, not a relabel: `nfet_03v3`/`pfet_03v3` throughout
where the foundry macro is `nfet_06v0`. GlobalFoundries reviewed it through wafer.space on
2 January 2026, flagged a PP.8 enclosed-area violation that klayout's deck did not implement, and
the layout was fixed and re-validated. Every view the flow needs is present: LEF, ten Liberty
corners, GDS, SPICE for netgen, blackbox Verilog.

Physical integration is clean but constrains the floorplan. Obstruction covers Metal1 to Metal3
over the interior only, leaving a 3 um frame; power arrives as a Metal2/Metal3 ring on the
perimeter; gf180mcuD has five routing layers so **Metal4 and Metal5 are free over the macro** for
straps and over-array routing. But **every signal pin is on Metal2 in the 3 um band along the
bottom edge**, all 37 of them, so each macro presents its whole interface on one side.
`macro_placement.cfg` must give every macro a channel below it and orientation is not free. The
LEF hide setback was cut from 6 um to 3 um in May 2026 specifically because the larger value let
routers connect behind the pins.

**The 64x8 is the exception: treat it as unvalidated.** Its checked-in DRC database reports six
density items and its violation polygon is 301.3 x 224.93, which is the 256x8's outline, so the
database was inherited with everything else. It was added in June 2026 explicitly so it fits a
Tiny Tapeout tile and can start being validated, which is a plan and not a result.

Silicon exists but is a pre-fix layout. wafer.space Run 1 carried project OCD2, `ocd_sram_test`,
on a 1x0.5 slot with one 1kB, one 512B and two 256B cores pinned to GPIO. It went in before the
January 2026 layout fix.

### Floorplan arithmetic

Sixteen macros of 301.30 x 515.81 um into a 3050 x 4240 um core, as 4 rows by 4 columns:
columns 4 x 301.3 plus three 10 um gaps is 1235 um; rows 4 x 515.81 is 2063 um; each row needs a
channel below it for 4 x 37 = 148 escaping nets, which at Metal3's 0.56 um pitch is 83 um for a
full-width escape, so 50 um per channel is the planning figure. Array **1235 x 2263 um = 2.79
mm2**, 12% channel overhead on 2.49 mm2 of macro. Two rows by eight columns comes out the same
and also fits the core width; sixteen in one row does not, at 4820 um against 3050.

The channel figure is an estimate. Everything above it is measured.

**This is where it is tight.** Logic at 9.76 mm2 plus 2.79 mm2 of array is 12.55 mm2 of a
12.92 mm2 core, **97% occupancy on the template's 35% density**, which ticket 10 already flagged
as the optimistic end of Run 1 experience. **So ticket 12's cut of `apb_i2cs` is a precondition
of this configuration, not an optimisation.** At 11.3% of cell area it is worth about 1.10 mm2 of
placed logic, taking occupancy from 97% to 89%.

### Why two interleaved channels and two private banks, not four channels

The private banks are not spare capacity. Upstream puts the application there and the data in the
interleaved region: `a2_boot/main.c` jumps to `0x1C00_8080`, which is private bank 1, and
`0x1C00_0880` under Verilator, while `a2_boot/core-v-mcu2-rom.ld` puts the bootloader's own RAM
at `0x1C07_C000`, which is 448 KiB into the TCDM. Both linker scripts and both jump addresses
stop existing at 16 KiB under any configuration, so software moves regardless.

Each interleaved bank is 32 bits wide and so takes four 8-bit macros. Four channels is therefore
exactly sixteen macros with nothing left over, and keeping any private bank on top would need
24 macros (about 4.2 mm2 placed, 99.5% of core even after the i2c cut). The lever is the channel
count, not the macro size: dropping to two channels frees eight macros for the private banks at
identical capacity, area and macro count.

Reducing macro size instead does not pay. Four channels of `512x8` plus two private banks of
`512x8` is 24 macros, 2.33 mm2 of macro but about 2.76 mm2 of array once channels are counted,
for **12 KiB instead of 16**. The `512x8` is 0.194 mm2/KiB against the `1024x8`'s 0.155, so the
25% density loss cancels the saving and the extra macros bring extra channels. Same floorplan, a
quarter less program space.

**The decisive argument against dropping the private banks is that the crossbar stays anyway.**
`CONTIGUOUS_CROSSBAR_RULES` in `soc_interconnect_wrap.sv` has four entries: private bank 0,
private bank 1, the boot ROM, the eFPGA slot. The core fetches its reset vector through that
crossbar, so removing the private banks deletes two of four slave ports on a structure that must
remain, gaining nothing structural while cutting into a parameterised PULP interconnect whose
failure modes are quiet ones (a decode hole, a dangling port that synthesises away but breaks in
simulation). Keeping them costs a define and two bank sizes.

At 4 KiB per bank both wrappers are 1024 words by 32 bits, four `1024x8` macros ganged, so
`gf180_private_ram.sv` and `gf180_interleaved_ram.sv` are the same module under two names.

### Why it is the better chip for firmware

All five TCDM masters (`fc_data`, `fc_instr`, `udma_tx`, `udma_rx`, `tcdm_debug`) reach both
regions through the L2 demux, so nothing is walled off from the DMA and no bounce buffer is
needed. What the split buys is that the halves sit behind **different arbiters**: an instruction
fetch from the private half and a uDMA burst into the interleaved half never queue behind each
other. With four interleaved channels everything spreads on address bits [3:2] and a fetch and a
DMA write collide about a quarter of the time with no way for firmware to influence it.

Fragmentation is the real objection to a split, and on a 16 KiB part it would be serious: two
8 KiB islands means a 9 KiB program fits nowhere. **It dissolves by laying the regions out
adjacently**, which costs nothing because every boundary is a constant in `soc_mem_map.svh`. The
linker then sees one 16 KiB span and gives the ordinary "region overflowed" error, and the split
becomes advisory rather than structural: it guides placement without trapping it.

The firmware-facing story is then short. Text, rodata and vectors in the lower 8 KiB, where
instruction fetch has its own path to memory. Data, BSS, stack and DMA buffers in the upper
8 KiB, interleaved so consecutive words alternate banks. Spill across the line if needed. And put
the bootloader's scratch in the interleaved half while the application image loads into the
private half, so the hardware structurally prevents the bootloader from overwriting the image it
just copied in, a class of bring-up bug that is a code review away under a single pool.

### The committed configuration

Memory map, `rtl/includes/soc_mem_map.svh`:

| region | start | end | size | banks |
| --- | --- | --- | ---: | --- |
| private bank 0 | `0x1C00_0000` | `0x1C00_1000` | 4 KiB | 4 macros |
| private bank 1 | `0x1C00_1000` | `0x1C00_2000` | 4 KiB | 4 macros |
| interleaved TCDM | `0x1C00_2000` | `0x1C00_4000` | 8 KiB | 2 banks x 4 macros |

Boot ROM stays at `0x1A00_0000`. The top of L2 becomes `0x1C00_4000`.

Parameters:

| file | parameter | from | to |
| --- | --- | ---: | ---: |
| `rtl/includes/pulp_soc_defines.svh:32` | `NB_L2_CHANNELS` | 4 | **2** |
| `l2_ram_multi_bank.sv:23` | `BANK_SIZE_INTL_SRAM` | 32768 | **1024** |
| `l2_ram_multi_bank.sv:24` | `BANK_SIZE_PRI0` | 8192 | **1024** |
| `l2_ram_multi_bank.sv:25` | `BANK_SIZE_PRI1` | 8192 | **1024** |
| `soc_domain.sv:101` | `L2_BANK_SIZE` | 29184 | **1024** |

All in 32-bit words. That fixes the stale parameter the question asks about: `L2_BANK_SIZE` and
`BANK_SIZE_INTL_SRAM` now agree at 1024, and the discrepancy stops being latent.

Derived and checked: `INTL_MEM_ADDR_WIDTH` = 10, matching the macro's `A[9:0]` with nothing left
over; `PRI0_MEM_ADDR_WIDTH` = `PRI1_MEM_ADDR_WIDTH` = 10; `L2_MEM_ADDR_WIDTH` = 10, so the uDMA's
`MEM_ADDR_WIDTH` at `soc_domain.sv:292` is 11 bits for 2048 words of TCDM. `NR_L2_PORTS`
propagates from `NB_L2_BANKS` at `soc_domain.sv:403`, so the interconnect follows the define
without a second edit. `interleaved_crossbar` requires a power-of-two slave count and 2 qualifies.

`SOC_MEM_MAP_TCDM_ALIAS_START_ADDR` and `_END_ADDR` are declared but referenced nowhere in RTL;
the real aliasing is the hardcoded `0x000` to `0x1c0` prefix remap on `fc_data` in
`soc_interconnect_wrap.sv`. Leave them, but do not read them as live.

### What this hands downstream

Ticket 12 gains a precondition rather than a suggestion: `apb_i2cs` must go or this configuration
does not close. Ticket 04 gains a hard constraint and a correction: every boot address moves, and
**there is no execute-in-place path**, because the uDMA QSPI is a DMA engine with a register
interface and the AXI plug is commented out at `soc_interconnect_wrap.sv:93`, so
`docs/porting-analysis.md:174`'s "or execute in place from SPI flash" describes hardware that
does not exist. External flash changes how code arrives, not how much SRAM the chip needs.
Ticket 16's gate-level plan needs ticket 20 first. The floorplan graduates out of the fog as
ticket 21, and the wrapper work is ticket 19.

### Traps for the next session

- **Liberty `area` is unreliable for the OCD macros.** Use LEF `SIZE`. This is not a rounding
  difference, it is up to 3.2x.
- **Comparing OCD Liberty timing against foundry Liberty timing compares a file with itself.**
  Any conclusion of the form "the OCD macro is as fast as the foundry one" is circular.
- The `sram64x8` is the only OCD macro whose Liberty was not simply inherited at the same depth,
  and it is also the one with no valid DRC database and no silicon. Do not reach for it.
- `piping a spec CSV through `cut -c` truncates the multi-line quoted headers` and made the
  corrupted 3.3 V row look like a parsing artifact on first read. Parse them with `csv`.
