#!/usr/bin/env python3
# Copyright 2026 Yusef Karim
# Solderpad Hardware License, Version 2.1, see LICENSE.md for details.
# SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
"""Summarise a pre-layout critical path as logic depth, not as a frequency.

The raw slack on a synthesised netlist is meaningless: nothing has been placed,
so every net has zero parasitics, and nothing has been buffered, so a net with
four thousand loads is driven by whatever minimum-drive cell synthesis first
picked. Those two errors do not cancel, and the second is enormous. On this
design the worst stage alone reports over 800 ns.

What does survive is the shape of the path. Count its stages, and take the
delay of the stages whose fanout is small enough that the liberty is not
extrapolating, which after buffering is what every stage will look like. Their
median times the stage count is a floor on the achievable period: real routing
and a real clock tree only add to it.
"""

import argparse
import re
import statistics
import sys

# A path line: "   0.568    9.236 v _099636_/ZN (gf180mcu_fd_sc_mcu7t5v0__nor3_1)"
STAGE = re.compile(r"^\s+(-?[0-9.]+)\s+-?[0-9.]+\s+[\^v]\s+\S+/\S+ \(gf180")
# Above this, the stage is a high-fanout net the flow has not buffered yet.
TYPICAL_MAX_NS = 2.0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("log", help="OpenSTA report_checks output")
    ap.add_argument("--corner", required=True)
    ap.add_argument("--clock-period", type=float, required=True)
    args = ap.parse_args()

    with open(args.log) as fh:
        stages = [float(m.group(1)) for line in fh if (m := STAGE.match(line))]
    # The first entry is the launching flop's clock-to-Q, not a logic stage.
    stages = stages[1:]
    typical = [d for d in stages if d < TYPICAL_MAX_NS]

    if not typical:
        print(f"{args.corner}: no usable path found in {args.log}", file=sys.stderr)
        return 1

    median = statistics.median(typical)
    depth_ns = len(stages) * median
    print(
        f"{args.corner}: {len(stages)} logic stages, median stage {median:.3f} ns "
        f"({len(typical)} of {len(stages)} stages under {TYPICAL_MAX_NS:g} ns), "
        f"floor {depth_ns:.1f} ns = {1000 / depth_ns:.1f} MHz, "
        f"{100 * depth_ns / args.clock_period:.0f}% of the "
        f"{args.clock_period:g} ns budget"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
