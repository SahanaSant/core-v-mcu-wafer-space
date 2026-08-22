/*
 * Copyright 2026 Yusef Karim
 * Solderpad Hardware License, Version 2.1, see LICENSE.md for details.
 * SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
 *
 * Minimal uDMA UART0 driver for the gate-level sim harness (ticket 31). The
 * register layout and divisor formula come from core-v-mcu/a2_boot/uart.c
 * (upstream's own board driver), not written from scratch: only the polling
 * open/write shape survives, trimmed to what this app needs (no rx).
 */

#ifndef __APP_UART_H__
#define __APP_UART_H__

#include <stdint.h>

void uart0_open(uint32_t baudrate);
void uart0_write(uint8_t const *buf, uint16_t len);
void uart0_puts(char const *s);

#endif /* __APP_UART_H__ */
