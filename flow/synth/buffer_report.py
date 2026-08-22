#!/usr/bin/env python3
# Copyright 2026 Yusef Karim
# Solderpad Hardware License, Version 2.1, see LICENSE.md for details.
# SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
#
# Ticket 32: attribute the buffers a resizer step inserted back to the nets
# they were inserted for, so "the design needs 64,734 emergency buffers" turns
# into a named list of which signals cost what.
#
# Give it two netlists from the same run, the one going into the step and the
# one coming out, plus the standard-cell LEF:
#
#   python3 flow/synth/buffer_report.py \
#       flow/runs/<RUN>/02-yosys-synthesis/chip_top.nl.v \
#       flow/runs/<RUN>/27-openroad-repairdesignpostgpl/chip_top.nl.v \
#       pdk/gf180mcuD/libs.ref/gf180mcu_fd_sc_mcu7t5v0/lef/gf180mcu_fd_sc_mcu7t5v0.lef
#
# It diffs the instance sets, then walks each new instance backwards through
# other new instances until it reaches a net that existed before the step, and
# charges the instance to that net. Pin directions come from the LEF rather
# than from cell-name conventions, so an output pin is an output pin because
# the LEF says so.
#
# Instances the walk cannot attribute are the connectionless physical cells
# (filltie, endcap, IO fill) that tap insertion and PDN add; the attributed
# count should match the step's own "[INFO RSZ-0038] Inserted N buffers".

import re
import sys
from collections import Counter, defaultdict

# Yosys writes one connection per line; OpenROAD writes the first connection on
# the instance line. Match whole instances instead, non-greedily up to the ");"
# that ends one: a connection's own ")" is always followed by "," or another
# ")", never by ";".
INST_RE = re.compile(r"^[ \t]*(gf180mcu\S+)\s+(\S+)\s*\((.*?)\)\s*;", re.M | re.S)
CONN_RE = re.compile(r"\.(\w+)\(\s*(.*?)\s*\)")


def lef_pin_dirs(path):
    """cell -> {pin: direction}, from the standard-cell LEF."""
    dirs = {}
    cell = pin = None
    for line in open(path):
        s = line.strip()
        if s.startswith("MACRO "):
            cell = s.split()[1]
            dirs[cell] = {}
        elif s.startswith("PIN "):
            pin = s.split()[1]
        elif s.startswith("DIRECTION ") and cell and pin:
            dirs[cell][pin] = s.split()[1]
        elif s.startswith("END ") and cell and s.split()[1] == cell:
            cell = pin = None
    return dirs


def parse_netlist(path):
    """-> (instances, conns) where conns[net] = [(inst, cell, pin), ...]."""
    instances = {}
    conns = defaultdict(list)
    for m in INST_RE.finditer(open(path).read()):
        cell, inst, body = m.group(1), m.group(2), m.group(3)
        instances[inst] = cell
        for pin, net in CONN_RE.findall(body):
            conns[net].append((inst, cell, pin))
    return instances, conns


def strip_escape(net):
    """Verilog escaped identifiers are \\name followed by a space."""
    return net[1:].rstrip() if net.startswith("\\") else net


def main(before_nl, after_nl, lef):
    dirs = lef_pin_dirs(lef)

    def split(conns):
        """net -> (drivers, loads). Macros absent from the LEF read as loads,
        which leaves their nets looking undriven rather than mis-driven."""
        out = {}
        for net, cs in conns.items():
            drv, ld = [], []
            for c in cs:
                (drv if dirs.get(c[1], {}).get(c[2]) == "OUTPUT" else ld).append(c)
            out[net] = (drv, ld)
        return out

    before_i, before_c = parse_netlist(before_nl)
    after_i, after_c = parse_netlist(after_nl)
    before, after = split(before_c), split(after_c)
    new = {i: c for i, c in after_i.items() if i not in before_i}

    print(f"instances: before {len(before_i)}, after {len(after_i)}, new {len(new)}")
    print(f"nets:      before {len(before)}, after {len(after)}")
    print()

    print("=== top 20 nets by fanout, before the step ===")
    for net, (drv, ld) in sorted(before.items(), key=lambda kv: -len(kv[1][1]))[:20]:
        cell = drv[0][1].split("__")[-1] if drv else "(port/macro)"
        print(f"{len(ld):7d}  {cell:16s}  {strip_escape(net)[:130]}")
    print()

    print("=== new instances by name prefix and cell ===")
    by_kind = Counter()
    for inst, cell in new.items():
        by_kind[("".join(c for c in inst if not c.isdigit()), cell.split("__")[-1])] += 1
    for (prefix, cell), n in by_kind.most_common(15):
        print(f"{n:7d}  {prefix:24s} {cell}")
    print()

    driver_of = {net: d[0][0] for net, (d, _) in after.items() if d}
    inputs_of = defaultdict(list)
    for net, (_, ld) in after.items():
        for inst, _cell, _pin in ld:
            inputs_of[inst].append(net)

    memo = {}

    def root_for(inst, depth=0):
        if inst in memo:
            return memo[inst]
        memo[inst] = None  # breaks any cycle without a depth guard
        best = None
        for net in inputs_of.get(inst, []):
            if net in before:
                best = net
                break
            up = driver_of.get(net)
            if up in new:
                best = root_for(up, depth + 1)
                if best is not None:
                    break
        memo[inst] = best
        return best

    sys.setrecursionlimit(100000)
    charge, unattributed = Counter(), 0
    for inst in new:
        r = root_for(inst)
        if r is None:
            unattributed += 1
        else:
            charge[r] += 1
    print(f"attributed {sum(charge.values())} instances, "
          f"{unattributed} unattributed (expect these to be fill/tap/endcap)")
    print()

    print("=== top 30 root nets by instances charged to them ===")
    for net, n in charge.most_common(30):
        drv, ld = before.get(net, ([], []))
        cell = drv[0][1].split("__")[-1] if drv else "(port/macro)"
        print(f"{n:7d}  fanout {len(ld):6d}  {cell:16s}  {strip_escape(net)[:120]}")
    print()

    def module_of(net):
        s = strip_escape(net)
        return ".".join(s.split(".")[:5]) if "." in s else "(synthesis-generated)"

    by_mod = Counter()
    for net, n in charge.items():
        by_mod[module_of(net)] += n
    total = sum(by_mod.values()) or 1
    print("=== charged instances by RTL module path, five levels deep ===")
    for mod, n in by_mod.most_common(20):
        print(f"{n:7d}  {100.0 * n / total:5.1f}%  {mod}")


if __name__ == "__main__":
    if len(sys.argv) != 4:
        sys.exit(__doc__ or "usage: buffer_report.py <before.nl.v> <after.nl.v> <scl.lef>")
    main(*sys.argv[1:])
