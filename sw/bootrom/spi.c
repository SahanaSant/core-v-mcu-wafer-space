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
 * Trimmed from core-v-mcu/a2_boot/spi.c to the single-SPI, boot-only subset
 * boot needs: open, the two reset commands, and a flash read. The
 * uDMA microcode sequences themselves (the kSPIm_* opcode streams) are
 * unchanged, because they are proven working sequences for this exact IP
 * block, not board-specific code. udma_qspim_write/udma_flash_readid/
 * udma_flash_write, unused by boot, are dropped.
 *
 * One real fix: udma_qspim_open()'s clock divisor assumed a fixed 5 MHz
 * peripheral clock, which was that board's FLL-derived udma_ctrl clock.
 * This design bypasses ref_clk_i undivided to periph_clk, so the divisor is
 * derived from that real
 * number rather than carried over. See PERIPH_CLK_HZ below.
 */

#include <stdint.h>

#include "core-v-mcu-config.h"
#include "udma_ctrl_reg_defs.h"
#include "udma_qspi_reg_defs.h"
#include "udma_qspi_driver.h"

/* soc_clk_o/periph_clk_o/cluster_clk_o are ref_clk_i, undivided. 5 MHz is the
 * frequency at which post-route STA closes at the slow corner. Keep this in
 * step with flow/config.yaml's CLOCK_PERIOD,
 * sw/app/uart.c's PERIPH_CLK_HZ, and the two sim constants named there. */
#define PERIPH_CLK_HZ 5000000u

/* udma_clk_div_cnt.sv toggles clk_o every `target` periph_clk cycles, so the
 * output period is 2*target periph_clk cycles: spi_clk = periph_clk / (2*N).
 * N=0 is not a valid "run at periph_clk/2" encoding (the counter's r_target-1
 * underflows to 255, i.e. divide-by-256), so the minimum useful N is 1.
 */
static uint8_t aucclkdiv;

uint16_t udma_qspim_open(uint8_t qspim_id, uint32_t spi_clk_hz)
{
	volatile UdmaCtrl_t *pudma_ctrl = (UdmaCtrl_t *)UDMA_CH_ADDR_CTRL;
	uint32_t divisor = PERIPH_CLK_HZ / (2u * spi_clk_hz);

	/* Enable reset then release it, and enable the QSPI's udma clock. */
	pudma_ctrl->reg_rst |= (UDMA_CTRL_QSPIM0_CLKEN << qspim_id);
	pudma_ctrl->reg_rst &= ~(UDMA_CTRL_QSPIM0_CLKEN << qspim_id);
	pudma_ctrl->reg_cg |= (UDMA_CTRL_QSPIM0_CLKEN << qspim_id);

	aucclkdiv = (divisor == 0u) ? 1u : (uint8_t)divisor;

	return 0;
}

static uint32_t auccmd[16];

uint32_t udma_flash_reset_enable(uint8_t qspim_id, uint8_t cs)
{
	UdmaQspi_t *pqspim_regs = (UdmaQspi_t *)(UDMA_CH_ADDR_QSPIM0 + qspim_id * UDMA_CH_SIZE);
	uint32_t *pcmd = auccmd;

	pqspim_regs->cmd_cfg_b.en = 0;
	pqspim_regs->cmd_cfg_b.clr = 1;

	*pcmd++ = kSPIm_Cfg | aucclkdiv;
	*pcmd++ = kSPIm_SOT | cs;
	*pcmd++ = kSPIm_SendCmd | (0x70066); /* JEDEC reset-enable, 0x66 */
	*pcmd++ = kSPIm_EOT | 1;

	pqspim_regs->cmd_saddr = (uint32_t)auccmd;
	pqspim_regs->cmd_size = (uint32_t)(pcmd - auccmd) * 4;
	pqspim_regs->cmd_cfg_b.en = 1;

	return 0;
}

uint32_t udma_flash_reset_memory(uint8_t qspim_id, uint8_t cs)
{
	UdmaQspi_t *pqspim_regs = (UdmaQspi_t *)(UDMA_CH_ADDR_QSPIM0 + qspim_id * UDMA_CH_SIZE);
	uint32_t *pcmd = auccmd;

	pqspim_regs->cmd_cfg_b.en = 0;
	pqspim_regs->cmd_cfg_b.clr = 1;

	*pcmd++ = kSPIm_Cfg | aucclkdiv;
	*pcmd++ = kSPIm_SOT | cs;
	*pcmd++ = kSPIm_SendCmd | (0x70099); /* JEDEC reset-memory, 0x99 */
	*pcmd++ = kSPIm_EOT | 1;

	pqspim_regs->cmd_saddr = (uint32_t)auccmd;
	pqspim_regs->cmd_size = (uint32_t)(pcmd - auccmd) * 4;
	pqspim_regs->cmd_cfg_b.en = 1;

	return 0;
}

/* Single-SPI JEDEC READ (0x03): 8-bit opcode, 24-bit address, data in. */
void udma_flash_read(uint32_t flash_addr, uint32_t l2addr, uint16_t read_len)
{
	UdmaQspi_t *pqspim_regs = (UdmaQspi_t *)(UDMA_CH_ADDR_QSPIM0);
	uint32_t *pcmd = auccmd;

	pqspim_regs->rx_cfg_b.en = 0;
	pqspim_regs->tx_cfg_b.en = 0;
	pqspim_regs->cmd_cfg_b.en = 0;

	*pcmd++ = kSPIm_Cfg | aucclkdiv;
	*pcmd++ = kSPIm_SOT;
	*pcmd++ = kSPIm_SendCmd | (0x70003);
	*pcmd++ = kSPIm_SendCmd | (0xf0000) | ((flash_addr >> 8) & 0xffff);
	*pcmd++ = kSPIm_SendCmd | (0x70000) | (flash_addr & 0xff);
	*pcmd++ = kSPIm_RxData | (0x00470000 | (read_len - 1));
	*pcmd++ = kSPIm_EOT | 1;

	pqspim_regs->rx_saddr = l2addr;
	pqspim_regs->rx_size = read_len;
	pqspim_regs->rx_cfg_b.en = 1;

	pqspim_regs->cmd_saddr = (uint32_t)auccmd;
	pqspim_regs->cmd_size = (uint32_t)(pcmd - auccmd) * 4;
	pqspim_regs->cmd_cfg_b.en = 1;

	while (pqspim_regs->rx_size != 0) {}
}
