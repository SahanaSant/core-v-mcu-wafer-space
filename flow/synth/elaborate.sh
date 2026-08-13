#!/bin/sh
# Copyright 2026 Yusef Karim
# Solderpad Hardware License, Version 2.1, see LICENSE.md for details.
# SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
#
# Elaborate the CORE-V MCU SoC for the GF180MCU target and report what is
# missing. Runs inside the toolchain container; invoke it as `make elaborate`.
#
# This is the cheap check: it stops at elaboration, so it answers "does the RTL
# still read, and what modules are still unwritten" in seconds. `area.sh` takes
# the same file list all the way through technology mapping.

set -eu

. "${ROOT:-/foss/designs}/flow/synth/filelist.sh"

gf180_filelist

echo "==> elaborating $TOP with yosys-slang"
yosys -l "$BUILD/elaborate.log" -p "
    plugin -i slang
    read_slang -F gf180.f -D SYNTHESIS --top $TOP --keep-hierarchy --error-limit=0
    hierarchy -check -top $TOP
    stat -top $TOP
" >/dev/null

# The per-instance hierarchy runs to thousands of lines with --keep-hierarchy;
# print only the roll-up, which ends with one line per unresolved module.
echo
echo "==> $TOP, counting submodules"
awk '/\+----------Count including submodules/ {buf = ""}
     /^End of script/ {exit}
     {buf = buf $0 ORS}
     END {printf "%s", buf}' "$BUILD/elaborate.log"
echo "full log: flow/build/elaborate.log"
