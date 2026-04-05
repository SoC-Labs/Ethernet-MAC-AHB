/*-----------------------------------------------------------------------------
 * Auto-generated from SystemRDL — do not edit
 *
 * Source addrmap: ethmac_regs
 * Generator:     scripts/rdl2c.py
 *-----------------------------------------------------------------------------*/

#ifndef ETHMAC_REGS_GENERATED_H
#define ETHMAC_REGS_GENERATED_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* CMSIS-style access qualifiers */
#ifndef __IO
#define __IO volatile
#endif
#ifndef __I
#define __I  volatile const
#endif
#ifndef __O
#define __O  volatile
#endif

/* ========================================================================= */
/* Register Offsets
 * ========================================================================= */

#define ETHMAC_REGS_MODER_OFFSET  0x000U
#define ETHMAC_REGS_INT_SOURCE_OFFSET  0x004U
#define ETHMAC_REGS_INT_MASK_OFFSET  0x008U
#define ETHMAC_REGS_IPGT_OFFSET  0x00CU
#define ETHMAC_REGS_IPGR1_OFFSET  0x010U
#define ETHMAC_REGS_IPGR2_OFFSET  0x014U
#define ETHMAC_REGS_PACKETLEN_OFFSET  0x018U
#define ETHMAC_REGS_COLLCONF_OFFSET  0x01CU
#define ETHMAC_REGS_TX_BD_NUM_OFFSET  0x020U
#define ETHMAC_REGS_CTRLMODER_OFFSET  0x024U
#define ETHMAC_REGS_MIIMODER_OFFSET  0x028U
#define ETHMAC_REGS_MIICOMMAND_OFFSET  0x02CU
#define ETHMAC_REGS_MIIADDRESS_OFFSET  0x030U
#define ETHMAC_REGS_MIITX_DATA_OFFSET  0x034U
#define ETHMAC_REGS_MIIRX_DATA_OFFSET  0x038U
#define ETHMAC_REGS_MIISTATUS_OFFSET  0x03CU
#define ETHMAC_REGS_MAC_ADDR0_OFFSET  0x040U
#define ETHMAC_REGS_MAC_ADDR1_OFFSET  0x044U
#define ETHMAC_REGS_HASH0_OFFSET  0x048U
#define ETHMAC_REGS_HASH1_OFFSET  0x04CU
#define ETHMAC_REGS_TX_CTRL_OFFSET  0x050U
#define ETHMAC_REGS_RX_CTRL_OFFSET  0x054U

/* ───────────────────────────────────────────────────────────────────────── */
/* MODER (0x000) — MAC mode control register.
 * ───────────────────────────────────────────────────────────────────────── */

#define ETHMAC_REGS_MODER_RXEN_Pos    0U
#define ETHMAC_REGS_MODER_RXEN_Msk    (0x1UL)

#define ETHMAC_REGS_MODER_TXEN_Pos    1U
#define ETHMAC_REGS_MODER_TXEN_Msk    (0x2UL)

#define ETHMAC_REGS_MODER_NOPRE_Pos    2U
#define ETHMAC_REGS_MODER_NOPRE_Msk    (0x4UL)

#define ETHMAC_REGS_MODER_BRO_Pos    3U
#define ETHMAC_REGS_MODER_BRO_Msk    (0x8UL)

#define ETHMAC_REGS_MODER_IAM_Pos    4U
#define ETHMAC_REGS_MODER_IAM_Msk    (0x10UL)

#define ETHMAC_REGS_MODER_PRO_Pos    5U
#define ETHMAC_REGS_MODER_PRO_Msk    (0x20UL)

#define ETHMAC_REGS_MODER_IFG_Pos    6U
#define ETHMAC_REGS_MODER_IFG_Msk    (0x40UL)

#define ETHMAC_REGS_MODER_LOOPBK_Pos    7U
#define ETHMAC_REGS_MODER_LOOPBK_Msk    (0x80UL)

#define ETHMAC_REGS_MODER_NOBCKOF_Pos    8U
#define ETHMAC_REGS_MODER_NOBCKOF_Msk    (0x100UL)

#define ETHMAC_REGS_MODER_EXDFREN_Pos    9U
#define ETHMAC_REGS_MODER_EXDFREN_Msk    (0x200UL)

#define ETHMAC_REGS_MODER_FULLD_Pos    10U
#define ETHMAC_REGS_MODER_FULLD_Msk    (0x400UL)

