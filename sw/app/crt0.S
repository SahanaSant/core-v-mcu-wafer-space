/*
 * Copyright 2026 Yusef Karim
 * Solderpad Hardware License, Version 2.1, see LICENSE.md for details.
 * SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
 *
 * Entry point for ticket 31's app image. No trap-vector table: unlike
 * sw/bootrom/crt0.S, this image is never reached by a hardware reset vector,
 * only by sw/bootrom/main.c's jump_to_address() calling it as a plain C
 * function, so _start just needs to be the first thing in .text.
 */

  .section .text

.global _start
.type _start, @function
_start:
  la t0, _bss_start
  la t1, _bss_end
1:
  bgeu t0, t1, 2f
  sw zero, 0(t0)
  addi t0, t0, 4
  j 1b
2:
  la sp, stack_top
  jal app_main
  /* app_main is noreturn; spin if it somehow returns. */
3:
  j 3b
