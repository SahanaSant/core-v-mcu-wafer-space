/*
 * Copyright 2026 Yusef Karim
 * Solderpad Hardware License, Version 2.1, see LICENSE.md for details.
 * SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
 *
 * Trimmed from core-v-mcu/a2_boot/include/bootloader.h: this ROM never
 * resumes, so only jump_to_address survives.
 */

#ifndef __BOOT_LOADER_H__
#define __BOOT_LOADER_H__

static inline void __attribute__((noreturn)) jump_to_address(unsigned int address)
{
	void (*entry)(void) = (void (*)(void))((long)address);
	entry();
	while (1) {}
}

#endif /* __BOOT_LOADER_H__ */
