/*
 * Copyright 2026 Yusef Karim
 * Solderpad Hardware License, Version 2.1, see LICENSE.md for details.
 * SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
 *
 * Ticket 31's gate-level sim harness image: the thing sw/bootrom/main.c
 * copies from flash, CRC-checks and jumps to. Runs the two checks
 * sim/README.md's "first tests worth writing" list still needed a real image
 * for (a read-write-read SRAM walk and a UART character out; reset/clock
 * reaching the core and a real boot are proven just by getting here at all),
 * then reports the result over UART0 so the cocotb testbench can assert
 * against a fixed string instead of inspecting internal state.
 */

#include <stdint.h>

#include "sram_test.h"
#include "uart.h"

#define APP_BAUD_HZ 115200u

/* L2 is 0x1C00_0000-0x1C00_4000 (ticket 11/19); boot_image.h reserves the top
 * 512 B for sw/bootrom's own stack, which this app's crt0.S reuses as its own
 * stack (the ROM is done running once jump_to_address() reaches here), so the
 * test range has to stay clear of it. Keep this boundary in step with
 * sw/bootrom/include/boot_image.h's L2_IMAGE_MAX_SIZE if that ever changes.
 */
#define L2_IMAGE_BASE  0x1C000000u
#define L2_TEST_END    0x1C003E00u

/* Ticket 31: gate-level sim of the full SoC under Icarus runs at roughly
 * 5-6us of simulated time per real second (measured), so the full
 * [test_start, L2_TEST_END) range (~15 KiB, walked twice, byte by byte) would
 * take real hours to simulate. 512 B still crosses multiple word slots at
 * varying byte-lane positions -- enough to catch a byte-lane or depth-mux
 * bug -- without needing to walk the entire 16 KiB region. Revisit if this
 * ever needs to be a real coverage claim rather than a harness smoke test. */
#define SRAM_TEST_BYTES 512u

extern char _app_end[];

static void put_udec(uint32_t v)
{
	char digits[10];
	int n = 0;

	if (v == 0) {
		uart0_puts("0");
		return;
	}
	while (v != 0 && n < 10) {
		digits[n++] = (char)('0' + (v % 10u));
		v /= 10u;
	}
	while (n > 0) {
		char one[2] = {digits[--n], '\0'};
		uart0_puts(one);
	}
}

void __attribute__((noreturn)) app_main(void)
{
	uint32_t test_start = ((uint32_t)(uintptr_t)_app_end + 63u) & ~63u;
	uint32_t test_end = test_start + SRAM_TEST_BYTES;
	uint32_t mismatches;

	if (test_end > L2_TEST_END) {
		test_end = L2_TEST_END;
	}

	uart0_open(APP_BAUD_HZ);
	uart0_puts("BOOT OK\r\n");

	mismatches = sram_rwr_walk(test_start, test_end);

	if (mismatches == 0) {
		uart0_puts("SRAM PASS\r\n");
	} else {
		uart0_puts("SRAM FAIL ");
		put_udec(mismatches);
		uart0_puts("\r\n");
	}

	while (1) {}
}
