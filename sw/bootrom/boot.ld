/*
 * Copyright 2026 Yusef Karim
 * Solderpad Hardware License, Version 2.1, see LICENSE.md for details.
 * SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
 *
 * Adapted from core-v-mcu/a2_boot/core-v-mcu2-rom.ld. Every address there was
 * upstream's own boot-address layout, which ticket 04 said stops existing
 * entirely once L2 is 16 KiB contiguous from 0x1C00_0000; these are this
 * design's addresses instead.
 *
 * ROM: apb_soc_ctrl's r_bootaddr reset value is 0x1A00_0080 and boot_rom.sv
 * decodes ROM_ADDR_WIDTH=13 (8 KiB) from SOC_MEM_MAP_BOOT_ROM_START_ADDR
 * (0x1A00_0000); that decode window is fixed by upstream RTL this port
 * doesn't touch, not by how much code actually lands in it. The LENGTH here
 * is a build-time guard against overrunning that window, not the measured
 * size ticket 23 reports.
 *
 * L2: BOOT_STACK_RESERVE_BYTES (boot_image.h) at the top of the 16 KiB region,
 * for this ROM's own .bss (spi.c's auccmd buffer) and stack only. The ROM
 * never becomes L2-resident, so that's the only L2 it ever uses; everything
 * below is the application's. `stack` is pinned to the top of the L2 region
 * directly (ORIGIN + LENGTH) rather than computed as "wherever .ram's location
 * counter ends up, plus a size": that was core-v-mcu2-rom.ld's own pattern
 * (`stack = . + 1024` inside the .stack section, chained after .ram) and it
 * silently overflows the declared region by however large .bss is, since ld
 * only bounds-checks sections that emit real content, not symbol arithmetic.
 * Caught here because this region is small enough (512 B against upstream's
 * 16 KiB) for the overflow to land outside L2 entirely instead of just
 * eating slack.
 */

L2_TOP = 0x1C004000;

MEMORY
{
  ROM : ORIGIN = 0x1A000000, LENGTH = 0x2000
  L2  : ORIGIN = 0x1C003E00, LENGTH = 0x200
}

SECTIONS
{
    .text : {
        . = ALIGN(4);
        KEEP(*(.vectors))
        _stext = .;
        *(.text*)
        _etext = .;
        *(.rodata*)
        *(.data*)
        _endtext = .;
    } > ROM

    .ram : {
        . = ALIGN(4);
        _bss_start = .;
        *(.ram*)
        *(.bss*)
        *(.sbss*)
        . = ALIGN(4);
        _bss_end = .;
    } > L2

    /DISCARD/ : { *(.comment) *(.riscv.attributes) }
}

stack = L2_TOP;

ASSERT(stack - _bss_end >= 256, "sw/bootrom: less than 256 B left for the boot stack above .bss")
ASSERT(L2_TOP == ORIGIN(L2) + LENGTH(L2), "sw/bootrom: L2_TOP drifted from the L2 region's top")