#define ETHMAC_REGS_MODER_DLYCRCEN_Pos    12U
#define ETHMAC_REGS_MODER_DLYCRCEN_Msk    (0x1000UL)

#define ETHMAC_REGS_MODER_CRCEN_Pos    13U
#define ETHMAC_REGS_MODER_CRCEN_Msk    (0x2000UL)
#define ETHMAC_REGS_MODER_CRCEN_Rst    0x1U

#define ETHMAC_REGS_MODER_HUGEN_Pos    14U
#define ETHMAC_REGS_MODER_HUGEN_Msk    (0x4000UL)
#define ETHMAC_REGS_MODER_HUGEN_Rst    0x1U

#define ETHMAC_REGS_MODER_PAD_Pos    15U
#define ETHMAC_REGS_MODER_PAD_Msk    (0x8000UL)
#define ETHMAC_REGS_MODER_PAD_Rst    0x1U

#define ETHMAC_REGS_MODER_RECSMALL_Pos    16U
#define ETHMAC_REGS_MODER_RECSMALL_Msk    (0x10000UL)
#define ETHMAC_REGS_MODER_RECSMALL_Rst    0x1U

/* ───────────────────────────────────────────────────────────────────────── */
/* INT_SOURCE (0x004) — Interrupt source flags. Write 1 to clear individual bits.
 * ───────────────────────────────────────────────────────────────────────── */

#define ETHMAC_REGS_INT_SOURCE_TXB_Pos    0U
#define ETHMAC_REGS_INT_SOURCE_TXB_Msk    (0x1UL)

#define ETHMAC_REGS_INT_SOURCE_TXE_Pos    1U
#define ETHMAC_REGS_INT_SOURCE_TXE_Msk    (0x2UL)

#define ETHMAC_REGS_INT_SOURCE_RXB_Pos    2U
#define ETHMAC_REGS_INT_SOURCE_RXB_Msk    (0x4UL)

#define ETHMAC_REGS_INT_SOURCE_RXE_Pos    3U
#define ETHMAC_REGS_INT_SOURCE_RXE_Msk    (0x8UL)

#define ETHMAC_REGS_INT_SOURCE_BUSY_Pos    4U
#define ETHMAC_REGS_INT_SOURCE_BUSY_Msk    (0x10UL)

#define ETHMAC_REGS_INT_SOURCE_TXC_Pos    5U
#define ETHMAC_REGS_INT_SOURCE_TXC_Msk    (0x20UL)

#define ETHMAC_REGS_INT_SOURCE_RXC_Pos    6U
#define ETHMAC_REGS_INT_SOURCE_RXC_Msk    (0x40UL)

/* ───────────────────────────────────────────────────────────────────────── */
/* INT_MASK (0x008) — Interrupt mask. Set bits to enable corresponding interrupts.
 * ───────────────────────────────────────────────────────────────────────── */

#define ETHMAC_REGS_INT_MASK_TXB_M_Pos    0U
#define ETHMAC_REGS_INT_MASK_TXB_M_Msk    (0x1UL)

#define ETHMAC_REGS_INT_MASK_TXE_M_Pos    1U
#define ETHMAC_REGS_INT_MASK_TXE_M_Msk    (0x2UL)

#define ETHMAC_REGS_INT_MASK_RXB_M_Pos    2U
#define ETHMAC_REGS_INT_MASK_RXB_M_Msk    (0x4UL)

#define ETHMAC_REGS_INT_MASK_RXE_M_Pos    3U
#define ETHMAC_REGS_INT_MASK_RXE_M_Msk    (0x8UL)

#define ETHMAC_REGS_INT_MASK_BUSY_M_Pos    4U
#define ETHMAC_REGS_INT_MASK_BUSY_M_Msk    (0x10UL)

#define ETHMAC_REGS_INT_MASK_TXC_M_Pos    5U
#define ETHMAC_REGS_INT_MASK_TXC_M_Msk    (0x20UL)

#define ETHMAC_REGS_INT_MASK_RXC_M_Pos    6U
#define ETHMAC_REGS_INT_MASK_RXC_M_Msk    (0x40UL)

/* ───────────────────────────────────────────────────────────────────────── */
/* IPGT (0x00C) — Back-to-back inter-packet gap. Default: 0x12 (full-duplex).
 * ───────────────────────────────────────────────────────────────────────── */

