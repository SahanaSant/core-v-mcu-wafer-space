/*
 * Copyright 2026 Yusef Karim
 * Solderpad Hardware License, Version 2.1, see LICENSE.md for details.
 * SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
 *
 * The flash image format: no XIP, no per-area table like
 * upstream's flash_v2_header_t (that format exists to describe several
 * independently-placed sections; this design copies exactly one image to one
 * fixed address, so it doesn't need one). A flat 8-byte header, then the image.
 */

#ifndef __BOOT_IMAGE_H__
#define __BOOT_IMAGE_H__

#include <stdint.h>

typedef struct {
	uint32_t size;  /* image size in bytes */
	uint32_t crc32; /* CRC-32/ISO-HDLC over exactly `size` bytes of the image */
} boot_header_t;

/* Flash layout: header at offset 0, image immediately after. */
#define BOOT_HEADER_FLASH_OFFSET 0u
#define BOOT_IMAGE_FLASH_OFFSET  ((uint32_t)sizeof(boot_header_t))

/* L2 destination: private bank 0, the bottom of the 16 KiB region
 * (0x1C00_0000-0x1C00_4000). The corner reserved for the ROM's boot-time stack
 * is fixed by this ROM's own linker script (boot.ld), at the top of the
 * region, BOOT_STACK_RESERVE_BYTES wide. The application's own linker script gets
 * everything below L2_IMAGE_MAX_SIZE.
 */
#define L2_IMAGE_BASE            0x1C000000u
#define L2_REGION_BYTES          (16u * 1024u)
#define BOOT_STACK_RESERVE_BYTES 512u
#define L2_IMAGE_MAX_SIZE        (L2_REGION_BYTES - BOOT_STACK_RESERVE_BYTES)

#endif /* __BOOT_IMAGE_H__ */
