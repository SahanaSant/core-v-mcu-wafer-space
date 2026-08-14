# Cut the SoC interconnect down to what this chip needs

Type: grilling
Status: resolved
Blocked by: 10, 12

## Question

Ticket 10 measured `soc_interconnect_wrap` at 1,040,079 um2, 22.0% of the design and the
second-largest block after the uDMA. It also found the critical path starting inside it, at
`i_axi_xbar.i_xbar.gen_mst_port_mux[0].i_axi_mux.gen_mux.i_aw_spill_reg`. So the interconnect
is both the area problem and the timing problem, and unlike the peripherals it cannot simply
be deleted.

Where it goes:

| | um2 | % of block |
| --- | ---: | ---: |
| i_soc_interconnect | 900,032 | 86.5 |
| &nbsp;&nbsp;i_axi_xbar | 383,084 | 42.6 of the 900k |
| &nbsp;&nbsp;i_contiguous_xbar | 230,661 | 25.6 |
| &nbsp;&nbsp;i_interleaved_xbar | 89,165 | 9.9 |
| &nbsp;&nbsp;9x gen_l2_demux | 165,514 | 18.4 |
| &nbsp;&nbsp;9x gen_tcdm_2_axi_bridge | 31,536 | 3.5 |
| i_axi_to_axi_lite | 115,891 | 11.1 |
| i_axi_lite_to_apb | 23,978 | 2.3 |

Upstream sized this for a 22FDX SoC with an eFPGA, 512 KiB of L2 in many banks, and a
cluster. This chip has none of those. The candidates, in rough order of how much they look
worth:

- **The four eFPGA master ports.** `NR_TCDM_MASTER_PORTS` is 9: FC instructions, FC data,
  uDMA RX, uDMA TX, debug, and four eFPGA. Ticket 10 confirmed the tie-off constant-folds
  them away **when the flow flattens**, and that they cost roughly 137,000 um2 of ports plus
  their share of three crossbars' arbitration when it does not. Is relying on constant
  folding across the whole design the right answer, or should `N_EFPGA_TCDM_PORTS` be
  parameterised down so the structure is never built? The second is honest and upstreamable;
  the first is free until someone changes a flow setting.
- **The AXI ID width.** `axi_burst_splitter` carries sixteen in-flight ID counters per
  channel, and `gen_counters[0]` through `[15]` are each instantiated in full. What ID width
  does this SoC actually need with one AXI master and no cluster?
- **The AXI path at all.** `i_axi_xbar` plus `i_axi_to_axi_lite` plus `i_axi_lite_to_apb` is
  522,953 um2, over half the interconnect, and it exists to reach a peripheral bus that is
  ultimately APB. Ticket 12 may cut enough peripherals to change what has to be reachable.
- **The interleaved crossbar.** 89,165 um2 of arbitration for interleaved L2 banking. If
  ticket 11 lands on a small unified L2 rather than many interleaved banks, does this
  structure still earn its place?

This is upstream RTL and the map's standing preference is to keep changes contributable, so
prefer parameterisation over deletion where upstream already provides a parameter.

## Definition of done

A decision per candidate, with the area recovered measured rather than estimated: change the
configuration, run `make area`, and quote the new flattened total. The critical path should
be re-checked with `make sta` afterwards, because the AW spill register that holds it today
may simply move somewhere else in the same crossbar.

## Answer

**No RTL change. Closed with the finding recorded, not one of the four candidates executed.**

The two problems this ticket was opened to solve are both gone. Ticket 22 (resolved after this
ticket was filed) found the AXI crossbar's AW spill register, the path this ticket's own
"timing problem" framing rests on, was never the deepest path in the design — it won a
pre-layout slack race at 35 stages, 31.2 ns, 62% of budget, while the real 89-stage, 62.3 ns
critical path lives inside the CV32E40P decoder, upstream CPU IP untouched by anything in the
interconnect. And ticket 12's peripheral cuts, also after this ticket was filed, dropped core
occupancy from the 97% this ticket was framed against to 76.4%, 3.04 mm² free. Neither the
timing case nor the area-crisis case for trimming the interconnect survives the map's own later
tickets.

Read against the actual measured state, the four candidates:

- **The four eFPGA master ports.** Ticket 10 already answered this one for the flow that's
  actually run: *"the eFPGA tie-off does fold away, but only when the flow flattens, which is
  now a flow requirement rather than a free win."* Flattening became a hard flow requirement as
  of that ticket, so every flattened total this map has quoted since (82,209 cells / 2,281,302
  um² and on) already has this structure constant-folded out for free. Parameterising
  `N_EFPGA_TCDM_PORTS` to 0 to make that explicit would touch four upstream files
  (`efpga_subsystem.sv`, `soc_peripherals.sv`, `soc_domain.sv`, `soc_interconnect_wrap.sv`,
  `NR_TCDM_MASTER_PORTS` 9→5) for a `make area` delta expected to be zero. The remaining value
  is structural honesty for an eventual upstream PR, not anything this shuttle's destination
  needs measured. Filed against ticket 13 instead, which is explicitly held until GDS sign-off.
- **The AXI ID width.** Not investigated further: it only mattered as a lever on the crossbar's
  contribution to the critical path, and the crossbar isn't on the critical path.
- **The AXI path at all.** Confirmed real on inspection — every one of the 9 TCDM master ports
  (fc_data, fc_instr, udma_tx, udma_rx, debug, 4×eFPGA) gets its own full TCDM→AXI bridge and
  its own slave port on `i_axi_xbar` in `soc_interconnect.sv`, though most of those masters
  plausibly never target the peripheral bus. But cutting it is restructuring which masters get
  an AXI path at all, not a parameter, and with 3.04 mm² of headroom and the crossbar off the
  critical path there is no pressure left to justify that risk. Left as a known lever, not a
  ticket: revisit only if ticket 21's floorplan finds routing congestion the interconnect's
  footprint is contributing to.
- **The interleaved crossbar.** Same reasoning: real structure, no current pressure to remove
  it, not pursued.

No files changed; `make area` and `make sta` were not re-run, since the DoD's premise (recover
area, fix the critical path) no longer holds for any of the four candidates.
