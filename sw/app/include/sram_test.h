/*
 * Copyright 2026 Yusef Karim
 * Solderpad Hardware License, Version 2.1, see LICENSE.md for details.
 * SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
 */

#ifndef __APP_SRAM_TEST_H__
#define __APP_SRAM_TEST_H__

#include <stdint.h>

/* Byte-wise read-write-read walk across [start, end). Returns the number of
 * byte-lane mismatches found (0 == pass). Writes every byte individually
 * (never a whole word at once) so a byte-lane or depth-mux bug in the SRAM
 * wrapper can't hide behind a word-wide store. */
uint32_t sram_rwr_walk(uint32_t start, uint32_t end);

#endif /* __APP_SRAM_TEST_H__ */
