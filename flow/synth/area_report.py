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
# Which cell that is depends on the library: gf180mcu_fd_sc_mcu7t5v0 has
# nand2_1, gf180mcu_as_sc_mcu7t3v3 has no _1 drive of anything and starts at
# nand2_2. So the reference is whichever nand2_* is smallest rather than a
# fixed name, and the report names the one it used. kGE is only comparable
# between libraries that resolve to the same reference cell; across libraries,
# compare the um2.
GE_CELL_PREFIX = "nand2_"
# Ticket 11's planning figure for the routing channels a macro array needs on top
# of the macros themselves: 12% on a 4x4 array of sram1024x8, from 148 nets
# escaping each row's bottom edge at Metal3's 0.56 um pitch. It is an estimate,
# unlike everything else in this report, and ticket 21 replaces it with a
# floorplan.
MACRO_CHANNEL_OVERHEAD = 0.12


def liberty_ge_area(path, scl):
    """Smallest nand2 in the library, as (bare cell name, area), from the liberty."""
    prefix = f"{scl}__{GE_CELL_PREFIX}"
    cell_re = re.compile(r"^\s*cell\s*\(\s*([A-Za-z0-9_\\]+)\s*\)")
    area_re = re.compile(r"^\s*area\s*:\s*([0-9.eE+-]+)\s*;")
    cell = None
    areas = {}
    with open(path) as fh:
        for line in fh:
            m = cell_re.match(line)
            if m:
                cell = m.group(1)
            elif cell and cell.startswith(prefix):
                m = area_re.match(line)
                if m:
                    areas.setdefault(cell, float(m.group(1)))
    if not areas:
        raise SystemExit(f"error: no {prefix}* cell found in {path}")
    name = min(areas, key=areas.get)
    return name[len(f"{scl}__"):], areas[name]


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


def read_cell_histogram(netlist, prefix):
    """Count instances of cells named `<prefix>__*` in a written netlist."""
    if not netlist.exists():
        return Counter()
    pat = re.compile(rf"^\s+({re.escape(prefix)}__[a-z0-9_]+)\s")
    hist = Counter()
    with open(netlist) as fh:
        for line in fh:
            m = pat.match(line)
            if m:
                hist[m.group(1)] += 1
    return hist


def read_lef_sizes(lef_dir):
    """Macro name -> area in um2, from LEF `SIZE`.

    This is deliberately not the liberty. Every gf180mcu_ocd_ip_sram liberty is a
    foundry liberty with the header swapped and the address bus resized, so its
    `area` field describes the macro it was copied from: 209,400 um2 declared for
    the sram1024x8 against a real 155,414, and 3.2x out on the sram64x8. LEF
    geometry is the only measured area these macros have. See ticket 20.
    """
    macro_re = re.compile(r"^\s*MACRO\s+(\S+)")
    size_re = re.compile(r"^\s*SIZE\s+([0-9.]+)\s+BY\s+([0-9.]+)")
    sizes = {}
    for path in sorted(Path(lef_dir).glob("*.lef")):
        name = None
        for line in path.read_text().splitlines():
            m = macro_re.match(line)
            if m:
                name = m.group(1)
                continue
            m = size_re.match(line)
            if m and name:
                sizes[name] = float(m.group(1)) * float(m.group(2))
                name = None
    return sizes


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
    ap.add_argument("--sram", help="macro library name, e.g. gf180mcu_ocd_ip_sram")
    ap.add_argument("--sram-lef-dir", help="that library's lef/ directory")
    args = ap.parse_args()

    logs = Path(args.logs)
    ge_cell, ge = liberty_ge_area(args.liberty, args.scl)
    flat = read_totals(logs / "synth-flat.log", args.top)
    hier = read_totals(logs / "synth-hier.log", args.top)
    modules = read_modules(logs / "synth-hier.log")

    out = []
    w = out.append
    corner = Path(args.liberty).stem.split("__")[-1]

    w(f"# Logic area: `{args.top}` on `{args.scl}`")
    w("")
    w(
        f"Mapped at corner `{corner}` against a {args.clock_period:g} ns target. The boot "
        "ROM and `apb_pll` are black boxes, the SRAM macros are real instances with no "
        "area in this liberty, and there are no pads, no floorplan and no PDN. The cell "
        "areas below are standard cells and nothing else; the macros are counted "
        "separately, from LEF."
    )
    w("")
    w(f"Gate equivalent: `{ge_cell}` = {ge:.3f} um2, read from the liberty.")
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

    macros = Counter()
    lef = {}
    if args.sram and args.sram_lef_dir:
        macros = read_cell_histogram(logs / f"{args.top}.flat.v", args.sram)
        lef = read_lef_sizes(args.sram_lef_dir)

    if flat:
        placed = flat["area"] / TARGET_DENSITY
        macro_area = sum(n * lef.get(m, 0.0) for m, n in macros.items())
        array = macro_area * (1 + MACRO_CHANNEL_OVERHEAD)

        w("## Silicon budget")
        w("")
        w(
            f"A 1x1 slot has {CORE_AREA_UM2 / 1e6:.2f} mm2 of core. Standard cells are "
            f"placed at `PL_TARGET_DENSITY_PCT: {TARGET_DENSITY * 100:.0f}`, which is "
            "the wafer.space template's default and the optimistic end of what Run 1 "
            "achieved. Macro area is LEF geometry, never liberty."
        )
        w("")
        w("| item | mm2 | % of core |")
        w("| --- | ---: | ---: |")
        w(
            f"| standard cells, flattened | {flat['area'] / 1e6:.3f} | "
            f"{100 * flat['area'] / CORE_AREA_UM2:.1f} |"
        )
        w(
            f"| the same, placed at {TARGET_DENSITY * 100:.0f}% | {placed / 1e6:.2f} "
            f"| {100 * placed / CORE_AREA_UM2:.1f} |"
        )
        if macro_area:
            for m, n in sorted(macros.items()):
                a = n * lef.get(m, 0.0)
                w(
                    f"| {n} x `{m.split('__')[-1]}` | {a / 1e6:.3f} "
                    f"| {100 * a / CORE_AREA_UM2:.1f} |"
                )
            w(
                f"| macro array, +{MACRO_CHANNEL_OVERHEAD * 100:.0f}% routing channels "
                f"| {array / 1e6:.2f} | {100 * array / CORE_AREA_UM2:.1f} |"
            )
        w(
            f"| **occupied** | **{(placed + array) / 1e6:.2f}** "
            f"| **{100 * (placed + array) / CORE_AREA_UM2:.1f}** |"
        )
        w(
            f"| free | {(CORE_AREA_UM2 - placed - array) / 1e6:.2f} "
            f"| {100 * (CORE_AREA_UM2 - placed - array) / CORE_AREA_UM2:.1f} |"
        )
        w("")
        if macros and not macro_area:
            w(
                "No LEF was found for the macros above, so the array is missing from "
                "this arithmetic. Check `--sram-lef-dir`."
            )
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