#define ETHMAC_REGS_IPGT_GAP_Pos    0U
#define ETHMAC_REGS_IPGT_GAP_Msk    (0x7FUL)
#define ETHMAC_REGS_IPGT_GAP_Wid    7U

/* ───────────────────────────────────────────────────────────────────────── */
/* IPGR1 (0x010) — Non-back-to-back inter-packet gap part 1. Default: 0x0C.
 * ───────────────────────────────────────────────────────────────────────── */

#define ETHMAC_REGS_IPGR1_GAP_Pos    0U
#define ETHMAC_REGS_IPGR1_GAP_Msk    (0x7FUL)
#define ETHMAC_REGS_IPGR1_GAP_Wid    7U

/* ───────────────────────────────────────────────────────────────────────── */
/* IPGR2 (0x014) — Non-back-to-back inter-packet gap part 2. Default: 0x12.
 * ───────────────────────────────────────────────────────────────────────── */

#define ETHMAC_REGS_IPGR2_GAP_Pos    0U
#define ETHMAC_REGS_IPGR2_GAP_Msk    (0x7FUL)
#define ETHMAC_REGS_IPGR2_GAP_Wid    7U

/* ───────────────────────────────────────────────────────────────────────── */
/* PACKETLEN (0x018) — Minimum and maximum packet length. Default: 0x00400600.
 * ───────────────────────────────────────────────────────────────────────── */

#define ETHMAC_REGS_PACKETLEN_MINFL_Pos    0U
#define ETHMAC_REGS_PACKETLEN_MINFL_Msk    (0xFFFFUL)
#define ETHMAC_REGS_PACKETLEN_MINFL_Wid    16U
#define ETHMAC_REGS_PACKETLEN_MINFL_Rst    0x600U

#define ETHMAC_REGS_PACKETLEN_MAXFL_Pos    16U
#define ETHMAC_REGS_PACKETLEN_MAXFL_Msk    (0xFFFF0000UL)
#define ETHMAC_REGS_PACKETLEN_MAXFL_Wid    16U
#define ETHMAC_REGS_PACKETLEN_MAXFL_Rst    0x40U

/* ───────────────────────────────────────────────────────────────────────── */
/* COLLCONF (0x01C) — Collision configuration for half-duplex mode.
 * ───────────────────────────────────────────────────────────────────────── */

#define ETHMAC_REGS_COLLCONF_COLLVALID_Pos    0U
#define ETHMAC_REGS_COLLCONF_COLLVALID_Msk    (0x3FUL)
#define ETHMAC_REGS_COLLCONF_COLLVALID_Wid    6U
#define ETHMAC_REGS_COLLCONF_COLLVALID_Rst    0x3FU

#define ETHMAC_REGS_COLLCONF_MAXRET_Pos    16U
#define ETHMAC_REGS_COLLCONF_MAXRET_Msk    (0xF0000UL)
#define ETHMAC_REGS_COLLCONF_MAXRET_Wid    4U
#define ETHMAC_REGS_COLLCONF_MAXRET_Rst    0xFU

/* ───────────────────────────────────────────────────────────────────────── */
/* TX_BD_NUM (0x020) — Number of TX buffer descriptors. RX count = 0x80 - TX_BD_NUM.
 * ───────────────────────────────────────────────────────────────────────── */

#define ETHMAC_REGS_TX_BD_NUM_TX_BD_NUM_Pos    0U
#define ETHMAC_REGS_TX_BD_NUM_TX_BD_NUM_Msk    (0xFFUL)
#define ETHMAC_REGS_TX_BD_NUM_TX_BD_NUM_Wid    8U
#define ETHMAC_REGS_TX_BD_NUM_TX_BD_NUM_Rst    0x40U

/* ───────────────────────────────────────────────────────────────────────── */
/* CTRLMODER (0x024) — MAC control mode settings.
 * ───────────────────────────────────────────────────────────────────────── */

#define ETHMAC_REGS_CTRLMODER_PASSALL_Pos    0U
#define ETHMAC_REGS_CTRLMODER_PASSALL_Msk    (0x1UL)

#define ETHMAC_REGS_CTRLMODER_RXFLOW_Pos    1U
#define ETHMAC_REGS_CTRLMODER_RXFLOW_Msk    (0x2UL)

#define ETHMAC_REGS_CTRLMODER_TXFLOW_Pos    2U
#define ETHMAC_REGS_CTRLMODER_TXFLOW_Msk    (0x4UL)

