/*-----------------------------------------------------------------------------
 * SoCLabs Ethernet MAC Driver — Header
 *
 * CMSIS-style bare-metal driver for the OpenCores ethmac IP core
 * accessed via the AHB-Lite wrapper (ethmac_ahb).
 *
 * Register structs and bit definitions are auto-generated from SystemRDL
 * via ethmac_regs.generated.h. This header adds the driver-level API.
 *
 * Target: ARM Cortex-M0 (word-aligned access only, no OS)
 *
 * A joint work commissioned on behalf of SoC Labs, under Arm Academic
 * Access license.
 *
 * Contributors
 *   David Mapstone (d.a.mapstone@soton.ac.uk)
 *
 * Copyright 2026, SoC Labs (www.soclabs.org)
 *---------------------------------------------------------------------------*/

#ifndef ETHMAC_H
#define ETHMAC_H

#include "ethmac_regs.generated.h"  /* ETHMAC_REGS_TypeDef + bit defs */

#ifdef __cplusplus
extern "C" {
#endif

/* ── Convenience aliases for frequently used bit definitions ────────────── */

/* MODER */
#define ETHMAC_MODER_RXEN_Pos      ETHMAC_REGS_MODER_RXEN_Pos
#define ETHMAC_MODER_RXEN_Msk      ETHMAC_REGS_MODER_RXEN_Msk
#define ETHMAC_MODER_TXEN_Pos      ETHMAC_REGS_MODER_TXEN_Pos
#define ETHMAC_MODER_TXEN_Msk      ETHMAC_REGS_MODER_TXEN_Msk
#define ETHMAC_MODER_FULLD_Pos     ETHMAC_REGS_MODER_FULLD_Pos
#define ETHMAC_MODER_FULLD_Msk     ETHMAC_REGS_MODER_FULLD_Msk
#define ETHMAC_MODER_PRO_Pos       ETHMAC_REGS_MODER_PRO_Pos
#define ETHMAC_MODER_PRO_Msk       ETHMAC_REGS_MODER_PRO_Msk
#define ETHMAC_MODER_LOOPBK_Pos    ETHMAC_REGS_MODER_LOOPBK_Pos
#define ETHMAC_MODER_LOOPBK_Msk    ETHMAC_REGS_MODER_LOOPBK_Msk
#define ETHMAC_MODER_CRCEN_Pos     ETHMAC_REGS_MODER_CRCEN_Pos
#define ETHMAC_MODER_CRCEN_Msk     ETHMAC_REGS_MODER_CRCEN_Msk
#define ETHMAC_MODER_PAD_Pos       ETHMAC_REGS_MODER_PAD_Pos
#define ETHMAC_MODER_PAD_Msk       ETHMAC_REGS_MODER_PAD_Msk

/* INT_SOURCE / INT_MASK */
#define ETHMAC_INT_TXB_Pos         ETHMAC_REGS_INT_SOURCE_TXB_Pos
#define ETHMAC_INT_TXB_Msk         ETHMAC_REGS_INT_SOURCE_TXB_Msk
#define ETHMAC_INT_TXE_Pos         ETHMAC_REGS_INT_SOURCE_TXE_Pos
#define ETHMAC_INT_TXE_Msk         ETHMAC_REGS_INT_SOURCE_TXE_Msk
#define ETHMAC_INT_RXB_Pos         ETHMAC_REGS_INT_SOURCE_RXB_Pos
#define ETHMAC_INT_RXB_Msk         ETHMAC_REGS_INT_SOURCE_RXB_Msk
#define ETHMAC_INT_RXE_Pos         ETHMAC_REGS_INT_SOURCE_RXE_Pos
#define ETHMAC_INT_RXE_Msk         ETHMAC_REGS_INT_SOURCE_RXE_Msk
#define ETHMAC_INT_BUSY_Pos        ETHMAC_REGS_INT_SOURCE_BUSY_Pos
#define ETHMAC_INT_BUSY_Msk        ETHMAC_REGS_INT_SOURCE_BUSY_Msk

/* MIISTATUS */
#define ETHMAC_MIISTATUS_BUSY_Pos  ETHMAC_REGS_MIISTATUS_BUSY_Pos
#define ETHMAC_MIISTATUS_BUSY_Msk  ETHMAC_REGS_MIISTATUS_BUSY_Msk

/* ── Buffer Descriptor Constants ────────────────────────────────────────── */

#define ETHMAC_BD_BASE             0x400U   /* Byte offset from register base */
#define ETHMAC_BD_MAX_COUNT        128U     /* Total descriptors (TX + RX)    */
#define ETHMAC_BD_SIZE             8U       /* Bytes per descriptor (2 words) */

/* TX Buffer Descriptor Status/Control Bits (Word 0, bits [15:0]) */
#define ETHMAC_TX_BD_RD_Pos        15U      /* Ready (MAC owns = 1)   */
#define ETHMAC_TX_BD_RD_Msk        (1UL << 15U)
#define ETHMAC_TX_BD_IRQ_Pos       14U      /* Interrupt on complete  */
#define ETHMAC_TX_BD_IRQ_Msk       (1UL << 14U)
#define ETHMAC_TX_BD_WR_Pos        13U      /* Wrap (last descriptor) */
#define ETHMAC_TX_BD_WR_Msk        (1UL << 13U)
#define ETHMAC_TX_BD_PAD_Pos       12U      /* Pad short frames       */
#define ETHMAC_TX_BD_PAD_Msk       (1UL << 12U)
#define ETHMAC_TX_BD_CRC_Pos       11U      /* Append CRC             */
#define ETHMAC_TX_BD_CRC_Msk       (1UL << 11U)
#define ETHMAC_TX_BD_LEN_Pos       16U      /* Frame length [31:16]   */

/* RX Buffer Descriptor Status/Control Bits (Word 0, bits [15:0]) */
#define ETHMAC_RX_BD_E_Pos         15U      /* Empty (MAC owns = 1)   */
#define ETHMAC_RX_BD_E_Msk         (1UL << 15U)
#define ETHMAC_RX_BD_IRQ_Pos       14U      /* Interrupt on receive   */
#define ETHMAC_RX_BD_IRQ_Msk       (1UL << 14U)
#define ETHMAC_RX_BD_WR_Pos        13U      /* Wrap (last descriptor) */
#define ETHMAC_RX_BD_WR_Msk        (1UL << 13U)
#define ETHMAC_RX_BD_LEN_Pos       16U      /* Frame length [31:16]   */

/* ── Driver handle ──────────────────────────────────────────────────────── */

typedef struct {
    ETHMAC_REGS_TypeDef *regs;     /* Register base (AHB slave)          */
    __IO uint32_t       *bd;       /* Buffer descriptor base (regs + 0x400) */
    uint32_t             tx_bd_num; /* Number of TX descriptors           */
} ethmac_t;

/* ── Initialisation ─────────────────────────────────────────────────────── */

/**
 * Initialise an Ethernet MAC driver handle.
 *
 * @param eth       Pointer to caller-allocated ethmac_t.
 * @param base      Physical base address of the AHB slave port.
 * @param tx_bd_num Number of TX buffer descriptors (default 64, max 128).
 */
void ethmac_init(ethmac_t *eth, uint32_t base, uint32_t tx_bd_num);

/* ── MAC Control ────────────────────────────────────────────────────────── */

/** Enable both TX and RX. */
static inline void ethmac_enable(ethmac_t *eth)
{
    eth->regs->MODER |= ETHMAC_MODER_TXEN_Msk | ETHMAC_MODER_RXEN_Msk;
}

/** Disable both TX and RX. */
static inline void ethmac_disable(ethmac_t *eth)
{
    eth->regs->MODER &= ~(ETHMAC_MODER_TXEN_Msk | ETHMAC_MODER_RXEN_Msk);
}

/** Set full-duplex mode. */
static inline void ethmac_set_full_duplex(ethmac_t *eth)
{
    eth->regs->MODER |= ETHMAC_MODER_FULLD_Msk;
}

/** Set half-duplex mode. */
static inline void ethmac_set_half_duplex(ethmac_t *eth)
{
    eth->regs->MODER &= ~ETHMAC_MODER_FULLD_Msk;
}

/** Enable promiscuous mode. */
static inline void ethmac_set_promiscuous(ethmac_t *eth, uint32_t en)
{
    if (en)
        eth->regs->MODER |= ETHMAC_MODER_PRO_Msk;
    else
        eth->regs->MODER &= ~ETHMAC_MODER_PRO_Msk;
}

/** Enable loopback mode. */
static inline void ethmac_set_loopback(ethmac_t *eth, uint32_t en)
{
    if (en)
        eth->regs->MODER |= ETHMAC_MODER_LOOPBK_Msk;
    else
        eth->regs->MODER &= ~ETHMAC_MODER_LOOPBK_Msk;
}

/* ── MAC Address ────────────────────────────────────────────────────────── */

/**
 * Set the MAC address.
 *
 * @param eth   Driver handle.
 * @param mac   6-byte MAC address array (network byte order).
 */
void ethmac_set_mac_addr(ethmac_t *eth, const uint8_t mac[6]);

/* ── Interrupts ─────────────────────────────────────────────────────────── */

/** Read and clear interrupt source flags. */
static inline uint32_t ethmac_get_int_source(ethmac_t *eth)
{
    uint32_t src = eth->regs->INT_SOURCE;
    eth->regs->INT_SOURCE = src;  /* W1C: write back to clear */
    return src;
}

/** Set interrupt mask (enable bits). */
static inline void ethmac_set_int_mask(ethmac_t *eth, uint32_t mask)
{
    eth->regs->INT_MASK = mask;
}

/* ── MII PHY Management ────────────────────────────────────────────────── */

/**
 * Configure the MII clock divider.
 *
 * @param eth      Driver handle.
 * @param clkdiv   Clock divider value. MII_CLK = SYS_CLK / (2*(clkdiv+1)).
 */
static inline void ethmac_mii_set_clkdiv(ethmac_t *eth, uint32_t clkdiv)
{
    eth->regs->MIIMODER = (eth->regs->MIIMODER & ~0xFFU) | (clkdiv & 0xFFU);
}

/**
 * Read a PHY register via MII.
 *
 * @param eth      Driver handle.
 * @param phy_addr PHY device address (0-31).
 * @param reg_addr PHY register address (0-31).
 * @param timeout  Busy-wait loop limit (0 = infinite).
 * @return Register value, or -1 on timeout.
 */
int ethmac_mii_read(ethmac_t *eth, uint32_t phy_addr, uint32_t reg_addr,
                     uint32_t timeout);

/**
 * Write a PHY register via MII.
 *
 * @param eth      Driver handle.
 * @param phy_addr PHY device address (0-31).
 * @param reg_addr PHY register address (0-31).
 * @param data     16-bit value to write.
 * @param timeout  Busy-wait loop limit (0 = infinite).
 * @return 0 on success, -1 on timeout.
 */
int ethmac_mii_write(ethmac_t *eth, uint32_t phy_addr, uint32_t reg_addr,
                      uint32_t data, uint32_t timeout);

/* ── Buffer Descriptor Management ───────────────────────────────────────── */

/**
 * Initialise all buffer descriptors (clear status, set wrap on last).
 *
 * @param eth  Driver handle (tx_bd_num must be set via ethmac_init).
 */
void ethmac_init_bds(ethmac_t *eth);

/**
 * Set up a TX buffer descriptor.
 *
 * @param eth    Driver handle.
 * @param idx    TX descriptor index (0 to tx_bd_num-1).
 * @param buf    Physical address of TX frame buffer.
 * @param len    Frame length in bytes.
 * @param flags  Control flags (IRQ, PAD, CRC bits ORed together).
 * @param last   Non-zero if this is the last TX descriptor (sets WR).
 */
void ethmac_tx_bd_setup(ethmac_t *eth, uint32_t idx, uint32_t buf,
                         uint32_t len, uint32_t flags, uint32_t last);

/** Mark a TX descriptor as ready (hand to MAC). */
static inline void ethmac_tx_bd_ready(ethmac_t *eth, uint32_t idx)
{
    eth->bd[idx * 2] |= ETHMAC_TX_BD_RD_Msk;
}

/** Check if a TX descriptor is complete (CPU owns). */
static inline uint32_t ethmac_tx_bd_done(ethmac_t *eth, uint32_t idx)
{
    return !(eth->bd[idx * 2] & ETHMAC_TX_BD_RD_Msk);
}

/**
 * Set up an RX buffer descriptor.
 *
 * @param eth    Driver handle.
 * @param idx    RX descriptor index (0 to rx_bd_num-1). Offset from tx_bd_num.
 * @param buf    Physical address of RX frame buffer.
 * @param flags  Control flags (IRQ bit).
 * @param last   Non-zero if this is the last RX descriptor (sets WR).
 */
void ethmac_rx_bd_setup(ethmac_t *eth, uint32_t idx, uint32_t buf,
                         uint32_t flags, uint32_t last);

/** Mark an RX descriptor as empty (hand to MAC). */
static inline void ethmac_rx_bd_empty(ethmac_t *eth, uint32_t idx)
{
    uint32_t bd_idx = (eth->tx_bd_num + idx) * 2;
    eth->bd[bd_idx] |= ETHMAC_RX_BD_E_Msk;
}

/** Check if an RX descriptor has a received frame (CPU owns). */
static inline uint32_t ethmac_rx_bd_received(ethmac_t *eth, uint32_t idx)
{
    uint32_t bd_idx = (eth->tx_bd_num + idx) * 2;
    return !(eth->bd[bd_idx] & ETHMAC_RX_BD_E_Msk);
}

/** Get the received frame length from an RX descriptor. */
static inline uint32_t ethmac_rx_bd_length(ethmac_t *eth, uint32_t idx)
{
    uint32_t bd_idx = (eth->tx_bd_num + idx) * 2;
    return (eth->bd[bd_idx] >> ETHMAC_RX_BD_LEN_Pos) & 0xFFFFU;
}

/* ── IRQ Handler Stub (weak, user-overridable) ──────────────────────────── */

void ETHMAC_IRQHandler(void);

#ifdef __cplusplus
}
#endif

#endif /* ETHMAC_H */
