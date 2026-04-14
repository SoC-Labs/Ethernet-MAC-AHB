/*-----------------------------------------------------------------------------
 * SoCLabs Ethernet MAC Driver — Implementation
 *
 * Bare-metal driver for the OpenCores ethmac IP core via AHB-Lite.
 * Targets ARM Cortex-M0.
 *
 * A joint work commissioned on behalf of SoC Labs, under Arm Academic
 * Access license.
 *
 * Contributors
 *   David Mapstone (d.a.mapstone@soton.ac.uk)
 *
 * Copyright 2026, SoC Labs (www.soclabs.org)
 *---------------------------------------------------------------------------*/

#include "ethmac.h"

/* ── Initialisation ─────────────────────────────────────────────────────── */

void ethmac_init(ethmac_t *eth, uint32_t base, uint32_t tx_bd_num)
{
    eth->regs     = (ETHMAC_REGS_TypeDef *)base;
    eth->bd       = (__IO uint32_t *)(base + ETHMAC_BD_BASE);
    eth->tx_bd_num = tx_bd_num;

    /* Configure TX/RX descriptor split */
    eth->regs->TX_BD_NUM = tx_bd_num & 0xFFU;
}

/* ── MAC Address ────────────────────────────────────────────────────────── */

void ethmac_set_mac_addr(ethmac_t *eth, const uint8_t mac[6])
{
    /*
     * OpenCores ethmac MAC_ADDR0 / MAC_ADDR1 register layout (from the core
     * spec). "Byte N" is the Nth byte on the wire — so mac[0] is the first
     * byte transmitted (and the most-significant byte of the address):
     *
     *   MAC_ADDR1[15:8] = mac[0]   (byte 0, MSB on wire)
     *   MAC_ADDR1[ 7:0] = mac[1]   (byte 1)
     *   MAC_ADDR0[31:24]= mac[2]   (byte 2)
     *   MAC_ADDR0[23:16]= mac[3]   (byte 3)
     *   MAC_ADDR0[15: 8]= mac[4]   (byte 4)
     *   MAC_ADDR0[ 7:0] = mac[5]   (byte 5, LSB on wire)
     *
     * Prior revisions of this function wrote the address reversed (mac[0]
     * went into MAC_ADDR0[7:0] instead of MAC_ADDR1[15:8]), which happened
     * to be invisible in promiscuous mode but broke MAC-based RX filtering
     * and gave the OpenCores self-source check the wrong address.
     */
    eth->regs->MAC_ADDR0 = ((uint32_t)mac[2] << 24U) |
                           ((uint32_t)mac[3] << 16U) |
                           ((uint32_t)mac[4] <<  8U) |
                           ((uint32_t)mac[5] <<  0U);

    eth->regs->MAC_ADDR1 = ((uint32_t)mac[0] <<  8U) |
                           ((uint32_t)mac[1] <<  0U);
}

/* ── MII PHY Management ────────────────────────────────────────────────── */

static int ethmac_mii_wait(ethmac_t *eth, uint32_t timeout)
{
    uint32_t count = timeout;

    while (eth->regs->MIISTATUS & ETHMAC_MIISTATUS_BUSY_Msk) {
        if (timeout != 0U) {
            if (count == 0U)
                return -1;
            count--;
        }
    }
    return 0;
}

int ethmac_mii_read(ethmac_t *eth, uint32_t phy_addr, uint32_t reg_addr,
                     uint32_t timeout)
{
    /* Set PHY + register address */
    eth->regs->MIIADDRESS = ((phy_addr & 0x1FU) << 8U) |
                             (reg_addr & 0x1FU);

    /* Trigger single read (RSTAT) */
    eth->regs->MIICOMMAND = 0x2U;

    /* Wait for completion */
    if (ethmac_mii_wait(eth, timeout) != 0)
        return -1;

    return (int)(eth->regs->MIIRX_DATA & 0xFFFFU);
}

int ethmac_mii_write(ethmac_t *eth, uint32_t phy_addr, uint32_t reg_addr,
                      uint32_t data, uint32_t timeout)
{
    /* Set PHY + register address */
    eth->regs->MIIADDRESS = ((phy_addr & 0x1FU) << 8U) |
                             (reg_addr & 0x1FU);

    /* Set write data */
    eth->regs->MIITX_DATA = data & 0xFFFFU;

    /* Trigger write (WCTRLDATA) */
    eth->regs->MIICOMMAND = 0x4U;

    /* Wait for completion */
    return ethmac_mii_wait(eth, timeout);
}

/* ── Buffer Descriptor Management ───────────────────────────────────────── */

void ethmac_init_bds(ethmac_t *eth)
{
    uint32_t i;
    uint32_t rx_bd_num = ETHMAC_BD_MAX_COUNT - eth->tx_bd_num;

    /* Clear all TX descriptors */
    for (i = 0U; i < eth->tx_bd_num; i++) {
        eth->bd[i * 2]     = 0U;  /* Status/control */
        eth->bd[i * 2 + 1] = 0U;  /* Buffer pointer */
    }
    /* Set wrap bit on last TX descriptor */
    if (eth->tx_bd_num > 0U)
        eth->bd[(eth->tx_bd_num - 1U) * 2] = ETHMAC_TX_BD_WR_Msk;

    /* Clear all RX descriptors */
    for (i = 0U; i < rx_bd_num; i++) {
        uint32_t bd_idx = (eth->tx_bd_num + i) * 2;
        eth->bd[bd_idx]     = 0U;
        eth->bd[bd_idx + 1] = 0U;
    }
    /* Set wrap bit on last RX descriptor */
    if (rx_bd_num > 0U) {
        uint32_t last_rx = (eth->tx_bd_num + rx_bd_num - 1U) * 2;
        eth->bd[last_rx] = ETHMAC_RX_BD_WR_Msk;
    }
}

void ethmac_tx_bd_setup(ethmac_t *eth, uint32_t idx, uint32_t buf,
                         uint32_t len, uint32_t flags, uint32_t last)
{
    uint32_t status;

    status = (len << ETHMAC_TX_BD_LEN_Pos) | (flags & 0x7800U);
    if (last)
        status |= ETHMAC_TX_BD_WR_Msk;

    eth->bd[idx * 2]     = status;
    eth->bd[idx * 2 + 1] = buf;
}

void ethmac_rx_bd_setup(ethmac_t *eth, uint32_t idx, uint32_t buf,
                         uint32_t flags, uint32_t last)
{
    uint32_t bd_idx = (eth->tx_bd_num + idx) * 2;
    uint32_t status;

    status = ETHMAC_RX_BD_E_Msk | (flags & ETHMAC_RX_BD_IRQ_Msk);
    if (last)
        status |= ETHMAC_RX_BD_WR_Msk;

    eth->bd[bd_idx]     = status;
    eth->bd[bd_idx + 1] = buf;
}

/* ── Weak IRQ Handler Stub ──────────────────────────────────────────────── */

__attribute__((weak)) void ETHMAC_IRQHandler(void)
{
    /* Default: no-op. Override in application code. */
}
