# Can c4m-arrakeen-memgen generate a usable SRAM macro?

Type: research
Status: resolved
Blocked by: none

## Question

Timebox: one day. This is an opportunity, not the critical path.

`c4m-arrakeen-memgen` can generate a native 32-bit-wide macro (`word_size=32, we_bits=4`)
that replaces four ganged foundry macros and shares periphery between them. That is a real
area win, because the periphery is a large fraction of a 512x8 macro and we currently pay for
it four times per word.

It is also blocked on several things. It caps at 512 words, so it changes the constant and
not the order of magnitude: roughly 16 KiB becomes 20 to 24 KiB, not 100 KiB. It emits no
Liberty file. It sits on a pre-alpha `c4m-pdk-gf180mcu` with roughly six weeks of GF180
support behind it. And DRC-clean output on the pinned PDK is unproven.

The ticket splits in two, because the hands-on half needs a working container and ticket 01
has not confirmed there is one.

**Desk research, doable now.** State of the dev branch and its parameter surface, read from
source rather than documentation. Whether the 512-word cap is architectural or configural.
Whether it emits a Liberty file at all. The state of `c4m-pdk-gf180mcu` and whether its
output is compatible with a design otherwise built against the official `gf180mcuD`. Any
published evidence of DRC-clean GF180 output or a tapeout using it. Any documented bitcell
or macro area giving a per-KiB figure to compare against 0.409 mm²/KiB.

**Hands-on validation, needs ticket 01 first.** Install against the pinned PDK, generate a
512x32 macro with byte write enables, run Magic and KLayout DRC on the result, and measure
its actual area.

Stop at the first hard failure. Without a Liberty file there is no static timing analysis,
and a macro that cannot be timed cannot be signed off, so that question alone may end the
ticket before anything is installed.

## Definition of done

A go or no-go with the measured area if it got that far, and the specific blocker if it did
not. A no-go answer is a good outcome; the point is to stop wondering. Feeds ticket 11.

## Answer

**No-go for December. Two independent disqualifiers, each sufficient. The hands-on half is
cancelled, not deferred to ticket 01.**

**Disqualifier one: it emits no timing model of any kind.** `_main.py` writes exactly four
outputs per run: GDS, LEF, an ngspice netlist, and a behavioural Verilog model. There is no
Liberty call anywhere in it, nor anywhere in `c4m-flexmem` or PDKMaster below it. The only
timing-related code in the stack is `TimingTestBlockT`, which builds scan-chain test
structures for measuring timing on fabricated silicon, not a simulation-derived
characterisation flow. A macro that cannot be timed cannot be signed off, and building a
characterisation flow from scratch is not a December-sized task.

**Disqualifier two: it targets the wrong PDK variant.** `dodo.py` hardcodes
`gf180mcuC`, and that is the only lettered-variant reference anywhere in the tree. There is
no `gf180mcuD` code path at all. C and D share the 5-metal stack but differ in top-metal
thickness (roughly 0.99 µm against 1.19 µm) and therefore in DRC rules, so cells drawn and
verified against C's deck are not automatically clean under D's. Variants cannot be mixed in
one tapeout, and wafer.space enforces D.

**Maturity, for completeness.** memgen is six commits and five weeks old (25 May to 1 July
2026), version `0.0.1.dev0`, no tags. Its SRAM support in `c4m-pdk-gf180mcu` only began on
28 June 2026, and that project's two most recent commits both show failed CI. It pins
PDKMaster to an unmerged, actively-moving `dev_SRAM` fork rather than a release.
`c4m-flexmem` self-describes as "experimental code with no backwards compatibility
guarantees whatsoever". No published DRC-clean output, no tapeout, no talk.

**What was confirmed on the way.** The width idea is at least expressible: `word_size=32,
we_bits=4` satisfies the constraints (`word_size % we_bits == 0` and `word_size // we_bits
>= 8`). The 512-word cap is real but is a current-configuration limit, not architectural.
Both `SPSRAMFactory.block()` and `DPSRAMFactory.block()` raise `NotImplementedError` outside
the literal tuple `(128, 256, 512)`, because the row decoder is built from hand-picked
`DecoderSpecification` tuples, one per supported depth. The machinery underneath is
parametric, so extending it is possible but is real engineering.

No area figure could be obtained. The bitcell is generated procedurally from transistor
widths and design rules, with no fixed pitch or macro-area constant in source or docs, so a
per-KiB number requires running the generator and measuring the GDS.

**Revisit only for a post-December tapeout**, and only if upstream ships a Liberty path and
a `gf180mcuD` target. Ticket 07's OCD macros deliver a 2.6x density improvement today, with
Liberty, silicon and `open_pdks` integration, which is the lever this ticket was hoping to
find.