/* ───────────────────────────────────────────────────────────────────────── */
/* MIIMODER (0x028) — MII mode configuration.
 * ───────────────────────────────────────────────────────────────────────── */

#define ETHMAC_REGS_MIIMODER_CLKDIV_Pos    0U
#define ETHMAC_REGS_MIIMODER_CLKDIV_Msk    (0xFFUL)
#define ETHMAC_REGS_MIIMODER_CLKDIV_Wid    8U
#define ETHMAC_REGS_MIIMODER_CLKDIV_Rst    0x64U

#define ETHMAC_REGS_MIIMODER_MIINOPRE_Pos    8U
#define ETHMAC_REGS_MIIMODER_MIINOPRE_Msk    (0x100UL)

#define ETHMAC_REGS_MIIMODER_MIIRST_Pos    9U
#define ETHMAC_REGS_MIIMODER_MIIRST_Msk    (0x200UL)

/* ───────────────────────────────────────────────────────────────────────── */
/* MIICOMMAND (0x02C) — MII command register.
 * ───────────────────────────────────────────────────────────────────────── */

#define ETHMAC_REGS_MIICOMMAND_SCANSTAT_Pos    0U
#define ETHMAC_REGS_MIICOMMAND_SCANSTAT_Msk    (0x1UL)

#define ETHMAC_REGS_MIICOMMAND_RSTAT_Pos    1U
#define ETHMAC_REGS_MIICOMMAND_RSTAT_Msk    (0x2UL)

#define ETHMAC_REGS_MIICOMMAND_WCTRLDATA_Pos    2U
#define ETHMAC_REGS_MIICOMMAND_WCTRLDATA_Msk    (0x4UL)

/* ───────────────────────────────────────────────────────────────────────── */
/* MIIADDRESS (0x030) — MII PHY and register address.
 * ───────────────────────────────────────────────────────────────────────── */

#define ETHMAC_REGS_MIIADDRESS_FIAD_Pos    0U
#define ETHMAC_REGS_MIIADDRESS_FIAD_Msk    (0x1FUL)
#define ETHMAC_REGS_MIIADDRESS_FIAD_Wid    5U

#define ETHMAC_REGS_MIIADDRESS_RGAD_Pos    8U
#define ETHMAC_REGS_MIIADDRESS_RGAD_Msk    (0x1F00UL)
#define ETHMAC_REGS_MIIADDRESS_RGAD_Wid    5U

/* ───────────────────────────────────────────────────────────────────────── */
/* MIITX_DATA (0x034) — MII transmit data for PHY register writes.
 * ───────────────────────────────────────────────────────────────────────── */

#define ETHMAC_REGS_MIITX_DATA_CTRLDATA_Pos    0U
#define ETHMAC_REGS_MIITX_DATA_CTRLDATA_Msk    (0xFFFFUL)
#define ETHMAC_REGS_MIITX_DATA_CTRLDATA_Wid    16U

/* ───────────────────────────────────────────────────────────────────────── */
/* MIIRX_DATA (0x038) — MII receive data from PHY register reads (read-only).
 * ───────────────────────────────────────────────────────────────────────── */

#define ETHMAC_REGS_MIIRX_DATA_PRSD_Pos    0U
#define ETHMAC_REGS_MIIRX_DATA_PRSD_Msk    (0xFFFFUL)
#define ETHMAC_REGS_MIIRX_DATA_PRSD_Wid    16U

/* ───────────────────────────────────────────────────────────────────────── */
/* MIISTATUS (0x03C) — MII status (read-only).
 * ───────────────────────────────────────────────────────────────────────── */

#define ETHMAC_REGS_MIISTATUS_LINKFAIL_Pos    0U
#define ETHMAC_REGS_MIISTATUS_LINKFAIL_Msk    (0x1UL)

#define ETHMAC_REGS_MIISTATUS_BUSY_Pos    1U
#define ETHMAC_REGS_MIISTATUS_BUSY_Msk    (0x2UL)

#define ETHMAC_REGS_MIISTATUS_NVALID_Pos    2U
#define ETHMAC_REGS_MIISTATUS_NVALID_Msk    (0x4UL)

/* ───────────────────────────────────────────────────────────────────────── */
/* MAC_ADDR0 (0x040) — MAC address lower 32 bits (bytes 3:0). LSB-first.
 * ───────────────────────────────────────────────────────────────────────── */

