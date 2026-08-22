#!/usr/bin/env python3
# Copyright 2026 Yusef Karim
# Solderpad Hardware License, Version 2.1, see LICENSE.md for details.
# SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
#
# Builds the flash image sw/bootrom/main.c expects: an 8-byte little-endian
# boot_header_t (size, crc32) at offset 0, the app binary immediately after
# (sw/bootrom/include/boot_image.h's BOOT_HEADER_FLASH_OFFSET/
# BOOT_IMAGE_FLASH_OFFSET). CRC is CRC-32/ISO-HDLC, the same algorithm
# sw/bootrom/crc.c's crcSlow() implements (confirmed against crc.h's own
# comment, not assumed) -- Python's zlib.crc32() is that algorithm, so this
# doesn't need to reimplement crcSlow to stay byte-for-byte compatible.
#
# Also writes a $readmemh-format hex file (one byte per line) for
# core-v-mcu/tb/qspi_model/GD25Q128B.v's `initfile` parameter, which is how
# sim/'s cocotb harness preloads the flash model ticket 31 uses instead of a
# hand-rolled QSPI BFM.

import argparse
import struct
import sys
import zlib

L2_IMAGE_MAX_SIZE = 16 * 1024 - 512  # boot_image.h: 16 KiB L2 minus the 512 B boot stack reserve


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--input", required=True, help="app.bin, the compiled app image")
    ap.add_argument("--flash-bin", required=True, help="header + image, as raw bytes")
    ap.add_argument("--flash-hex", required=True, help="same content, $readmemh format")
    args = ap.parse_args()

    with open(args.input, "rb") as f:
        image = f.read()

    if len(image) == 0 or len(image) > L2_IMAGE_MAX_SIZE:
        print(
            f"error: app image is {len(image)} bytes, must be 1..{L2_IMAGE_MAX_SIZE} "
            "(boot_image.h's L2_IMAGE_MAX_SIZE)",
            file=sys.stderr,
        )
        return 1

    # Pad to a whole number of 32-bit words. The uDMA receive channel the boot
    # ROM uses runs at 32-bit datasize, and udma_spim_txrx only hands a word to
    # the DMA once it has assembled four bytes. A tail of one to three bytes is
    # received off the wire, sits in the shift register and is never delivered,
    # so the channel's byte counter stops short of zero and udma_flash_read's
    # `while (rx_size != 0)` never exits.
    #
    # sw/bootrom/main.c now rounds its own transfer up, so this is no longer
    # the only thing standing between a mis-sized image and a silent hang. It
    # stays because that guard only reaches silicon through a re-hardened ROM,
    # and because padding before the CRC keeps the two in step: the header's
    # size and the ROM's crcSlow() both cover the padded image.
    pad = (-len(image)) % 4
    if pad:
        image += b"\x00" * pad
        print(f"padded app image with {pad} zero byte(s) to a 32-bit word boundary")

    crc32 = zlib.crc32(image) & 0xFFFFFFFF
    header = struct.pack("<II", len(image), crc32)  # little-endian: size, crc32
    flash = header + image

    with open(args.flash_bin, "wb") as f:
        f.write(flash)

    with open(args.flash_hex, "w") as f:
        for b in flash:
            f.write(f"{b:02x}\n")

    print(f"app image: {len(image)} bytes, crc32 0x{crc32:08x}")
    print(f"flash image: {len(flash)} bytes (8-byte header + image)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
