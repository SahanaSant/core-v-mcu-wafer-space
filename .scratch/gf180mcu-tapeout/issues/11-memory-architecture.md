# Memory architecture: how much L2, in how many banks, from which macro?

Type: grilling
Status: open
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

<!-- filled on resolution -->
