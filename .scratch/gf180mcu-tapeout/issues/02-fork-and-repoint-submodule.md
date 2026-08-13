# Fork upstream and re-point the submodule

Type: task
Status: open
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

<!-- filled on resolution -->
