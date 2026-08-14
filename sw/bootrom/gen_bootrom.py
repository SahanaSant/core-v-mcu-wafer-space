#!/usr/bin/env python3
# Copyright 2026 Yusef Karim
# Solderpad Hardware License, Version 2.1, see LICENSE.md for details.
# SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
#
# Converts sw/bootrom's compiled binary into rtl/gf180mcu/gf180_bootrom.sv: a
# case statement over the image, in the same spirit as
# core-v-mcu/a2_boot/srec2verilog.py (which did the same conversion from an
# .srec, for upstream's original a2_bootrom.sv) and matching pad_control.sv's
# "generated file" convention (util/ioscript.py). $readmemh does not
# synthesise, which is why this exists at all.
#
# Also optionally writes a plain hex-words "golden" file for the testbench in
# sw/bootrom/tb/ to self-check the generated Verilog against -- not RTL, not
# synthesised, purely a verification artifact -- the same dual-output shape
# srec2verilog.py already had (it wrote both the .sv and a .mem alongside it).

import argparse
import datetime
import struct
import sys

ADDR_WIDTH = 11
DATA_WIDTH = 32
MAX_WORDS = 1 << ADDR_WIDTH  # boot_rom.sv's decode window: 2048 words, 8 KiB

HEADER = """\
// Copyright 2026 Yusef Karim
// Solderpad Hardware License, Version 2.1, see LICENSE.md for details.
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1

// GF180MCU boot ROM for the CORE-V MCU.
//
// GENERATED FILE. Do not hand-edit: this is sw/bootrom/gen_bootrom.py's
// output from sw/bootrom/bootrom.bin (built by sw/bootrom/Makefile), the same
// way pad_control.sv is generated from util/ioscript.py. Regenerate with
// `make bootrom` after any change under sw/bootrom/.
//
// Replaces upstream's a2_bootrom.sv, which initialises itself with
// $readmemh("mem_init/boot.mem") over an 11-bit x 32-bit array -- that does
// not synthesise. This module keeps a2_bootrom's name, port list and
// registered read timing exactly (CEN low latches a new word into both
// read_data and Q; CEN high holds Q at the last latched value), because
// boot_rom.sv instantiates it unmodified, and replaces the $readmemh array
// with a case statement over the compiled image: the same technique
// upstream's own a2_boot/srec2verilog.py already used to turn an .srec into
// Verilog for the original a2_bootrom.sv.
//
// Built: {date}, {nwords} words, {nbytes} bytes (ticket 04 estimated 2 KiB).

module a2_bootrom #(
    parameter int unsigned ADDR_WIDTH = {addr_width},
    parameter int unsigned DATA_WIDTH = {data_width}
) (
    input  logic                  CLK,
    input  logic                  CEN,
    input  logic [ADDR_WIDTH-1:0] A,
    output logic [DATA_WIDTH-1:0] Q
);

  // boot_rom.sv instantiates this with ADDR_WIDTH = ROM_ADDR_WIDTH-2 = {addr_width}
  // (an 8 KiB byte window from SOC_MEM_MAP_BOOT_ROM_START_ADDR) and
  // DATA_WIDTH = {data_width}; the case statement below was generated for exactly
  // that shape.
  if (ADDR_WIDTH != {addr_width} || DATA_WIDTH != {data_width})
    $error("gf180_bootrom: generated for ADDR_WIDTH=%0d/DATA_WIDTH=%0d, got %0d/%0d",
           {addr_width}, {data_width}, ADDR_WIDTH, DATA_WIDTH);

  logic [DATA_WIDTH-1:0] rom_word;
  logic [DATA_WIDTH-1:0] read_data;

  always_comb begin
    case (A)
"""

FOOTER = """\
      default: rom_word = {{DATA_WIDTH{{1'b0}}}};
    endcase
  end

  // Matches a2_bootrom.sv's original registered behaviour exactly: on
  // CEN low, latch the addressed word into both read_data and Q (one-cycle
  // read latency); on CEN high, Q holds at the value read_data last latched.
  always_ff @(posedge CLK) begin
    if (CEN == 1'b0) begin
      read_data <= rom_word;
      Q         <= rom_word;
    end else begin
      Q <= read_data;
    end
  end

endmodule
"""


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--input", required=True, help="compiled flat binary (objcopy -O binary)")
    ap.add_argument("--output", required=True, help="rtl/gf180mcu/gf180_bootrom.sv to write")
    ap.add_argument("--golden", help="optional plain hex-words file for the testbench")
    ap.add_argument(
        "--golden-words-vh",
        help="optional Verilog header (`define BOOTROM_GOLDEN_WORDS N) recording the word "
        "count for --golden, so the testbench doesn't hardcode a count that goes stale "
        "every time the image changes",
    )
    args = ap.parse_args()

    with open(args.input, "rb") as f:
        data = f.read()

    if len(data) % 4 != 0:
        pad = 4 - (len(data) % 4)
        data += b"\x00" * pad

    nwords = len(data) // 4
    if nwords > MAX_WORDS:
        sys.exit(
            f"error: bootrom.bin is {len(data)} bytes ({nwords} words), "
            f"which overruns boot_rom.sv's {MAX_WORDS}-word decode window"
        )

    words = struct.unpack(f"<{nwords}I", data)

    with open(args.output, "w") as sv:
        sv.write(
            HEADER.format(
                date=datetime.date.today().isoformat(),
                nwords=nwords,
                nbytes=len(data),
                addr_width=ADDR_WIDTH,
                data_width=DATA_WIDTH,
            )
        )
        for i, w in enumerate(words):
            sv.write(f"      {i}: rom_word = 32'h{w:08x};\n")
        sv.write(FOOTER)

    print(f"wrote {args.output}: {nwords} words, {len(data)} bytes")

    if args.golden:
        with open(args.golden, "w") as g:
            for w in words:
                g.write(f"{w:08x}\n")
        print(f"wrote {args.golden}: {nwords} words (testbench self-check only, not RTL)")

    if args.golden_words_vh:
        with open(args.golden_words_vh, "w") as vh:
            vh.write(f"// generated by gen_bootrom.py, testbench self-check only, not RTL\n")
            vh.write(f"`define BOOTROM_GOLDEN_WORDS {nwords}\n")
        print(f"wrote {args.golden_words_vh}")


if __name__ == "__main__":
    main()
