/*-----------------------------------------------------------------------------
 * SoCLabs HA1588 PTP Timestamp Unit Driver — Header
 *
 * CMSIS-style bare-metal driver for the HA1588 IP (OpenCores PTP core with
 * SoC Labs patches). Covers the RTC counter and the RX/TX timestamp queues.
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

#ifndef HA1588_H
#define HA1588_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* ── Register offsets ──────────────────────────────────────────────────── */

/* RTC control */
#define HA1588_RTC_CTRL          0x00u
#define HA1588_SCRATCH           0x04u
#define HA1588_RTC_SEC_HI        0x10u
#define HA1588_RTC_SEC_LO        0x14u
#define HA1588_RTC_NS            0x18u
#define HA1588_RTC_NSF           0x1Cu
#define HA1588_RTC_PERIOD_NS     0x20u
#define HA1588_RTC_PERIOD_NSF    0x24u
#define HA1588_RTC_ADJPER_NS     0x28u
#define HA1588_RTC_ADJPER_NSF    0x2Cu
#define HA1588_RTC_ADJLD         0x30u

/* RX timestamp queue */
#define HA1588_RX_TSU_CTRL       0x40u
#define HA1588_RX_TSU_STAT       0x44u
#define HA1588_RX_TSU_DATA0      0x50u
#define HA1588_RX_TSU_DATA1      0x54u
#define HA1588_RX_TSU_DATA2      0x58u
#define HA1588_RX_TSU_DATA3      0x5Cu

/* TX timestamp queue */
#define HA1588_TX_TSU_CTRL       0x60u
#define HA1588_TX_TSU_STAT       0x64u
#define HA1588_TX_TSU_DATA0      0x70u
#define HA1588_TX_TSU_DATA1      0x74u
#define HA1588_TX_TSU_DATA2      0x78u
#define HA1588_TX_TSU_DATA3      0x7Cu

/* ── RTC_CTRL write bits (pulse, self-clearing) ────────────────────────── */

#define HA1588_RTC_CTRL_TIME_RD    (1u << 0)
#define HA1588_RTC_CTRL_ADJ_LD     (1u << 1)
#define HA1588_RTC_CTRL_PERIOD_LD  (1u << 2)
#define HA1588_RTC_CTRL_TIME_LD    (1u << 3)
#define HA1588_RTC_CTRL_RTC_RST    (1u << 4)

/* ── RTC_CTRL read-back bits ───────────────────────────────────────────── */

#define HA1588_RTC_CTRL_TIME_OK      (1u << 0)
#define HA1588_RTC_CTRL_ADJ_LD_DONE  (1u << 1)

/* ── TSU_CTRL write bits (pulse, self-clearing) ────────────────────────── */

#define HA1588_TSU_CTRL_Q_RD   (1u << 0)
#define HA1588_TSU_CTRL_Q_RST  (1u << 1)

/* ── TSU_CTRL read-back bits ───────────────────────────────────────────── */

#define HA1588_TSU_CTRL_QU_OK  (1u << 0)

/* ── TSU_STAT msgid mask position (write bits [31:24]) ─────────────────── */

#define HA1588_TSU_STAT_MSGID_MASK_POS 24u
#define HA1588_TSU_STAT_Q_DEPTH_Msk    0xFFu

/* ── Timestamp struct ──────────────────────────────────────────────────── */

typedef struct {
    uint32_t sec_hi;       /* Seconds upper 16 bits (+ flags in [31:16]) */
    uint32_t sec_lo;       /* Seconds lower 32 bits                     */
    uint32_t nanoseconds;  /* Nanoseconds [29:0]                        */
    uint32_t hash;         /* Frame identifier / hash from TSU DATA3    */
} ha1588_ts_t;

/* ── Driver handle ─────────────────────────────────────────────────────── */

typedef struct {
    volatile uint32_t *regs;  /* Register base pointer */
} ha1588_t;

/* Helper to read/write registers by offset */
#define HA1588_REG(ha, off) ((ha)->regs[(off) >> 2])

/* ── Initialisation ────────────────────────────────────────────────────── */

void ha1588_init(ha1588_t *ha, uint32_t base);

/* ── RTC Control ───────────────────────────────────────────────────────── */

