# Build the patched OpenROAD image

On the stock toolchain image, `OpenROAD.CTS` crashes on this design on all but roughly one
attempt in a hundred. The cause is understood and there is a one-line source fix, checked in
at [flow/openroad/patches/](../../flow/openroad/patches/). Building it once turns clock tree
synthesis back into an ordinary step.

The crash mechanism is in [known-issues.md](../explanation/known-issues.md). This page is
just the build.

## Which binary to patch

LibreLane's `OpenROAD.CTS` step invokes `/foss/tools/openroad-librelane/bin/openroad`, which
is a **different, separately versioned build** from the `/foss/tools/openroad/bin/openroad`
that an interactive shell's `which openroad` resolves to. Both exist side by side in the
image. Patching the wrong one changes nothing and looks like the fix failed.

In the pinned `2026.07` image the LibreLane binary is commit `dcf36133a`. Confirm the patch
applies against that exact source rather than an approximation of it:

```sh
git hash-object src/cts/src/TritonCTS.cpp   # expect 42edd07a…
```

## The Dockerfile

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

Build it as `iic-osic-tools:cts-fix`, then point any target at it:

```sh
make harden OSIC_IMAGE=iic-osic-tools:cts-fix
```

## Notes from doing it

- About 38 minutes at `-threads=4`. That is deliberately conservative: a from-scratch
  OpenROAD build with wider parallelism risks OOM on a machine running anything else.
- Fetching by full commit SHA (`git fetch --depth 1 origin <sha>`) fails against GitHub with
  "couldn't find remote ref" for a non-tip commit. A plain clone then `git checkout <sha>`
  works and is not meaningfully slower for a repository this size.
- or-tools and lemon-graph resolve from prebuilt releases rather than a source build.
  `DependencyInstaller.sh` downloads a prebuilt or-tools tarball; the version staged in the
  base image at `/opt/or-tools` does not match what this older commit expects, so it
  correctly replaces it.
- Keep the builder stage tagged (`iic-osic-tools:cts-fix-builder`) rather than leaving it as
  a dangling layer. Podman's default prune targets untagged images first, and the compile is
  the expensive part. Pulling `/build/openroad` out to a plain directory with a bind-mounted
  `podman run` gives a third copy that survives losing the image store entirely; the ninja
  build directory in it makes an incremental rebuild fast if the patch ever needs iterating.

## Does it work

Yes. Against an unpatched baseline crash rate of roughly 1 in 100, two consecutive isolated
CTS runs passed, and a third full end-to-end run took the design from CTS through global
routing (0% overflow on every layer), detailed routing (0 DRC, 0 antenna violations) and
sign-off in one pass.

A newer OpenROAD is not the fix: a build 343 commits ahead crashed ten times out of ten with
the identical null dereference.

## Filing it upstream

[flow/openroad/upstream-issue.md](../../flow/openroad/upstream-issue.md) is a complete,
paste-ready bug report for `The-OpenROAD-Project/OpenROAD`, with the coredump evidence, the
checkpoint-database walk, the patch inline and a reproduction shape. It has not been filed;
opening a public issue is left to whoever wants to.
