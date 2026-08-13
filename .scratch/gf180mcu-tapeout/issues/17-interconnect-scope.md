# Cut the SoC interconnect down to what this chip needs

Type: grilling
Status: open
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

<!-- filled on resolution -->
