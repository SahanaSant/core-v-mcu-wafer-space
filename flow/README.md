# flow/

Physical implementation: LibreLane configuration, timing constraints, PDN, macro placement,
and the standalone synthesis and measurement scripts.

Run it with `make harden` from the repository root. Outputs land in `runs/` and `final/`,
both gitignored.

- What each file is and which settings matter: [docs/reference/flow.md](../docs/reference/flow.md)
- How to drive a run and sign it off: [docs/how-to/harden.md](../docs/how-to/harden.md)

Each configuration file carries its reasoning in its own header, next to the setting it
explains. Read those before changing anything.
