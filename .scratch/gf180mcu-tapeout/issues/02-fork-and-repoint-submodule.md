# Fork upstream and re-point the submodule

Type: task
Status: resolved
Blocked by: none

## Question

Where does the CORE-V MCU fork live, and on what branch does the submodule track it?

The submodule currently points at `https://github.com/openhwgroup/core-v-mcu.git` pinned at
`4608714d`, which is read-only for us. The port needs commits inside the submodule: removing
the eFPGA dependency from `core-v-mcu.core`, adding a GF180 fileset and target, changing
`N_IO` and `N_APBIO` in `rtl/includes/pulp_soc_defines.svh`, regenerating `pad_control.sv`
and `safe_domain.sv`, and fixing the stale `localparam L2_BANK_SIZE = 29184` in
`soc_domain.sv:101` that contradicts `l2_ram_multi_bank.sv`.

There is nowhere to put those commits today. OpenHW's `CONTRIBUTING.md` mandates a fork as
step one of any contribution, so the fork has to exist regardless of whether we upstream
anything, which is exactly why this repo uses a submodule rather than vendoring a patch
stack.

Secondary question worth answering in the same sitting: sign the Eclipse Contributor
Agreement now or later? It is free, it is slow, and ticket 13 cannot merge anything without
it. Signing early costs nothing.

## Definition of done

A fork exists with a working branch for this port. `.gitmodules` points at the fork over
HTTPS, so CI can clone it without credentials. `git clone --recurse-submodules` of this repo
into a fresh directory produces a checkout that builds. The local clone keeps whatever SSH
remote is convenient for pushing.

Record the fork URL and branch name in the answer, since every later ticket that touches
upstream RTL will reference it.

## Answer

**No fork, and none for the foreseeable future.** The port's commits live on the submodule's
local `master`, unpushed. This is a deliberate call by the dev driving the map: nothing from
this effort goes to a public remote until they publish it themselves. The question the ticket
asked ("where does the fork live") is answered by removing the fork, not by siting it.

What that means concretely:

- `.gitmodules` is **unchanged** and stays pointed at `https://github.com/openhwgroup/core-v-mcu.git`.
  There is nothing to re-point at. Upstream's default branch is `master`.
- The submodule checkout is on an **attached** `master` at `4608714d`, clean, tracking
  `origin/master` where `origin` is upstream over SSH. Commits made there stick. Pushing is
  a non-event since we have no write access to `openhwgroup`, so the tracking branch is a
  convenience for rebasing onto upstream, not a hazard.
- Guard applied: `submodule.core-v-mcu.update = merge` in the parent's `.git/config` (local
  config, not `.gitmodules`). Without it a plain `git submodule update` detaches HEAD and
  orphans every port commit on `master`, which is the one way this arrangement loses work.
  Nothing in `Makefile` or `run.sh` runs `git submodule update` today, so this is a guard
  against a hand-typed command, not against the build.

**The definition of done is deliberately not met, and that is the point.** The DoD asked that
`git clone --recurse-submodules` into a fresh directory reproduce a working checkout. It
cannot: the parent records a submodule commit that exists on one disk and nowhere else, and
the parent repo itself has **no remote at all**, so there is nothing to clone from either.
Reconstitution and CI both wait on a publishing decision that is out of scope for this map.
The residual risk is disk loss, accepted knowingly.

Secondary question, the Eclipse Contributor Agreement: **deferred, not declined.** It is not
needed until the work goes public. Noted for whenever that happens: the ECA bot validates the
**commit author email**, and commits here are authored as `yusefkarim@riseup.net`, so that
address has to be registered on the Eclipse account or the history needs rewriting before any
PR to OpenHW will pass. Ticket 13 now depends on a fork and an ECA that do not exist.

Facts gathered along the way, since a future publishing decision will want them: no fork of
`core-v-mcu` exists under `yusefkarim` or `riscv-ottawa` today; the dev is an **admin** of the
`riscv-ottawa` org, so either siting is available on demand; upstream is public with 78 forks
and an "Other" license. OpenHW's `CONTRIBUTING.md` mandates a fork as step one, and the
`GitCheats.md` it points at asks for `<org>_<userid>_yyyymmdd` or `<org>_<userid>_issue_<num>`
branch names, which is a *PR* branch convention and would apply to the narrow branches ticket
13 cuts, not to a long-lived port branch.