#define ETHMAC_REGS_MAC_ADDR0_BYTE0_3_Pos    0U
#define ETHMAC_REGS_MAC_ADDR0_BYTE0_3_Msk    (0xFFFFFFFFUL)
#define ETHMAC_REGS_MAC_ADDR0_BYTE0_3_Wid    32U

/* ───────────────────────────────────────────────────────────────────────── */
/* MAC_ADDR1 (0x044) — MAC address upper 16 bits (bytes 5:4).
 * ───────────────────────────────────────────────────────────────────────── */

#define ETHMAC_REGS_MAC_ADDR1_BYTE4_5_Pos    0U
#define ETHMAC_REGS_MAC_ADDR1_BYTE4_5_Msk    (0xFFFFUL)
#define ETHMAC_REGS_MAC_ADDR1_BYTE4_5_Wid    16U

/* ───────────────────────────────────────────────────────────────────────── */
/* HASH0 (0x048) — Hash filter bits 31:0.
 * ───────────────────────────────────────────────────────────────────────── */

#define ETHMAC_REGS_HASH0_HASH_Pos    0U
#define ETHMAC_REGS_HASH0_HASH_Msk    (0xFFFFFFFFUL)
#define ETHMAC_REGS_HASH0_HASH_Wid    32U

/* ───────────────────────────────────────────────────────────────────────── */
/* HASH1 (0x04C) — Hash filter bits 63:32.
 * ───────────────────────────────────────────────────────────────────────── */

#define ETHMAC_REGS_HASH1_HASH_Pos    0U
#define ETHMAC_REGS_HASH1_HASH_Msk    (0xFFFFFFFFUL)
#define ETHMAC_REGS_HASH1_HASH_Wid    32U

/* ───────────────────────────────────────────────────────────────────────── */
/* TX_CTRL (0x050) — TX flow control (PAUSE frame generation).
 * ───────────────────────────────────────────────────────────────────────── */

#define ETHMAC_REGS_TX_CTRL_PAUSETV_Pos    0U
#define ETHMAC_REGS_TX_CTRL_PAUSETV_Msk    (0xFFFFUL)
#define ETHMAC_REGS_TX_CTRL_PAUSETV_Wid    16U

#define ETHMAC_REGS_TX_CTRL_PAUSERQ_Pos    16U
#define ETHMAC_REGS_TX_CTRL_PAUSERQ_Msk    (0x10000UL)

/* ───────────────────────────────────────────────────────────────────────── */
/* RX_CTRL (0x054) — RX flow control status.
 * ───────────────────────────────────────────────────────────────────────── */

#define ETHMAC_REGS_RX_CTRL_RXCTRL_Pos    0U
#define ETHMAC_REGS_RX_CTRL_RXCTRL_Msk    (0xFFFFUL)
#define ETHMAC_REGS_RX_CTRL_RXCTRL_Wid    16U

/* ========================================================================= */
/* Register Struct
 * ========================================================================= */

typedef struct {
    __IO uint32_t MODER;  /* 0x000 */
    __IO uint32_t INT_SOURCE;  /* 0x004 */
    __IO uint32_t INT_MASK;  /* 0x008 */
    __IO uint32_t IPGT;  /* 0x00C */
    __IO uint32_t IPGR1;  /* 0x010 */
    __IO uint32_t IPGR2;  /* 0x014 */
    __IO uint32_t PACKETLEN;  /* 0x018 */
    __IO uint32_t COLLCONF;  /* 0x01C */
    __IO uint32_t TX_BD_NUM;  /* 0x020 */
    __IO uint32_t CTRLMODER;  /* 0x024 */
    __IO uint32_t MIIMODER;  /* 0x028 */
    __IO uint32_t MIICOMMAND;  /* 0x02C */
    __IO uint32_t MIIADDRESS;  /* 0x030 */
    __IO uint32_t MIITX_DATA;  /* 0x034 */
    __I  uint32_t MIIRX_DATA;  /* 0x038 */
    __I  uint32_t MIISTATUS;  /* 0x03C */
    __IO uint32_t MAC_ADDR0;  /* 0x040 */
    __IO uint32_t MAC_ADDR1;  /* 0x044 */
    __IO uint32_t HASH0;  /* 0x048 */
    __IO uint32_t HASH1;  /* 0x04C */
    __IO uint32_t TX_CTRL;  /* 0x050 */
    __I  uint32_t RX_CTRL;  /* 0x054 */
} ETHMAC_REGS_TypeDef;

#ifdef __cplusplus
}
#endif

#endif /* ETHMAC_REGS_GENERATED_H */