/**
 * Latch the current RTC time into RTC_SEC/NS registers and read it.
 * Blocks until the CDC handshake completes (time_ok flag).
 */
void ha1588_rtc_read_time(ha1588_t *ha, ha1588_ts_t *ts);

/**
 * Atomically load a new time into the RTC counter.
 * Stages sec_hi, sec_lo, ns into the holding registers, then pulses TIME_LD.
 */
void ha1588_rtc_set_time(ha1588_t *ha, uint32_t sec_hi, uint32_t sec_lo,
                          uint32_t ns);

/**
 * Set the base period (nanoseconds per rtc_clk cycle).
 * E.g. for 125 MHz: ns=8, nsf=0. For 50 MHz: ns=20, nsf=0.
 */
void ha1588_rtc_set_period(ha1588_t *ha, uint32_t ns, uint32_t nsf);

/**
 * Apply a frequency adjustment for a given number of clock cycles.
 * The RTC temporarily uses (base_period + adj) for @p cycles cycles,
 * then reverts to the base period.
 */
void ha1588_rtc_set_adj(ha1588_t *ha, uint32_t adj_ns, uint32_t adj_nsf,
                         uint32_t cycles);

/** Reset the RTC counters to zero. */
static inline void ha1588_rtc_reset(ha1588_t *ha)
{
    HA1588_REG(ha, HA1588_RTC_CTRL) = HA1588_RTC_CTRL_RTC_RST;
}

/* ── RX Timestamp Queue ────────────────────────────────────────────────── */

/**
 * Read the front-of-queue RX timestamp, then advance the FIFO.
 * Returns 0 on success, -1 if the queue is empty.
 */
int ha1588_rx_queue_read(ha1588_t *ha, ha1588_ts_t *ts);

/** Reset (flush) the RX timestamp queue. */
void ha1588_rx_queue_reset(ha1588_t *ha);

/**
 * Return the current RX queue depth (entries available) WITHOUT dequeuing.
 * Reads RX_TSU_STAT only; STAT is a status read with no side effects (no Q_RD
 * pulse is issued, so the FIFO head is NOT advanced).
 */
static inline uint32_t ha1588_rx_queue_depth(ha1588_t *ha)
{
    return HA1588_REG(ha, HA1588_RX_TSU_STAT) & HA1588_TSU_STAT_Q_DEPTH_Msk;
}

/**
 * Set the RX PTP message-type capture mask.
 * Each bit enables capture for the corresponding PTP messageType:
 *   bit 0 = Sync (0x0), bit 1 = Delay_Req (0x1), etc.
 */
static inline void ha1588_rx_set_msgid_mask(ha1588_t *ha, uint8_t mask)
{
    HA1588_REG(ha, HA1588_RX_TSU_STAT) =
        (uint32_t)mask << HA1588_TSU_STAT_MSGID_MASK_POS;
}

/* ── TX Timestamp Queue ────────────────────────────────────────────────── */

/**
 * Read the front-of-queue TX timestamp, then advance the FIFO.
 * Returns 0 on success, -1 if the queue is empty.
 */
int ha1588_tx_queue_read(ha1588_t *ha, ha1588_ts_t *ts);

/** Reset (flush) the TX timestamp queue. */
void ha1588_tx_queue_reset(ha1588_t *ha);

/**
 * Return the current TX queue depth (entries available) WITHOUT dequeuing.
 * Reads TX_TSU_STAT only; STAT is a status read with no side effects (no Q_RD
 * pulse is issued, so the FIFO head is NOT advanced).
 */
static inline uint32_t ha1588_tx_queue_depth(ha1588_t *ha)
{
    return HA1588_REG(ha, HA1588_TX_TSU_STAT) & HA1588_TSU_STAT_Q_DEPTH_Msk;
}

/**
 * Set the TX PTP message-type capture mask.
 */
static inline void ha1588_tx_set_msgid_mask(ha1588_t *ha, uint8_t mask)
{
    HA1588_REG(ha, HA1588_TX_TSU_STAT) =
        (uint32_t)mask << HA1588_TSU_STAT_MSGID_MASK_POS;
}

#ifdef __cplusplus
}
#endif

#endif /* HA1588_H */
