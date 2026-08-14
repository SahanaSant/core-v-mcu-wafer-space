/*
 * Copyright 2026 Yusef Karim
 * Solderpad Hardware License, Version 2.1, see LICENSE.md for details.
 * SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
 *
 * Reset vector for the GF180MCU boot ROM. Trimmed from core-v-mcu/a2_boot/crt0.S:
 * same 32-entry trap-vector table and the same .org 0x80 reset vector, because
 * apb_soc_ctrl.sv's r_bootaddr reset value (0x1A00_0080) is upstream RTL this
 * port does not touch, so the ROM's word 32 has to be _start regardless of what
 * runs after it. changeStack is gone: this ROM never becomes L2-resident and
 * runs its whole life on one stack, so there is nothing to switch away from.
 */

  .section .text

  .section .vectors, "ax"
  .option norvc;
  .org 0x0
  jal x0, default_handler
  jal x0, default_handler
  jal x0, default_handler
  jal x0, default_handler
  jal x0, default_handler
  jal x0, default_handler
  jal x0, default_handler
  jal x0, default_handler
  jal x0, default_handler
  jal x0, default_handler
  jal x0, default_handler
  jal x0, default_handler
  jal x0, default_handler
  jal x0, default_handler
  jal x0, default_handler
  jal x0, default_handler
  jal x0, default_handler
  jal x0, default_handler
  jal x0, default_handler
  jal x0, default_handler
  jal x0, default_handler
  jal x0, default_handler
  jal x0, default_handler
  jal x0, default_handler
  jal x0, default_handler
  jal x0, default_handler
  jal x0, default_handler
  jal x0, default_handler
  jal x0, default_handler
  jal x0, default_handler
  jal x0, default_handler
  jal x0, default_handler

  //// reset vector: word 32, byte offset 0x80, matching apb_soc_ctrl's
  //// r_bootaddr reset value of 0x1A00_0080.

  .org 0x80

.global _start
.type _start, @function
  _start:
  /* clear the bss segment (auccmd in spi.c, and any other zero-init statics) */
  la t0, _bss_start
  la t1, _bss_end
1:
  sw zero, 0(t0)
  addi t0, t0, 4
  bltu t0, t1, 1b
  la x2, stack
  j boot_main

default_handler:
  mret
