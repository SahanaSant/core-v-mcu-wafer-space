/*
 * Copyright 2026 Yusef Karim
 * Solderpad Hardware License, Version 2.1, see LICENSE.md for details.
 * SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
 *
 * Linker script for the app image. sw/bootrom/main.c copies this
 * image to L2_IMAGE_BASE and jumps straight to its first byte (no reset
 * vector table, see crt0.S), so .text has to lead and crt0.o has to be the
 * first object on the link line for _start to land there (enforced by
 * Makefile's link order, not by this script).
 *
 * The 0x3E00 region length is sw/bootrom/include/boot_image.h's
 * L2_IMAGE_MAX_SIZE (16 KiB minus the 512 B boot stack reserve); ld's own
 * region-overflow check is what actually guards this, so there's no separate
 * ASSERT here the way boot.ld needed one for symbol arithmetic ld doesn't
 * check. stack_top matches boot.ld's `stack`: the boot ROM is done running
 * once this image starts, so reusing its 512 B stack region rather than
 * carving out a second one is a free, deliberate choice, not an oversight.
 */

/* Needed because -T replaces the toolchain's default script wholesale,
 * taking its implicit ENTRY(_start) with it: without this, --gc-sections has
 * no root to keep and links a zero-byte binary (caught by app.sh reporting
 * 0/0/0 text/data/bss and gen_flash_image.py refusing an empty image).
 * sw/bootrom/boot.ld doesn't need this because its vectors section is
 * KEEP()'d directly instead, which anchors _start the same way. */
ENTRY(_start)

MEMORY
{
  L2 : ORIGIN = 0x1C000000, LENGTH = 0x3E00
}

SECTIONS
{
  .text : {
    . = ALIGN(4);
    *(.text*)
    *(.rodata*)
  } > L2

  .data : {
    *(.data*)
  } > L2

  .bss : {
    . = ALIGN(4);
    _bss_start = .;
    *(.bss*)
    *(.sbss*)
    . = ALIGN(4);
    _bss_end = .;
  } > L2

  /DISCARD/ : { *(.comment) *(.riscv.attributes) }
}

_app_end = _bss_end;
stack_top = 0x1C004000;

ASSERT(stack_top - _app_end >= 256, "sw/app: less than 256 B left for the app's stack")
