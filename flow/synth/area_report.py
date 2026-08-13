#!/usr/bin/env python3
# Copyright 2026 Yusef Karim
# Solderpad Hardware License, Version 2.1, see LICENSE.md for details.
# SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
"""Turn the logs `area.sh` leaves behind into the area report.

Both inputs are the yosys `stat -liberty` output, which is enough on its own.
The flattened log gives the honest total, since nothing optimises across a
module boundary that has been removed. The hierarchical log gives the
breakdown: `--keep-hierarchy` uniquifies every module, so its name carries the
full instance path and area attributes to a subtree by prefix match, with no
instance-count arithmetic and no 100 MB netlist to walk.

Cell areas come from the liberty file, so the gate equivalent moves with the
PDK instead of drifting from it.
"""

import argparse
import re
from collections import Counter
from pathlib import Path

# A 1x1 slot's core area, from docs/porting-analysis.md.
CORE_AREA_UM2 = 12.92e6
# The wafer.space template default that the placed-area arithmetic hangs off.
TARGET_DENSITY = 0.35
# Gate equivalents are quoted against the smallest 2-input NAND in the library.
GE_CELL = "nand2_1"
# mm2 per KiB for the two macros ticket 11 is choosing between.
SRAM_DENSITY = (
    ("gf180mcu_fd_ip_sram, foundry", 0.409),
    ("gf180mcu_ocd_ip_sram, ticket 07", 0.155),
)


def liberty_ge_area(path, scl):
    """Area of the gate-equivalent reference cell, straight from the liberty."""
    want = f"{scl}__{GE_CELL}"
    cell_re = re.compile(r"^\s*cell\s*\(\s*([A-Za-z0-9_\\]+)\s*\)")
    area_re = re.compile(r"^\s*area\s*:\s*([0-9.eE+-]+)\s*;")
    cell = None
    with open(path) as fh:
        for line in fh:
            m = cell_re.match(line)
            if m:
                cell = m.group(1)
            elif cell == want:
                m = area_re.match(line)
                if m:
                    return float(m.group(1))
    raise SystemExit(f"error: {want} not found in {path}")


def read_totals(log, top_module):
    """Total cells, cell area and the sequential share, from a stat log.

    A flattened run has one module, so `stat` prints a local count and a
    `Chip area for module` line. A hierarchical run prints those per module and
    then a `design hierarchy` roll-up, which is the only place the design-wide
    cell count appears: counting instances in the netlist would miss every
    module instantiated more than once.
    """
    if not log.exists():
        return None
    text = log.read_text()
    area = re.findall(r"Chip area for top module '[^']*':\s*([0-9.]+)", text) or re.findall(
        rf"Chip area for module '\\?{re.escape(top_module)}':\s*([0-9.]+)", text
    )
    if not area:
        return None

    # `synth` runs its own `stat` before technology mapping, so the log holds
    # two roll-ups. Take the last, which is the mapped one; the earlier count is
    # generic cells and is roughly 17% higher. With `-liberty` the roll-up
    # carries an area column between the count and the module name.
    rollup = text.rfind("=== design hierarchy ===")
    if rollup != -1:
        cells = re.search(
            rf"^\s*(\d+)\s+(?:\S+\s+)?{re.escape(top_module)}$", text[rollup:], re.M
        )
    else:
        cells = re.search(r"^\s+(\d+)\s+\S+\s+cells\s*$", text, re.M)

    seq = re.findall(r"used for sequential elements:\s*([0-9.]+)", text)
    return {
        "area": float(area[-1]),
        "cells": int(cells.group(1)) if cells else None,
        "sequential": float(seq[-1]) if seq else None,
    }


def read_modules(log):
    """Every module's own area, keyed by instance path.

    `--keep-hierarchy` names each module `<type>$<instance path>`, uniquified,
    so each path appears exactly once and the areas sum to the design total.
    """
    if not log.exists():
        return []
    line_re = re.compile(r"Chip area for module '\\([^']+)':\s*([0-9.]+)")
    out = []
    with open(log) as fh:
        for line in fh:
            m = line_re.search(line)
            if m:
                name = m.group(1)
                path = name.split("$", 1)[1] if "$" in name else name
                out.append((path, float(m.group(2))))
    return out


def read_cell_histogram(netlist, scl):
    """Count standard-cell instances in a written netlist."""
    if not netlist.exists():
        return Counter()
    pat = re.compile(rf"^\s+({re.escape(scl)}__[a-z0-9_]+)\s")
    hist = Counter()
    with open(netlist) as fh:
        for line in fh:
            m = pat.match(line)
            if m:
                hist[m.group(1)] += 1
    return hist


