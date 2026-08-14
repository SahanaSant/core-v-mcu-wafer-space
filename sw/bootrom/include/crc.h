/**********************************************************************
 *
 * Filename:    crc.h
 *
 * Description: CRC-32 (poly 0x04C11DB7, reflected, a.k.a. CRC-32/ISO-HDLC,
 *              the same algorithm zlib's crc32() implements) parameters and
 *              declarations.
 *
 * Notes:       Trimmed from core-v-mcu/a2_boot/include/crc.h, which carried
 *              CRC-CCITT, CRC-16 and CRC-32 all behind one #ifdef and defaulted
 *              to CRC-CCITT. Ticket 04 settled on CRC32, so this ROM only ever
 *              needs the one, and crcSlow() (bit-serial, no lookup table) is
 *              the only variant kept: a 256-entry crc32 table would be the
 *              single biggest thing in this ROM's .bss for a checksum that
 *              runs once per boot over at most 16 KiB, so the table's O(1)
 *              per-byte cost buys nothing here that's worth the RAM.
 *
 * Copyright (c) 2000 by Michael Barr.  This software is placed into
 * the public domain and may be used for any purpose.  However, this
 * notice must not be changed or removed and no warranty is either
 * expressed or implied by its publication or distribution.
 **********************************************************************/

#ifndef _crc_h
#define _crc_h

#include <stdint.h>

#define TRUE  1
#define FALSE 0

/* Fixed-width, deliberately: WIDTH in crc.c is 8*sizeof(crc), and this has to
 * stay 32 bits on every host that builds it, not just the RV32 ilp32 target
 * where `unsigned long` happens to be 32 bits. A host build (checking this
 * file against the standard CRC-32 check value, or a future image-signing
 * tool) is a 64-bit `unsigned long` and silently computes a different, wider
 * CRC otherwise -- caught by running exactly that check during ticket 23.
 */
typedef uint32_t crc;

#define CRC_NAME          "CRC-32"
#define POLYNOMIAL        0x04C11DB7
#define INITIAL_REMAINDER 0xFFFFFFFF
#define FINAL_XOR_VALUE   0xFFFFFFFF
#define REFLECT_DATA      TRUE
#define REFLECT_REMAINDER TRUE
#define CHECK_VALUE       0xCBF43926

crc crcSlow(unsigned char const message[], int nBytes);

#endif /* _crc_h */
