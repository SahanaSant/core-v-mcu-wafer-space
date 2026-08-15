# Get the design through detailed routing

Type: task
Status: open
Blocked by: none

## Question

Ticket 25 built `chip_top`, the whole LibreLane configuration and the macro placement, and got
the design as far as a legalised placement with a clean power grid: 40.9% overall utilisation,
25.9% standard cells before design repair and 43.5% after, against a 35% target. What it could
not do is finish the run, and the reason is a tool crash rather than anything about the design.

**`OpenROAD.CTS` null-dereferences on this design on all but roughly one attempt in a hundred**,
in `dbNet::get1stSignalInput` called from `separateMacroRegSinks`. It is intermittent: ticket
25 saw one pass and then about forty failures against a byte-identical configuration and the
same placement database, which is why every configuration-level "fix" it tried turned out to
be a lucky run. The stack trace, the things that were tried, and the two clock constraints
that are currently left out because of it are all written down in `flow/chip_top.sdc`'s
header.

What has to happen:

- **Get past CTS.** `make harden-cts` retries the step until it survives, resuming the
  previous run; continue afterwards with
  `make harden ARGS="--last-run --from OpenROAD.STAMidPNR-1"`. That is the brute-force route
  and it is known to work in principle, since the step does pass sometimes. The better answer
  is to find out why. `separateMacroRegSinks` builds an `unordered_set<dbMaster*>` of macro
  masters and this design hands it twenty-one macros, sixteen SRAMs and **five `gf180mcu_ws_ip__*`
  marker cells that have no pins at all** — a pinless master is exactly the shape that would
  make `get1stSignalInput` return null, and pointer-keyed set ordering is exactly the shape
  that would make it intermittent. That is a hypothesis, not a finding: test it before acting
  on it, for instance by checking whether the crash rate changes with the marker cells absent
  from `macros.yaml`.
- **Route.** Global routing, detailed routing, and the antenna repair iterations
  `flow/config.yaml` already configures.
- **Quote the real numbers**: routed density against the 35% target, whether it routed at that
  target or needed a different one, DRC violation counts, and any `MAGIC_GDS_FLATGLOB` patterns
  discovered by running into false errors — which ticket 25's DoD asked for and could not
  supply, since the run never reached Magic DRC.
- **Look at the 48 `PDN-0110` warnings**, three per SRAM macro, at the macro boundaries. They
  are `flow/pdn/pdn_sram.tcl`'s Metal4 stripe geometry not landing perfectly on the OCD
  macro's Metal2/Metal3 rings. The power grid checker passes regardless, so this is a quality
  question rather than a blocker, but it should be understood rather than carried forward
  unexamined.
- **Check IR drop.** The breakout PCB fixes the core supply at two VDD and two VSS pads
  (ticket 25 superseded ticket 18's provisional 5/5/4/4 with the template's 6/8/2/2), which is
  not many for a design that now places 222,437 instances. `OpenROAD.IRDropReport` is in the
  flow and its output has never been read.

Two things worth knowing before starting. Whichever run this resumes, `--last-run --from` is
how to avoid repeating the nine-minute synthesis and the forty-five-minute design repair. And
per ticket 25's own lesson: on this design a single pass or a single failure of a physical
step is not evidence, so give anything that looks like a fix twenty-plus attempts before
believing it.

## Definition of done

`make harden` completes through detailed routing with no fatal errors, with the numbers above
quoted from the run rather than predicted. Sign-off is a separate matter: this closes when the
design routes, not when it passes precheck.

## Answer

<!-- filled on resolution -->
