# Clock frequency selection

Quick-reference for the `CLOCK_PERIOD` decision. Update the **Decision** section below
whenever this gets re-litigated; keep the rest as a stable reference. Full narrative and
measurements live in ticket 29 (`.scratch/gf180mcu-tapeout/issues/29-close-post-route-timing.md`).

## The numbers

- **Original target**: 100 ns / 10 MHz (ticket 05). External oscillator, never burned into
  silicon — a budget choice, not a hard constraint.
- **Real post-route critical path** (ticket 26/29, `ss_125C_3v00`, the slow corner): **~128.6 ns**.
  Source: CV32E40P decoder, `instr_rdata_i[21]` flop fanning out to many decode comparators —
  structural to how a decoder works, not a placement accident.
- **100 ns is 29% over that** — WNS -28.59 ns, 9,127 setup violations, all at the slow corner.
  OpenROAD's own resizer already tried and gave up (`[RSZ-0062] Unable to repair all setup
  violations`).
- **Candidates**, both standard crystal frequencies:
  | Period | Freq | Utilisation | Margin |
  |---|---|---|---|
  | 166.67 ns | 6 MHz | 77% | 23% |
  | 200 ns | 5 MHz | 64% | 36% |
- 166.67 ns / 6 MHz matches the ~75-80% utilisation ticket 24 targeted pre-layout, so it's the
  first candidate tried.

## Software dependency

One confirmed hardcoded reference: `sw/bootrom/spi.c`'s `PERIPH_CLK_HZ` (derives the boot SPI
clock divisor from `periph_clk`, which is `ref_clk_i` undivided — ticket 05). Grep for
`10000000\|CLOCK_PERIOD\|PERIPH_CLK_HZ` before changing the frequency again; nothing else in
`sw/` or `rtl/chip/` was found hardcoded to the old value (UART/SDIO/PWM take divisors at
runtime).

## Where the runtime goes (why a `make harden` run takes ~2.5-3h before routing)

Two `OpenROAD` steps dominate. Measured across three back-to-back 10 MHz runs, byte-identical
config, all landing within a minute or two of each other — this part is *not* the source of the
run-to-run variance, it's just consistently slow:

| Step | What it does | Clock-dependent? | 10 MHz duration | 6 MHz duration |
|---|---|---|---|---|
| `RepairDesignPostGPL` | Fixes max-cap/max-slew (electrical) violations on unbuffered high-fanout nets (clock, reset, etc.) | **No** — this is electrical DRC repair, not setup-timing repair | 62-64 min, inserts 64,734 buffers | Same: 63 min, same 64,734 buffers |
| `ResizerTimingPostCTS` | Repairs setup/hold timing violations against the SDC clock period | **Yes** | 40-42 min, fights 6,274/6,274 violating endpoints, ends with `RSZ-0062` (doesn't fully close) | 9.5 min, 1,203/1,203 endpoints, **no `RSZ-0062`** — fully closes |

Takeaway: don't expect a lower clock to shrink the whole run. `RepairDesignPostGPL`'s cost is
structural (the RTL's own unbuffered fanout) and stays fixed regardless of frequency;
`ResizerTimingPostCTS` is the one that actually responds to the clock target.

## Global routing's separate, mostly-root-caused variance

`OpenROAD.GlobalRouting` (after CTS/resizer, before detailed routing) has shown **1m05s to 4+
hours** across otherwise-identical runs — a different problem from the table above, and
**independent of clock frequency**: this run (6 MHz) hit 4+ hours too, same as the worst 10 MHz
samples.

**Confirmed mechanism, live from a 6 MHz run's log** (`RUN_2026-08-17_16-21-08`,
`34-openroad-globalrouting/openroad-globalrouting.log`): the "extra iterations to remove
overflow" loop (`-congestion_iterations $GRT_OVERFLOW_ITERS`, LibreLane default **50**, never
overridden in `flow/config.yaml`) doesn't run once — it **restarts from iteration 1 every time
it disables NDR (non-default routing rule) on one congested net**, then grinds through up to 50
more. This design has **73 `delaynet_*_clk_PAD` nets** (a delay-matching/hold-fix chain on the
clock net); after 3 restart cycles and 4+ hours, only 2 of 73 had been cleared. However many of
the 73 end up congested for a given placement — which plausibly varies run to run — directly
sets the total wall time. This is consistent with, and likely the concrete instance of, the
general mechanism OpenROAD's own maintainers describe for long GRT runs (GitHub discussion
[#2889](https://github.com/The-OpenROAD-Project/OpenROAD/discussions/2889): overconstrained
timing → excess buffering → high density → many overflow iterations; issue
[#3336](https://github.com/The-OpenROAD-Project/OpenROAD/issues/3336): an unresolved "stuck for
days" report on the same GRT-0101/0102 loop, closed stale, no upstream fix).

**Applied and measured: capping `GRT_OVERFLOW_ITERS` works, and the right number is much lower
than "10-15."** Same 6 MHz run, resumed twice from the post-CTS checkpoint (`--last-run --from
OpenROAD.GlobalRouting`, no need to redo CTS or either resizer pass):

| `GRT_OVERFLOW_ITERS` | Time per net disabled | Time for all 73 |
|---|---|---|
| 50 (LibreLane default) | 4+ hours (only 2/73 cleared when abandoned) | would be days |
| 12 | **8m12s, exactly, every single time** | ~10 hours |
| 3 | **~25s, every single time** | ~30 minutes |

The striking finding: at every cap tried, the router disables NDR on the nets in the same order
(mostly descending `delaynet_N_clk_PAD`, occasionally a real clock-tree net like
`clk_PAD2CORE`) regardless of how many iterations it's given per cycle. That means the iteration
count isn't buying real convergence attempts, it's just how long the router grinds before
conceding on whichever net was already going to lose NDR — so a much lower cap doesn't change
*which* nets end up NDR-disabled, only how much time is wasted finding that out. **3 is what's
running now; there was no sign of diminishing returns going this low, and given `GRT_ALLOW_CONGESTION:
true` already accepts the quality tradeoff at any cap, there's no reason to keep it higher.**

Not applied: reducing the 73 `delaynet_*_clk_PAD` nets in the first place (via
`PL_RESIZER_HOLD_SLACK_MARGIN`/`GRT_RESIZER_HOLD_SLACK_MARGIN`) would need to restart from
placement, not just resume routing, so it's a real lever left for later if routing quality
(rather than just wall-clock time) ever becomes the concern — the cap fix above already solves
the runtime problem this ticket was chasing. Also not ruled out: non-deterministic buffer
*placement* between otherwise-identical runs (OpenROAD's resizer/CTS code iterates pointer-keyed
`unordered_set`s elsewhere in this codebase, confirmed root cause of the CTS crash, tickets
25/26) as the reason *how many* of the 73 end up congested might vary run to run, even though
this run showed the disable *order* is deterministic once congestion exists.

**Note this is a separate question from clock frequency** — `RepairDesignPostGPL`'s buffer
count (the other density contributor) is clock-independent (see table above), so 6 MHz alone
was never going to fix this; `GRT_OVERFLOW_ITERS` is what did.

## Decision

**Status: pending.** A live run at 166.67 ns / 6 MHz is validating both timing closure and
whether it changes global-routing's runtime. Update this section once it's done:

<!-- fill in: kept 10 MHz / dropped to 6 MHz / dropped to 5 MHz, real post-route STA numbers,
     real GRT duration, and the reasoning -->
