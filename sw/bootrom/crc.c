/**********************************************************************
 *
 * Filename:    crc.c
 *
 * Description: Bit-serial CRC-32/ISO-HDLC (reflected in, reflected out),
 *              trimmed from core-v-mcu/a2_boot/crc.c (itself public domain,
 *              Michael Barr), which supported CRC-CCITT/CRC-16/CRC-32 behind
 *              one #ifdef. This file only ever builds for CRC-32 (crc.h fixes
 *              POLYNOMIAL/INITIAL_REMAINDER/FINAL_XOR_VALUE and both reflect
 *              flags to CRC-32's values), so the generality that switch bought
 *              is dead weight here and both reflect steps are unconditional.
 *              crcFast()/crcInit() and the 256-entry table they need are
 *              dropped too; see crc.h for why.
 *
 * Copyright (c) 2000 by Michael Barr.  This software is placed into
 * the public domain and may be used for any purpose.  However, this
 * notice must not be changed or removed and no warranty is either
 * expressed or implied by its publication or distribution.
 **********************************************************************/

#include "crc.h"

#define WIDTH  (8 * sizeof(crc))
#define TOPBIT (UINT32_C(1) << (WIDTH - 1))

static uint32_t reflect(uint32_t data, unsigned char nBits)
{
	uint32_t reflection = 0;
	unsigned char bit;

	for (bit = 0; bit < nBits; ++bit) {
		if (data & 0x01) {
			reflection |= (UINT32_C(1) << ((nBits - 1) - bit));
		}
		data >>= 1;
	}

	return reflection;
}

crc crcSlow(unsigned char const message[], int nBytes)
{
	crc remainder = INITIAL_REMAINDER;
	int byte;
	unsigned char bit;

	for (byte = 0; byte < nBytes; ++byte) {
		remainder ^= ((crc)reflect(message[byte], 8) << (WIDTH - 8));

		for (bit = 8; bit > 0; --bit) {
			if (remainder & TOPBIT) {
				remainder = (remainder << 1) ^ POLYNOMIAL;
			} else {
				remainder = (remainder << 1);
			}
		}
	}

	return reflect(remainder, WIDTH) ^ FINAL_XOR_VALUE;
}
