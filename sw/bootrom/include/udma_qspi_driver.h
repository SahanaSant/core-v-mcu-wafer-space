/*
 * Copyright 2021 QuickLogic
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 *
 * SPDX-License-Identifier: Apache-2.0
 *
 * Unchanged from core-v-mcu/a2_boot/include/udma_qspi_driver.h except for the
 * function declarations at the bottom, trimmed to what sw/bootrom/spi.c
 * actually implements (open plus reset-enable/reset-memory/read; no close,
 * no generic control, no write, no read-into-buffer).
 */

#ifndef DRIVERS_INCLUDE_UDMA_QSPIM_DRIVER_H_
#define DRIVERS_INCLUDE_UDMA_QSPIM_DRIVER_H_

#include <stdint.h>

typedef enum {
	kSPIm_Cfg = (0x0 << 28),
	kSPIm_SOT = (0x1 << 28),
	kSPIm_SendCmd = (0x2 << 28),
	kSPIm_Dummy = (0x4 << 28),
	kSPIm_Wait = (0x5 << 28),
	kSPIm_TxData = (0x6 << 28),
	kSPIm_RxData = (0x7 << 28),
	kSPIm_Repeat = (0x8 << 28),
	kSPIm_EOT = (0x9 << 28),
	kSPIm_RepeatEnd = (0xa << 28),
	kSPIm_RxCheck = (0xb << 28),
	kSPIm_FDX = (0xc << 28),
	kSPIm_UCA = (0xd << 28),
	kSPIm_UCS = (0xe << 28)
} spim_cmd_t;

uint16_t udma_qspim_open(uint8_t qspim_id, uint32_t spi_clk_hz);
uint32_t udma_flash_reset_enable(uint8_t qspim_id, uint8_t cs);
uint32_t udma_flash_reset_memory(uint8_t qspim_id, uint8_t cs);
void udma_flash_read(uint32_t flash_addr, uint32_t l2addr, uint16_t read_len);

#endif /* DRIVERS_INCLUDE_UDMA_QSPIM_DRIVER_H_ */