class Tree:
    """Subtree areas, by instance-path prefix."""

    def __init__(self, modules):
        self.modules = modules
        self.total = sum(a for _, a in modules)

    def area(self, path):
        return sum(a for n, a in self.modules if n == path or n.startswith(path + "."))

    def children(self, path):
        """Immediate children of a path, as {child instance name: subtree area}."""
        kids = Counter()
        prefix = path + "."
        for name, a in self.modules:
            if name.startswith(prefix):
                kids[name[len(prefix) :].split(".")[0]] += a
            elif name == path:
                kids["(own logic)"] += a
        return kids


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--liberty", required=True)
    ap.add_argument("--scl", required=True)
    ap.add_argument("--clock-period", type=float, required=True)
    ap.add_argument("--logs", required=True, help="directory area.sh wrote to")
    ap.add_argument("--top", default="core_v_mcu")
    args = ap.parse_args()

    logs = Path(args.logs)
    ge = liberty_ge_area(args.liberty, args.scl)
    flat = read_totals(logs / "synth-flat.log", args.top)
    hier = read_totals(logs / "synth-hier.log", args.top)
    modules = read_modules(logs / "synth-hier.log")

    out = []
    w = out.append
    corner = Path(args.liberty).stem.split("__")[-1]

    w(f"# Logic area: `{args.top}` on `{args.scl}`")
    w("")
    w(
        f"Mapped at corner `{corner}` against a {args.clock_period:g} ns target. The "
        "memories, the clock cells, the boot ROM and `apb_pll` are black boxes, and "
        "there are no pads, no floorplan and no PDN. This is the logic and nothing else."
    )
    w("")
    w(f"Gate equivalent: `{GE_CELL}` = {ge:.3f} um2, read from the liberty.")
    w("")

    w("## Headline")
    w("")
    w("| pass | cells | cell area (um2) | mm2 | kGE | sequential |")
    w("| --- | ---: | ---: | ---: | ---: | ---: |")
    for label, stat in (("flattened", flat), ("hierarchical", hier)):
        if not stat:
            continue
        seq = (
            f"{100 * stat['sequential'] / stat['area']:.1f}%"
            if stat["sequential"]
            else "-"
        )
        cells = f"{stat['cells']:,}" if stat["cells"] else "-"
        w(
            f"| {label} | {cells} | {stat['area']:,.0f} | {stat['area'] / 1e6:.3f} "
            f"| {stat['area'] / ge / 1000:.1f} | {seq} |"
        )
    w("")

    if flat:
        placed = flat["area"] / TARGET_DENSITY
        left = CORE_AREA_UM2 - placed
        w(
            f"Placed at `PL_TARGET_DENSITY_PCT: {TARGET_DENSITY * 100:.0f}` the "
            f"flattened logic occupies **{placed / 1e6:.2f} mm2** of the 12.92 mm2 "
            f"core, leaving **{left / 1e6:.2f} mm2**."
        )
        w("")
        w("| macro | mm2 per KiB | KiB in the remainder |")
        w("| --- | ---: | ---: |")
        for macro, per_kib in SRAM_DENSITY:
            w(f"| {macro} | {per_kib:.3f} | {left / 1e6 / per_kib:.1f} |")
        w("")

    if modules:
        t = Tree(modules)
        w("## Where the area is")
        w("")
        w(
            "From the hierarchical pass, so these sum to its larger total. Read them "
            "as proportions. The gap against the flattened total is what cross-"
            "boundary optimisation removes, and it is not spread evenly."
        )
        w("")

        S = f"{args.top}.i_soc_domain"
        P = f"{S}.soc_peripherals_i"
        rows = [
            ("core_v_mcu", args.top, 0),
            ("safe_domain", f"{args.top}.i_safe_domain", 1),
            ("pad_control", f"{args.top}.i_safe_domain.i_pad_control", 2),
            ("soc_domain", S, 1),
            ("fc_subsystem", f"{S}.fc_subsystem_i", 2),
            ("cv32e40p_core", f"{S}.fc_subsystem_i.lFC_CORE", 3),
            ("soc_interconnect_wrap", f"{S}.i_soc_interconnect_wrap", 2),
            ("debug module", f"{S}.i_dm_top", 2),
            ("dmi_jtag", f"{S}.i_dmi_jtag", 2),
            ("l2_ram_multi_bank", f"{S}.l2_ram_i", 2),
            ("soc_peripherals", P, 2),
            ("udma_subsystem", f"{P}.i_udma", 3),
            ("soc_event_generator", f"{P}.u_evnt_gen", 3),
            ("apb_adv_timer", f"{P}.i_apb_adv_timer", 3),
            ("apb_i2cs", f"{P}.i_apb_i2cs", 3),
            ("apb_soc_ctrl", f"{P}.i_apb_soc_ctrl", 3),
            ("apb_gpiov2", f"{P}.i_apb_gpio", 3),
            ("apb_timer_unit", f"{P}.i_apb_timer_unit", 3),
            ("periph_bus_wrap", f"{P}.periph_bus_i", 3),
            ("efpga_subsystem (stub)", f"{P}.i_efpga_subsystem", 3),
        ]
        w("| block | area (um2) | % of design |")
        w("| --- | ---: | ---: |")
        for label, path, depth in rows:
            a = t.area(path)
            pad = "&nbsp;" * 4 * depth
            w(f"| {pad}{label} | {a:,.0f} | {100 * a / t.total:.1f} |")
        w("")

        for title, path in (
            ("uDMA, per peripheral", f"{P}.i_udma"),
            ("apb_i2cs", f"{P}.i_apb_i2cs"),
            ("soc_interconnect_wrap", f"{S}.i_soc_interconnect_wrap"),
        ):
            sub = t.area(path)
            if sub <= 0:
                continue
            w(f"### {title}, {sub:,.0f} um2")
            w("")
            w("| instance | area (um2) | % of block |")
            w("| --- | ---: | ---: |")
            for name, a in t.children(path).most_common():
                w(f"| {name} | {a:,.0f} | {100 * a / sub:.1f} |")
            w("")

    hist = read_cell_histogram(logs / f"{args.top}.flat.v", args.scl)
    if hist:
        w("## Most-used cells, flattened netlist")
        w("")
        w("| cell | instances |")
        w("| --- | ---: |")
        for cell, n in hist.most_common(15):
            w(f"| {cell.split('__')[-1]} | {n:,} |")
        w("")

    print("\n".join(out))


if __name__ == "__main__":
    main()
