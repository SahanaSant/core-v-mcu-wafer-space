#!/usr/bin/env python3
# Copyright 2026 Yusef Karim
# Solderpad Hardware License, Version 2.1, see LICENSE.md for details.
# SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
"""Strip parameter overrides from black-box instances in a synthesised netlist.

`write_verilog` keeps the `#(.ADDR_WIDTH(32'd11))` on instances of black-boxed
modules, because they really are parameterised. A Liberty cell is not: OpenSTA's Verilog reader takes an instance of a library
cell to be plain, and a parameter list there is a syntax error that stops the
whole link. The widths have already done their job by the time synthesis is
over, so dropping them costs nothing and makes the netlist readable.

Only instances are touched. Read from stdin, write to stdout.
"""

import re
import sys

# Yosys writes an override as:
#
#   module_name #(
#     .PARAM(32'd11),
#     .PARAM(32'd32)
#   ) \instance.name  (
#
# so the block runs from `#(` to the `) ` that opens the port list.
INSTANCE = re.compile(
    r"^(  [A-Za-z_][A-Za-z0-9_]*) #\((?:[^\n]*\n)*?  \) ",
    re.MULTILINE,
)


def main():
    sys.stdout.write(INSTANCE.sub(r"\1 ", sys.stdin.read()))


if __name__ == "__main__":
    main()
