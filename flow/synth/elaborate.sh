#!/bin/sh
# Copyright 2026 Yusef Karim
# Solderpad Hardware License, Version 2.1, see LICENSE.md for details.
# SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
#
# Elaborate the SoC and report any module it instantiates but does not define.
# The cheap check: seconds, and it answers "does the RTL still read". Invoke it
# as `make elaborate`.

set -eu

. "${ROOT:-/foss/designs}/flow/synth/filelist.sh"

gf180_liberty
gf180_filelist

READ_LIBS=$(for l in $LIBS; do echo "    read_liberty -lib $l"; done)

echo "==> elaborating $TOP with yosys-slang"
yosys -l "$BUILD/elaborate.log" -p "
$READ_LIBS
    plugin -i slang
    read_slang -F gf180.f -D SYNTHESIS --top $TOP --keep-hierarchy --error-limit=0
    hierarchy -check -top $TOP
    stat -top $TOP
" >/dev/null

# The per-instance hierarchy runs to thousands of lines under --keep-hierarchy.
# Print only the roll-up, which ends with one line per unresolved module.
echo
echo "==> $TOP, counting submodules"
awk '/\+----------Count including submodules/ {buf = ""}
     /^End of script/ {exit}
     {buf = buf $0 ORS}
     END {printf "%s", buf}' "$BUILD/elaborate.log"
echo "full log: flow/build/elaborate.log"
