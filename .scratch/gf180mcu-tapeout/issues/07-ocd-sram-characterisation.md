# Is gf180mcu_ocd_ip_sram a denser alternative to the foundry SRAM?

Type: research
Status: resolved
Blocked by: none

## Question

The foundry macro `gf180mcu_fd_ip_sram__sram512x8m8wm1` costs 0.409 mm² per KiB. Against
12.92 mm² of core area on a 1x1 slot, that is the constraint that shapes the entire design:
16 KiB of L2 eats 6.70 mm², and 32 KiB does not fit at all.

The `gf180mcu_ocd_ip_sram` 3.3 V blocks, including a 1 KiB block, went out on wafer.space
Run 1, and characterisation results are due at ORConf 2026 (11 to 13 September, Ghent). If
they are denser and silicon-validated, that is the single biggest lever available on how much
memory this chip gets, and it lands three months before the Run 3 deadline.

Establish:

- Are the Run 1 results published, and do the blocks work?
- Area per KiB, compared against 0.409 mm²/KiB.
- Is there a Liberty file? Without characterised timing there is no static timing analysis,
  and a macro we cannot time is a macro we cannot sign off.
- Are there LEF and GDS views usable with the pinned `gf180mcuD`?
- Voltage: these are 3.3 V blocks. Does that fit alongside a 5.0 V standard-cell library, or
  does it force a supply decision?

ORConf is roughly a month out from charting. If results are not yet published, say so
explicitly, record what is known today, and name the date to re-check rather than guessing.

## Definition of done

A clear verdict with numbers, or an explicit "not yet known, re-check on <date>". Feeds
ticket 11.

## Answer

**Roughly 2.6x denser than the foundry macro, silicon-functional, and it drags a core supply
voltage decision into the open. Plan around it, but do not sign off on it yet.**

The library is real and maintained: `github.com/RTimothyEdwards/gf180mcu_ocd_ip_sram`,
Apache-2.0, Open Circuit Design. It is a fixed set of four macros, not a compiler:
`sram64x8m8wm1`, `sram256x8m8wm1`, `sram512x8m8wm1`, `sram1024x8m8wm1`. All are 8 bits wide
with a byte write mask, so a 32-bit word still means ganging four of them, exactly as with
the foundry part. Each is a community port of the GF 5 V bitcell down to 3.3 V devices, done
outside GlobalFoundries. It has been an optional library in `open_pdks` for GF180MCU since
November 2025, with fixes landing through June 2026.

Area, taken from the `SIZE` line of each LEF:

| Macro | Size | Area | Per KiB |
| --- | --- | --- | --- |
| `sram1024x8m8wm1` | 301.300 × 515.810 µm | 0.1554 mm² | **0.155 mm²/KiB** |
| `sram512x8m8wm1` | 301.300 × 321.890 µm | 0.0970 mm² | 0.194 mm²/KiB |
| `sram256x8m8wm1` | 301.300 × 224.930 µm | 0.0678 mm² | 0.271 mm²/KiB |
| `sram64x8m8wm1` | 301.300 × 152.210 µm | 0.0459 mm² | 0.734 mm²/KiB |

Density improves sharply with depth as the decoder and sense amps amortise, so the 1 KiB
macro is the one that matters. Against the foundry macro's 0.409 mm²/KiB that is a 2.6x
improvement, and it changes the shape of the whole design:

| L2 | Foundry macro | OCD 1 KiB macro |
| --- | --- | --- |
| 16 KiB | 6.70 mm², 52% of core | 2.49 mm², 19% of core |
| 32 KiB | 13.4 mm², does not fit | 4.97 mm², 39% of core |

So 32 KiB becomes reachable where it previously did not fit at all. Banking glue for
address decode and output muxing is extra, but it is small and we already need it for the
foundry part.

**Silicon status is good but shallow.** wafer.space Run 1 carried project OCD2
(`ocd_sram_test`, half slot) with one 1 KiB, one 512 B and two 256 B cores pinned to GPIO,
plus OCD1 exercising the same library. Wafers arrived 19 April 2026. Edwards' ORConf 2026
abstract states plainly that "all circuits are functional". That is a go/no-go statement,
not characterisation data.

**Liberty exists, but it cannot be silicon-correlated.** Ten PVT corners per macro, five at
3.3 V nominal and five at 1.8 V. The files are dated 11 December 2025 and `open_pdks` called
them final on 3 December 2025, which is four months before silicon existed. They are
therefore simulation-derived by construction. Nothing in the repo claims re-characterisation
since. LEF, GDS, SPICE and behavioural Verilog are all present.

**There is no 5.0 V corner at all.** This is the consequential finding, and it is bigger
than it looks. The agent reports that `gf180mcu_fd_sc_mcu7t5v0`, despite the `5v0` in its
name, ships Liberty across three voltage families including 3.3 V (3v00/3v30/3v60). If that
holds, running the digital core at 3.3 V drops the OCD SRAM in with a matched supply and no
level shifters. Running at 5.0 V forces a level shifter at every SRAM boundary, because the
SRAM has no 5.0 V corner to fall back on. That is a core power architecture decision, not an
IO-domain detail, and it is now **ticket 14**. Ticket 01 should confirm the standard-cell
corner list directly from the pinned PDK, since the whole argument rests on it.

**Open gaps.** Nobody has confirmed the library against `gf180mcuD` specifically as opposed
to GF180MCU generically, so variant compatibility needs a hands-on check. Issue #3 (opened
27 May 2026, still open) reports that the macro LEFs declare `ANTENNADIFFAREA` on inputs but
not `ANTENNAGATEAREA`, which is an antenna-rule completeness gap that will matter at
routing. No measured timing, power or yield data is published anywhere as of 12 August 2026.

**Re-check after 13 September 2026**, for Edwards' talk "Finally Testing Silicon Again:
Chipalooza and Wafer.Space!" and Leo Moser's "A Look Back at Two Successful wafer.space
Shuttle Runs", both on the ORConf 2026 programme in Ghent.

Recommendation carried into ticket 11: plan the memory around 0.155 mm²/KiB, but keep a
foundry-macro fallback sized and do not commit the floorplan until either the ORConf data
lands or someone builds against the pinned PDK.
