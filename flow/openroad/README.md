# flow/openroad/

The OpenROAD source patch that fixes the `OpenROAD.CTS` crash on this design, checked in as a
real artifact rather than left in a session's scratch files. Nothing in the `Makefile` builds
or applies it automatically.

- `patches/0001-cts-guard-against-a-null-downstream-net-in-separateM.patch` — the fix, a
  `git format-patch` against `The-OpenROAD-Project/OpenROAD`.
- `upstream-issue.md` — a complete, paste-ready bug report. Written but not filed.

The crash and its root cause: [docs/explanation/known-issues.md](../../docs/explanation/known-issues.md).
Building the patched image: [docs/how-to/patched-openroad.md](../../docs/how-to/patched-openroad.md).
