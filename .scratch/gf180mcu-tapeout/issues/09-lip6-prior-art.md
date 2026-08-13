# What did lip6/core-v-180-mcu actually get working?

Type: research
Status: resolved
Blocked by: none

## Question

`lip6/core-v-180-mcu` is the closest prior art that exists: LIP6 have CV32E40P through Yosys,
Coriolis and `c4m-pdk-gf180mcu`, using sv2v and svase as the SystemVerilog front end, and
they produce GDS in GitHub Actions CI. It surfaced late in the original research and has not
been examined properly.

This ticket is deliberately early and unblocked because it may collapse ticket 03 entirely.
Somebody has already fought the front-end battle on this exact core in this exact process.

Establish:

- What is in scope for them: bare CV32E40P, or a SoC with memory and peripherals?
- The exact front-end invocation. Which sv2v and svase versions, what preprocessing, what
  patches to upstream RTL, and what does their CI run end to end?
- What did they cut to make it fit, and what area did they land at?
- Memory: what did they use, and did they hit the same density wall?
- Do they use `c4m-pdk-gf180mcu` because it was necessary, or by preference? We are pinned to
  the wafer.space `gf180mcuD` via Ciel, so a hard dependency on the C4M PDK would not
  transfer.
- Licence and provenance, since anything reused has to be compatible with Apache-2.0 WITH
  SHL-2.1.

## Definition of done

A summary of what transfers, what does not, and specifically whether their front-end recipe
can be lifted directly. If it can, say so loudly in the answer so whoever takes ticket 03
reads it first.

## Answer

**Much less than advertised, and the premise of this ticket was wrong. It does not collapse
ticket 03. But the search found something better.**

Correcting the record first: the earlier research characterised `lip6/core-v-180-mcu` as
"producing GDS in GitHub Actions CI". GitHub's API reports **zero recorded workflow runs for
that repository, ever**, despite the workflow being active since September 2023. The recipe
to attempt a GDS exists. There is no public evidence it has ever completed. The README's
runtime claims cannot be corroborated and probably describe local runs.

What it actually is: a single-author engineering sketch by Jean-Paul Chaput (LIP6, the
Coriolis maintainer), last pushed January 2024, one star, no forks, no issues. It builds
**only `cv32e40p_core`**, the bare CPU. `dodo.py` hardcodes `buildCv32 = True`; the branch
that would build the full `core_v_mcu` SoC exists in source but is never exercised. The
"chip" is a synthetic pad frame wrapped around the bare core's ports. No memory map, no
peripherals, no SRAM, so they never met the density problem that dominates our design.

Its `dodo.py` also carries `# KO` annotations against several targets, including
`cv32e40p_core` itself, which is the active, uncommented `topName`. Whether that comment is
stale or current cannot be determined from the repository.

**And there is no LICENSE file.** GitHub reports `"license": null`, with 404s on every
conventional filename. Default copyright applies, so nothing from it can be reused without
Chaput's permission. That is independent of Apache-2.0 compatibility; there is simply no
grant to compare against. He is active and reachable in the open-EDA community if the recipe
is wanted.

### What does transfer

Small, but genuinely useful, and free:

- Stock `openhwgroup/core-v-mcu` RTL needed **no source patches** at core scope. Their fork
  at the pinned SHA is an unmodified mirror. All workarounds are file-level exclusions done
  in Python.
- The exclusion list as a starting checklist: drop `cv32e40p_register_file_latch` in favour
  of the flip-flop variant, drop `cv32e40p_prefetch_controller_sva` and other SVA, drop
  `cv32e40p_core_log`. Scaling to the full SoC additionally means dropping `fpga`, `_latch`,
  `simulation` and `deprecated` paths and `apb_efpga_demux`.
- Defines: `TOVERILOG`, `SYNTHESIS`, `DISABLE_EFPGA`. That last one matters, since it means
  upstream already has a supported way to compile the eFPGA out.

Everything from `Blif2Vst` onward is Coriolis-specific and does not map to OpenROAD. Their
PDK binding is a hard dependency on the pre-alpha PDKMaster-packaged `c4m-pdk-gf180mcu`,
not our official `gf180mcuD` via Ciel. The workflow does check out `google/gf180mcu-pdk`,
but no build step references it; it is vestigial.

### The better find: Basilisk

ETH Zürich and Bologna's **Basilisk** is far stronger evidence for our candidate front-end
path (b) than anything in the LIP6 repo. "Insights from Basilisk: Are Open-Source EDA Tools
Ready for a Multi-Million-Gate, Linux-Booting RV64 SoC Design?" (arXiv:2405.04257, with
companions arXiv:2406.15107 and arXiv:2505.10060).

It builds Cheshire through exactly our path (b), **Bender, Morty, SVase, sv2v, Yosys with
ABC, then OpenROAD**, on IHP's open 130 nm PDK. It is a real tapeout: zero DRC violations,
77 MHz, 1.1 MGE of logic (down from a 1.8 MGE naive baseline), 172 KiB of SRAM in 24 macros,
55% core utilisation. It is CVA6-based rather than CV32E40P, but it draws on the same PULP
vendor ecosystem (`common_cells`, `register_interface`, `riscv-dbg`) that sits in CORE-V
MCU's own `rtl/vendor` tree.

The QoR did not come free: it needed a custom Yosys and ABC synthesis script, a hand-built
arithmetic macro-operator library, and OpenROAD placement and routing tuning. All of that is
documented and applies to our flow regardless of PDK. **This paper is required reading for
whoever takes ticket 03**, and the 1.8 to 1.1 MGE reduction is directly relevant to
ticket 10's area measurement.

A 2020 OpenTitan write-up is a third, unrelated sv2v precedent of lesser relevance. No other
CV32E40P, PULPissimo or CORE-V MCU attempt on SKY130 or GF180 was found.
