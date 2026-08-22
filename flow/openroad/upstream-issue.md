<!--
Draft for a new issue on github.com/The-OpenROAD-Project/OpenROAD. Not filed by this session —
opening a public issue is left to the maintainer's own judgment. Everything below the title is
meant to be pasted as the issue body as-is.
-->

# TritonCTS null-derefs in `separateMacroRegSinks` when a clock net carries a characterization dummy load

## Summary

`clock_tree_synthesis` intermittently (roughly 1 run in 100, on the design that found this)
segfaults in `TritonCTS::separateMacroRegSinks` at
`src/cts/src/TritonCTS.cpp:1499-1501` (commit `c74892e7b`):

```cpp
if (libertyCell && libertyCell->isInverter()) {
  odb::dbITerm* invertedTerm
      = inst->getFirstOutput()->getNet()->get1stSignalInput(false);
  nonSinkMacro &= invertedTerm->getInst()->isBlock();
}
```

`inst->getFirstOutput()->getNet()` returns `nullptr`, and the subsequent
`->get1stSignalInput(false)` call dereferences it.

## Root cause

`separateMacroRegSinks` walks every `dbITerm` on a clock net to classify its sinks into macro and
register buckets. For any input `dbITerm` whose instance's Liberty cell qualifies as an inverter,
it assumes that inverter is a real pass-through clock-tree stage and follows its output to the
next net downstream, to decide whether that inverter is driving a macro.

That assumption doesn't hold for the dummy load instances `configure_cts_characterization`
creates (named with `CtsOptions::getDummyLoadPrefix()`, `"clkload"` by default,
`src/cts/src/CtsOptions.h:304,403`). Those instances are placed on real, already-populated clock
nets specifically to measure buffer/inverter delay and slew under representative fanout — their
*input* pin is wired onto a genuine net that also carries real register clock pins, and their
*output* pin is deliberately left unconnected, since they exist to be loads, not drivers.

When `separateMacroRegSinks` is later called on one of those same nets and its iteration over
`net->getITerms()` reaches the dummy load's input `dbITerm`, it sees a Liberty inverter, follows
`getFirstOutput()->getNet()`, gets `nullptr` (the dummy's intentionally-unconnected output), and
crashes on the following `->get1stSignalInput(false)`.

The intermittency comes from two independently nondeterministic selections needing to coincide:
which real clock nets `configure_cts_characterization` happens to pick for a dummy load, and
which nets `separateMacroRegSinks` happens to reprocess during tree construction. Both ride on
`unordered_set`/`unordered_map` iteration order over pointer-keyed containers in OpenDB, which is
why the crash rate is low but consistent and doesn't correlate with anything about the design
itself (verified: not the SDC, not clock groupings, not any `CTS_*` tuning knob, not the presence
of pin-less marker/decal cells, not a newer OpenROAD build — `26Q3-1193-gec94b92b3` crashes
identically to the pinned `26Q3-850-gc74892e7b`).

## Evidence

- **Live coredump.** `gdb` against the crashing binary shows the fault at
  `odb::dbNet::get1stSignalInput(bool)+26`, called from `separateMacroRegSinks`, with `rdi`
  (the `this` pointer, i.e. the `dbNet*` receiver) equal to `0x0` at the fault — confirming the
  null is the *net*, i.e. `getFirstOutput()->getNet()` returned `nullptr`, not that
  `get1stSignalInput`'s return value was the one later dereferenced unchecked (both are
  unguarded in the source; the coredump shows which one actually fires first).
- **Direct database inspection.** Loading the checkpoint database every crashing run in our
  case operates on and walking every instance via the Tcl/odb API: 974 instances have an output
  `dbITerm` whose `getNet()` is `NULL`; 410 of them are Liberty inverters, and every single one
  is named `clkloadNNN` — TritonCTS's own characterization-dummy naming, matching the
  `[INFO CTS-0049] Characterization buffer is <cell>.`-style log lines the same run emits.
