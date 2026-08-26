/*
 * Copyright 2026 Yusef Karim
 * Solderpad Hardware License, Version 2.1, see LICENSE.md for details.
 * SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
 *
 * A read-write-read walk across every SRAM bank, byte enables checked
 * individually. [start, end) spans this app's own test range in L2 (main.c
 * picks it, well clear of the running code and the boot stack reserved at the
 * top of the 16 KiB region), which is a large enough span to cross both
 * interleaved channels and both private banks regardless of exactly how the
 * crossbar splits the flat address space between them.
 */

#include "sram_test.h"

uint32_t sram_rwr_walk(uint32_t start, uint32_t end)
{
	volatile uint8_t *p = (volatile uint8_t *)(uintptr_t)start;
	uint32_t const n = end - start;
	uint32_t mismatches = 0;
	uint32_t i;

	/* Write a pattern that varies per byte lane and per address, so a stuck
	 * bit or a byte-enable that silently writes the wrong lane shows up
	 * rather than being masked by a repeated constant. */
	for (i = 0; i < n; i++) {
		p[i] = (uint8_t)((i * 3u + 1u) ^ (i >> 8));
	}

	for (i = 0; i < n; i++) {
		uint8_t expected = (uint8_t)((i * 3u + 1u) ^ (i >> 8));
		if (p[i] != expected) {
			mismatches++;
		}
	}

	/* Second pass with the complement, so a byte lane that only ever reads
	 * back its own write (rather than the actual stored bit pattern) has a
	 * second chance to be caught. */
	for (i = 0; i < n; i++) {
		p[i] = (uint8_t)~((i * 3u + 1u) ^ (i >> 8));
	}

	for (i = 0; i < n; i++) {
		uint8_t expected = (uint8_t)~((i * 3u + 1u) ^ (i >> 8));
		if (p[i] != expected) {
			mismatches++;
		}
	}

	return mismatches;
}
