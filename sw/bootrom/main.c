/*
 * Copyright 2026 Yusef Karim
 * Solderpad Hardware License, Version 2.1, see LICENSE.md for details.
 * SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
 *
 * GF180MCU boot ROM. Ticket 04's architecture: SPI-flash boot only, single
 * SPI, CRC32-checked before jump, no bootsel fallback, JTAG-only recovery on
 * failure. This replaces upstream's a2_boot/main.c (bootsel-driven SPI/I2C
 * dual path) entirely rather than trimming it in place: the two are different
 * state machines, not one with branches removed.
 *
 * Boot flow: bring up uDMA QSPI0 in single-SPI mode, read the 8-byte header at
 * flash offset 0, stream the image it describes into L2 at L2_IMAGE_BASE, CRC
 * it, and jump on match. On any failure (oversized header, CRC mismatch) halt
 * and spin: the JTAG debug module can still halt the core and write L2 over
 * the system bus regardless of what this ROM does from here, so there is
 * nothing for a ROM-level retry to add.
 *
 * Both uDMA reads land at L2_IMAGE_BASE and nowhere else, on purpose:
 * udma_spim_reg_if.sv's rx_saddr is L2_AWIDTH_NOAL bits wide (an L2-local
 * offset sized to this design's 16 KiB L2, currently 13 bits -- narrower than
 * cmd_saddr, which the CSV and generated header both give the full 32 bits,
 * because the command stream reaches the QSPI over a different, full-width
 * path than the bulk rx/tx data does). A destination address has to fit that
 * local offset, not the CPU's global 0x1C00_0000-based view of the same byte.
 * Rather than track that width precisely (it moves with L2_MEM_ADDR_WIDTH,
 * which moves with NB_L2_CHANNELS), every rx_saddr this ROM ever writes is
 * L2_IMAGE_BASE itself: offset 0 from L2's own base, representable regardless
 * of how wide the field actually is. The header is read there first and
 * copied into locals before the second read overwrites it with the real
 * image at the same address.
 */

#include <stdint.h>

#include "boot_image.h"
#include "bootloader.h"
#include "crc.h"
#include "udma_qspi_driver.h"

/* Conservative: boot-time throughput doesn't matter for a one-shot image
 * copy (ticket 04), so there's no reason to push the flash or the uDMA clock
 * divisor's rounding anywhere near their limits.
 */
#define BOOT_SPI_CLK_HZ 2500000u

static void __attribute__((noreturn)) halt(void)
{
	while (1) {}
}

void __attribute__((noreturn)) boot_main(void)
{
	volatile boot_header_t const *header = (boot_header_t const *)(uintptr_t)L2_IMAGE_BASE;
	uint32_t size, crc32;

	udma_qspim_open(0, BOOT_SPI_CLK_HZ);
	udma_flash_reset_enable(0, 0);
	udma_flash_reset_memory(0, 0);

	udma_flash_read(BOOT_HEADER_FLASH_OFFSET, L2_IMAGE_BASE, sizeof(*header));
	size = header->size;
	crc32 = header->crc32;

	if (size == 0 || size > L2_IMAGE_MAX_SIZE) {
		halt();
	}

	/* Overwrites the header just read at the same address with the real
	 * image; size and crc32 above are already copied out to locals. */
	udma_flash_read(BOOT_IMAGE_FLASH_OFFSET, L2_IMAGE_BASE, (uint16_t)size);

	if (crcSlow((unsigned char const *)(uintptr_t)L2_IMAGE_BASE, (int)size) != crc32) {
		halt();
	}

	jump_to_address(L2_IMAGE_BASE);
}