- **Every one of those 410 sits on a real, shared clock net.** Checked the net feeding each
  dummy's input pin: zero are on an isolated/private net (≤2 `dbITerm`s, the shape a clean
  characterization setup would use); all 410 are on a `clknet_leaf_NNN_<hierarchical-path>` net
  carrying anywhere from 4 to 12+ other, genuine `dffrnq`/`dffsnq` clock-pin `dbITerm`s.

## Suggested fix

Guard the output net and the result of `get1stSignalInput()` before dereferencing either, and
leave `nonSinkMacro` as already computed from `isSink()` when either is null rather than
assuming a downstream net always exists. Patch attached (against `c74892e7b`, applies cleanly
against later commits including `ec94b92b3` — tested):

```diff
--- a/src/cts/src/TritonCTS.cpp
+++ b/src/cts/src/TritonCTS.cpp
@@ -1495,9 +1495,22 @@ bool TritonCTS::separateMacroRegSinks(
       sta::Cell* masterCell = network_->dbToSta(mterm->getMaster());
       sta::LibertyCell* libertyCell = network_->libertyCell(masterCell);
       if (libertyCell && libertyCell->isInverter()) {
-        odb::dbITerm* invertedTerm
-            = inst->getFirstOutput()->getNet()->get1stSignalInput(false);
-        nonSinkMacro &= invertedTerm->getInst()->isBlock();
+        // The inverter's output pin may be legitimately unconnected: CTS's
+        // own characterization phase (configure_cts_characterization)
+        // places dummy "<dummyload_prefix_>NNN" instances (see
+        // CtsOptions::getDummyLoadPrefix) on real clock nets to measure
+        // delay/slew under representative fanout, and those instances'
+        // outputs are deliberately left floating. Treating every Liberty
+        // inverter found on a net as a real pass-through stage with a
+        // valid downstream net null-derefs on exactly that case.
+        odb::dbITerm* outputTerm = inst->getFirstOutput();
+        odb::dbNet* outputNet = outputTerm ? outputTerm->getNet() : nullptr;
+        if (outputNet) {
+          odb::dbITerm* invertedTerm = outputNet->get1stSignalInput(false);
+          if (invertedTerm) {
+            nonSinkMacro &= invertedTerm->getInst()->isBlock();
+          }
+        }
       }
 
       if (hasInsertionDelay(inst, mterm) || nonSinkMacro || inst->isBlock()) {
```

An alternative, more targeted fix would exclude instances matching `getDummyLoadPrefix()` from
`separateMacroRegSinks`'s sink walk entirely, mirroring the existing `isTimingBuffer` skip already
in the function for a different class of non-sink instance. We didn't take that approach because
it re-introduces a name-prefix dependency the null guard doesn't need, but a maintainer more
familiar with the intended invariants here may prefer it.

## Environment

- OpenROAD `26Q3-850-gc74892e7b` (pinned in `hpretl/iic-osic-tools:2026.07`); also reproduced on
  `26Q3-1193-gec94b92b3` (343 commits ahead, from `hpretl/iic-osic-tools:next`).
- LibreLane 3.1.0.dev2.
- Design: a ~222k-instance RISC-V SoC on GF180MCU (`gf180mcu_fd_sc_mcu7t5v0`), sixteen SRAM
  macros with `CLK` pins on the clock net, one clock domain, no PLL.

## Reproduction shape

We don't have a minimal standalone reproducer, but the pattern that appears to trigger it is: any
design where `clock_tree_synthesis` runs `configure_cts_characterization` (default) against a
clock net topology large/complex enough that TritonCTS reprocesses already-populated leaf nets
via `separateMacroRegSinks` — SRAM or other macro `CLK` pins on the clock net seem to increase
the odds by giving `separateMacroRegSinks` more nets to reprocess, but aren't structurally
required by the mechanism above. Happy to help narrow this down further if useful.
