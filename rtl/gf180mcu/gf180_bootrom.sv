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
// Built: 2026-08-22, 208 words, 832 bytes (ticket 04 estimated 2 KiB).

module a2_bootrom #(
    parameter int unsigned ADDR_WIDTH = 11,
    parameter int unsigned DATA_WIDTH = 32
) (
    input  logic                  CLK,
    input  logic                  CEN,
    input  logic [ADDR_WIDTH-1:0] A,
    output logic [DATA_WIDTH-1:0] Q
);

  // boot_rom.sv instantiates this with ADDR_WIDTH = ROM_ADDR_WIDTH-2 = 11
  // (an 8 KiB byte window from SOC_MEM_MAP_BOOT_ROM_START_ADDR) and
  // DATA_WIDTH = 32; the case statement below was generated for exactly
  // that shape.
  if (ADDR_WIDTH != 11 || DATA_WIDTH != 32)
    $error("gf180_bootrom: generated for ADDR_WIDTH=%0d/DATA_WIDTH=%0d, got %0d/%0d",
           11, 32, ADDR_WIDTH, DATA_WIDTH);

  logic [DATA_WIDTH-1:0] rom_word;
  logic [DATA_WIDTH-1:0] read_data;

  always_comb begin
    case (A)
      0: rom_word = 32'h0a80006f;
      1: rom_word = 32'h0a40006f;
      2: rom_word = 32'h0a00006f;
      3: rom_word = 32'h09c0006f;
      4: rom_word = 32'h0980006f;
      5: rom_word = 32'h0940006f;
      6: rom_word = 32'h0900006f;
      7: rom_word = 32'h08c0006f;
      8: rom_word = 32'h0880006f;
      9: rom_word = 32'h0840006f;
      10: rom_word = 32'h0800006f;
      11: rom_word = 32'h07c0006f;
      12: rom_word = 32'h0780006f;
      13: rom_word = 32'h0740006f;
      14: rom_word = 32'h0700006f;
      15: rom_word = 32'h06c0006f;
      16: rom_word = 32'h0680006f;
      17: rom_word = 32'h0640006f;
      18: rom_word = 32'h0600006f;
      19: rom_word = 32'h05c0006f;
      20: rom_word = 32'h0580006f;
      21: rom_word = 32'h0540006f;
      22: rom_word = 32'h0500006f;
      23: rom_word = 32'h04c0006f;
      24: rom_word = 32'h0480006f;
      25: rom_word = 32'h0440006f;
      26: rom_word = 32'h0400006f;
      27: rom_word = 32'h03c0006f;
      28: rom_word = 32'h0380006f;
      29: rom_word = 32'h0340006f;
      30: rom_word = 32'h0300006f;
      31: rom_word = 32'h02c0006f;
      32: rom_word = 32'h02004297;
      33: rom_word = 32'hd8028293;
      34: rom_word = 32'h02004317;
      35: rom_word = 32'hdbc30313;
      36: rom_word = 32'h0002a023;
      37: rom_word = 32'h00428293;
      38: rom_word = 32'hfe62ece3;
      39: rom_word = 32'h02004117;
      40: rom_word = 32'hf6410113;
      41: rom_word = 32'h0080006f;
      42: rom_word = 32'h30200073;
      43: rom_word = 32'h002625b7;
      44: rom_word = 32'h85931141;
      45: rom_word = 32'h45015a05;
      46: rom_word = 32'hc422c606;
      47: rom_word = 32'hc04ac226;
      48: rom_word = 32'h458128c1;
      49: rom_word = 32'h22294501;
      50: rom_word = 32'h45014581;
      51: rom_word = 32'h043722ad;
      52: rom_word = 32'h46211c00;
      53: rom_word = 32'h1c0005b7;
      54: rom_word = 32'h22c94501;
      55: rom_word = 32'h67914004;
      56: rom_word = 32'h00442903;
      57: rom_word = 32'hfff48713;
      58: rom_word = 32'hdff78793;
      59: rom_word = 32'h00e7f363;
      60: rom_word = 32'h67c1a001;
      61: rom_word = 32'h861317f1;
      62: rom_word = 32'h85a20034;
      63: rom_word = 32'h8e7d4521;
      64: rom_word = 32'h85a62a71;
      65: rom_word = 32'h20318522;
      66: rom_word = 32'h01250363;
      67: rom_word = 32'h9402a001;
      68: rom_word = 32'h57fda001;
      69: rom_word = 32'h04c12837;
      70: rom_word = 32'h43054681;
      71: rom_word = 32'h08138e3e;
      72: rom_word = 32'hc563db78;
      73: rom_word = 32'h470102b6;
      74: rom_word = 32'h06374501;
      75: rom_word = 32'h06938000;
      76: rom_word = 32'hf5930200;
      77: rom_word = 32'hc5810017;
      78: rom_word = 32'h00e655b3;
      79: rom_word = 32'h07058d4d;
      80: rom_word = 32'h18e38385;
      81: rom_word = 32'h4513fed7;
      82: rom_word = 32'h8082fff5;
      83: rom_word = 32'h00d50733;
      84: rom_word = 32'h00074883;
      85: rom_word = 32'h4701461d;
      86: rom_word = 32'h0018fe93;
      87: rom_word = 32'h000e8663;
      88: rom_word = 32'h00c31eb3;
      89: rom_word = 32'h01d76733;
      90: rom_word = 32'hd893167d;
      91: rom_word = 32'h15e30018;
      92: rom_word = 32'h0762ffc6;
      93: rom_word = 32'h47218fb9;
      94: rom_word = 32'h0786863e;
      95: rom_word = 32'h00065463;
      96: rom_word = 32'h0107c7b3;
      97: rom_word = 32'h7713177d;
      98: rom_word = 32'hf77d0ff7;
      99: rom_word = 32'hbf510685;
      100: rom_word = 32'h1a102737;
      101: rom_word = 32'h47894714;
      102: rom_word = 32'h00a79533;
      103: rom_word = 32'hc7148ec9;
      104: rom_word = 32'h47934714;
      105: rom_word = 32'h0586fff5;
      106: rom_word = 32'hc71c8ff5;
      107: rom_word = 32'h8d5d431c;
      108: rom_word = 32'h005b97b7;
      109: rom_word = 32'h8793c308;
      110: rom_word = 32'h4705d807;
      111: rom_word = 32'h00b7e463;
      112: rom_word = 32'h02b7d733;
      113: rom_word = 32'h1c0047b7;
      114: rom_word = 32'he4e78023;
      115: rom_word = 32'h80824501;
      116: rom_word = 32'h003427b7;
      117: rom_word = 32'h04278793;
      118: rom_word = 32'h051e953e;
      119: rom_word = 32'h02854783;
      120: rom_word = 32'h1c004737;
      121: rom_word = 32'he4074703;
      122: rom_word = 32'h04239bbd;
      123: rom_word = 32'h478302f5;
      124: rom_word = 32'he7930285;
      125: rom_word = 32'h04230407;
      126: rom_word = 32'h47b702f5;
      127: rom_word = 32'ha0231c00;
      128: rom_word = 32'h0737e0e7;
      129: rom_word = 32'h8dd91000;
      130: rom_word = 32'h20070737;
      131: rom_word = 32'he0078793;
      132: rom_word = 32'h06670713;
      133: rom_word = 32'h0737c798;
      134: rom_word = 32'h07059000;
      135: rom_word = 32'hc3ccd11c;
      136: rom_word = 32'h47c1c7d8;
      137: rom_word = 32'h4783d15c;
      138: rom_word = 32'he7930285;
      139: rom_word = 32'h04230107;
      140: rom_word = 32'h450102f5;
      141: rom_word = 32'h27b78082;
      142: rom_word = 32'h87930034;
      143: rom_word = 32'h953e0427;
      144: rom_word = 32'h4783051e;
      145: rom_word = 32'h47370285;
      146: rom_word = 32'h47031c00;
      147: rom_word = 32'h9bbde407;
      148: rom_word = 32'h02f50423;
      149: rom_word = 32'h02854783;
      150: rom_word = 32'h0407e793;
      151: rom_word = 32'h02f50423;
      152: rom_word = 32'h1c0047b7;
      153: rom_word = 32'he0e7a023;
      154: rom_word = 32'h10000737;
      155: rom_word = 32'h07378dd9;
      156: rom_word = 32'h87932007;
      157: rom_word = 32'h0713e007;
      158: rom_word = 32'hc7980997;
      159: rom_word = 32'h90000737;
      160: rom_word = 32'hd11c0705;
      161: rom_word = 32'hc7d8c3cc;
      162: rom_word = 32'hd15c47c1;
      163: rom_word = 32'h02854783;
      164: rom_word = 32'h0107e793;
      165: rom_word = 32'h02f50423;
      166: rom_word = 32'h80824501;
      167: rom_word = 32'h1a1027b7;
      168: rom_word = 32'h1087c703;
      169: rom_word = 32'h1c0046b7;
      170: rom_word = 32'h00851813;
      171: rom_word = 32'h84239b3d;
      172: rom_word = 32'hc70310e7;
      173: rom_word = 32'h75131187;
      174: rom_word = 32'h87930ff5;
      175: rom_word = 32'h9b3d1007;
      176: rom_word = 32'h00e78c23;
      177: rom_word = 32'h0287c703;
      178: rom_word = 32'h84239b3d;
      179: rom_word = 32'hc68302e7;
      180: rom_word = 32'h4737e406;
      181: rom_word = 32'h20231c00;
      182: rom_word = 32'h0713e0d7;
      183: rom_word = 32'h06b7e007;
      184: rom_word = 32'hc3541000;
      185: rom_word = 32'h200706b7;
      186: rom_word = 32'hc714068d;
      187: rom_word = 32'h01085693;
      188: rom_word = 32'h200f0837;
      189: rom_word = 32'h0106e6b3;
      190: rom_word = 32'h06b7c754;
      191: rom_word = 32'h8d552007;
      192: rom_word = 32'h0693cb08;
      193: rom_word = 32'h0537fff6;
      194: rom_word = 32'h8ec97047;
      195: rom_word = 32'h06b7cb54;
      196: rom_word = 32'h06859000;
      197: rom_word = 32'hc38ccf14;
      198: rom_word = 32'hc683c3d0;
      199: rom_word = 32'he6930087;
      200: rom_word = 32'h84230106;
      201: rom_word = 32'hd39800d7;
      202: rom_word = 32'hd3d84771;
      203: rom_word = 32'h0287c703;
      204: rom_word = 32'h01076713;
      205: rom_word = 32'h02e78423;
      206: rom_word = 32'hff7d43d8;
      207: rom_word = 32'h00008082;
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
