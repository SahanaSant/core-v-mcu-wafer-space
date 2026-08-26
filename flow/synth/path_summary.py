#!/usr/bin/env python3
# Copyright 2026 Yusef Karim
# Solderpad Hardware License, Version 2.1, see LICENSE.md for details.
# SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
"""Summarise the deepest pre-layout logic path, picked by depth, not by slack.

`report_checks -group_path_count 1` ranks by slack, which pre-layout means by
raw arrival time. Every net has zero parasitics and nothing has been buffered,
so arrival is dominated by whichever minimum-drive cell happens to drive a
large net, not by how many gates the path passes through. Depth barely enters
the ranking, and the winner can flip identity by 2.4x under an RTL change that
touches neither block.

So `sta.sh` asks OpenSTA for the N worst-slack candidates in one shot
(`-group_path_count`, `-unique_paths_to_endpoint`, `-format json`) and this
script reports whichever has the most logic stages. That is cheap, because
OpenSTA enumerates paths internally rather than this script re-querying per
endpoint, and far more stable, because the paths this design's unbuffered
fanout puts at the top of the slack ranking differ by single-digit
nanoseconds, so the true deepest path is almost always inside the window even
when it does not rank first. N=50, 300 and 1000 all converge on the same path.
If the winner sits near the end of the requested window that margin may not
hold, and this script says so.

Stage count is exact rather than inferred from text formatting: it is the
number of distinct cell instances in OpenSTA's JSON path between the launching
and capturing registers, minus those two.

The delay floor is an approximation. Nothing has been placed or buffered, so a
stage's delay is real only when its net's fanout is small enough that Liberty
is not extrapolating. Stages under 2 ns are "typical"; take their median and
multiply by the stage count for a floor. Real routing and a real clock tree
only add to it.
"""
import argparse
import json
import statistics
import sys

TYPICAL_MAX_NS = 2.0


def stage_instances(source_path):
    """Distinct cell instances along the path, launch and capture included,
    collapsed from OpenSTA's one-entry-per-pin listing (each cell appears as
    an input-pin arrival and an output-pin arrival)."""
    instances = []
    for point in source_path:
        inst = point.get("instance")
        if not instances or instances[-1] != inst:
            instances.append(inst)
    return instances


def stage_delays_ns(source_path):
    """Each cell's own delay: the arrival delta between its input-pin and
    output-pin entries. Net delay is zero by construction pre-layout, so
    entries belonging to different instances contribute nothing here."""
    delays = []
    for a, b in zip(source_path, source_path[1:]):
        if a.get("instance") == b.get("instance"):
            delays.append((b["arrival"] - a["arrival"]) * 1e9)
    return delays


def load_checks(path):
    with open(path) as fh:
        text = fh.read()
    start = text.find('{"checks"')
    if start < 0:
        return None
    return json.loads(text[start:])["checks"]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("log", help="OpenSTA report_checks -format json output")
    ap.add_argument("--corner", required=True)
    ap.add_argument("--clock-period", type=float, required=True)
    args = ap.parse_args()

    checks = load_checks(args.log)
    if not checks:
        print(f"{args.corner}: no usable path found in {args.log}", file=sys.stderr)
        return 1

    # OpenSTA already returns these worst-slack first; re-sort defensively,
    # since the reported rank is the only thing here that depends on order.
    by_slack = sorted(checks, key=lambda p: p["slack"])
    scored = [(len(stage_instances(p["source_path"])) - 2, p) for p in by_slack]
    depth, winner = max(scored, key=lambda t: t[0])
    rank = by_slack.index(winner) + 1
    n = len(checks)

    delays = stage_delays_ns(winner["source_path"])
    typical = [d for d in delays if 0 <= d < TYPICAL_MAX_NS]
    if not typical:
        print(f"{args.corner}: no usable stage delays on the deepest candidate", file=sys.stderr)
        return 1

    median = statistics.median(typical)
    depth_ns = depth * median
    rank_note = "ranked #1 by slack" if rank == 1 else f"ranked #{rank} of {n} by slack"
    margin_note = ""
    if rank > 0.9 * n:
        margin_note = (
            f" (near the edge of the {n}-candidate window; rerun with a higher "
            "-group_path_count if this changes)"
        )
    print(
        f"{args.corner}: {depth} logic stages ({winner['endpoint']}, {rank_note}{margin_note}), "
        f"median stage {median:.3f} ns ({len(typical)} of {len(delays)} stages under "
        f"{TYPICAL_MAX_NS:g} ns), "
        f"floor {depth_ns:.1f} ns = {1000 / depth_ns:.1f} MHz, "
        f"{100 * depth_ns / args.clock_period:.0f}% of the "
        f"{args.clock_period:g} ns budget"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
