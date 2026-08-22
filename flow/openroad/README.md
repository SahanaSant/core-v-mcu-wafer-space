# OpenROAD patches

Not built or applied automatically by anything in `Makefile`. This directory exists so the fix
found here is checked in as a real, reusable artifact rather than living only in a session's
scratch files — the same reasoning `flow/pdk/patch_ocd_sram.sh` follows for the PDK.

## `patches/0001-cts-guard-against-a-null-downstream-net-in-separateM.patch`

Fixes the crash documented in `flow/chip_top.sdc`'s header: `OpenROAD.CTS` null-dereferences in
`TritonCTS::separateMacroRegSinks` on all but roughly one attempt in a hundred. Root cause,
confirmed rather than hypothesised via a live coredump and direct inspection of the checkpoint
database (`gdb` against the exact crashing binary, plus walking every instance in the pre-CTS
`.odb` via the Tcl/odb API): TritonCTS's own
`configure_cts_characterization` phase places dummy load instances on real, already-populated
clock nets to measure delay/slew under representative fanout, deliberately leaving those
instances' output pins unconnected. `separateMacroRegSinks` later walks every sink on a net and,
for any Liberty inverter it finds, unconditionally follows the inverter's output net without a
null check — which segfaults when the inverter it's looking at is one of those dummy loads. The
patch here is a git `format-patch` against `The-OpenROAD-Project/OpenROAD` guarding that
dereference. Confirmed unpatched on two separate builds before this fix existed: the pinned
`hpretl/iic-osic-tools:2026.07` image's own OpenROAD
(`26Q3-850-gc74892e7b`), and a substantially newer build (`26Q3-1193-gec94b92b3`, 343 commits
ahead, from `hpretl/iic-osic-tools:next`) spliced in as a throwaway diagnostic image — ten
attempts, ten crashes, identical null dereference on both. A newer OpenROAD is not the fix.

**Built and applied.** The binary LibreLane's `OpenROAD.CTS` step actually invokes is
`/foss/tools/openroad-librelane/bin/openroad` — a distinct, separately-versioned build from the
plain `/foss/tools/openroad/bin/openroad` also in the image (confirmed via `coredumpctl`'s own
`Executable:` field on a live crash, not assumed). It was `26Q1-1024-gdcf36133a`, not the newer
`26Q3-850-gc74892e7b` an interactive shell's `which openroad` resolves to — an easy mistake, since
both binaries exist side by side in the image and only one is on the PATH LibreLane's own
subprocess actually uses. The patch is built against the correct commit, `dcf36133a`: its blob
hash for the unmodified file (`git hash-object src/cts/src/TritonCTS.cpp`, `42edd07a…`) matches
that exact checkout, confirming the patch applies against the real source rather than a
hand-edited approximation of it.

Built with:

```dockerfile
FROM hpretl/iic-osic-tools:2026.07 AS builder
USER root
WORKDIR /build
RUN git clone https://github.com/The-OpenROAD-Project/OpenROAD openroad \
    && cd openroad && git checkout dcf36133a \
    && git submodule update --init --recursive
COPY 0001-cts-guard-against-a-null-downstream-net-in-separateM.patch /build/
RUN cd /build/openroad && git apply /build/0001-cts-guard-against-a-null-downstream-net-in-separateM.patch
RUN cd /build/openroad && bash ./etc/DependencyInstaller.sh -all -threads=4
RUN cd /build/openroad && bash ./etc/Build.sh -no-gui -threads=4

FROM hpretl/iic-osic-tools:2026.07
COPY --from=builder /build/openroad/build/bin/openroad /foss/tools/openroad-librelane/bin/openroad
```

Compiled in 37m33s real time at `-threads=4` (kept conservative on purpose — this machine runs
with little free RAM alongside other work, and a from-scratch OpenROAD build with wider
parallelism risks OOM; `-threads=4` never came close). Fetching by full commit SHA
(`git fetch --depth 1 origin <sha>`) fails against GitHub with "couldn't find remote ref" for a
non-tip commit; a plain `git clone` followed by `git checkout <sha>` works and isn't meaningfully
slower for a repo this size. or-tools and lemon-graph, OpenROAD's two heaviest optional
dependencies, both resolved from prebuilt releases rather than a source build (`DependencyInstaller.sh`
downloads a prebuilt x86_64 or-tools tarball; the version already staged in the base image at
`/opt/or-tools` didn't match what this older commit expects, so it correctly replaced it rather
than reusing it).

**Three durable copies exist, in increasing order of how much they buy back if something needs
redoing** (kept because the compile is the expensive part — worth protecting against a container
recycle, a `podman image prune`, or storage getting reclaimed for space):

- `localhost/iic-osic-tools:cts-fix` — the podman image actually swapped in for testing (final
  stage only: the pinned base image plus the one patched binary copied over it).
- `localhost/iic-osic-tools:cts-fix-builder` — the full builder stage, explicitly tagged rather
  than left as a dangling `<none>:<none>` layer (podman's default prune targets untagged images
  first, and this one carried the whole build tree until tagging).
- `openroad-build/cts-fix/` (gitignored, at the repo root — same shape as `/pdk/`) — a plain
  filesystem copy of the builder stage's `/build/openroad`, pulled out with a bind-mounted
  `podman run` rather than left inside any image layer. 4.6 GB: 2.0 GB is the actual ninja build
  directory (`build/`, useful for a fast incremental rebuild if the patch needs iterating — ninja
  will skip every unchanged translation unit rather than rebuilding from clean), 1.2 GB is the
  full OpenROAD git history, and `build/bin/openroad` is the 91 MB compiled binary itself,
  reachable without podman or the image store at all.

**Result: clean on every attempt.** Two back-to-back isolated `OpenROAD.CTS` runs against the
patched image both passed (against an unpatched baseline crash rate of roughly 1 in 100, two
consecutive passes alone puts the odds of this being coincidence around 1 in 10,000 — a source-
level fix against a fully diagnosed, coredump-confirmed mechanism, not a config change that might
coincidentally correlate with a lucky run). A third, real end-to-end run then took the design from
CTS through the rest of the flow in one pass with no `--to` cutoff: CTS passed again, and the
design went on to complete global routing (0% overflow on every layer, 23.14% overall routing
resource usage) and detailed routing (0 DRC violations, 0 antenna violations) — the first time
this design has ever reached, let alone cleared, either step. IR drop is negligible (worst-case
26.2 µV on VDD / 29.1 µV on VSS, 0.00% of the 3.3 V rail). Post-route static timing analysis is a
separate, real problem the patch does not touch: the design does not close setup timing at the
slow corner (large WNS/TNS, widespread max-slew/max-cap violations) — that is a timing-closure
question, unrelated to this crash, and stays open.

## `upstream-issue.md`

A complete, paste-ready bug report for `The-OpenROAD-Project/OpenROAD`, written up but not filed
— opening a public issue is an outward-facing action left to the user's own judgment. Covers the
root cause above in more depth (with the supporting evidence: the coredump register state, and
the checkpoint-database walk showing all 410 characterization dummy loads with a floating output
sitting on real, shared clock nets rather than isolated ones), the same patch inline as the
suggested fix, environment details, and a best-effort reproduction shape.
