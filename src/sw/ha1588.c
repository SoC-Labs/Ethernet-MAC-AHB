/*-----------------------------------------------------------------------------
 * SoCLabs HA1588 PTP Timestamp Unit Driver — Implementation
 *
 * Bare-metal driver for the HA1588 IP. Targets ARM Cortex-M0.
 *
 * A joint work commissioned on behalf of SoC Labs, under Arm Academic
 * Access license.
 *
 * Contributors
 *   David Mapstone (d.a.mapstone@soton.ac.uk)
 *
 * Copyright 2026, SoC Labs (www.soclabs.org)
 *---------------------------------------------------------------------------*/

#include "ha1588.h"

/* ── Initialisation ────────────────────────────────────────────────────── */

void ha1588_init(ha1588_t *ha, uint32_t base)
{
    ha->regs = (volatile uint32_t *)(uintptr_t)base;
}

/* ── RTC Control ───────────────────────────────────────────────────────── */

/* RTC_CTRL pulse bits are edge-detected in the rtc_clk domain (see reg.v).
 * The bit must toggle 0→1→0 for each pulse. Write the bit set, then clear it. */
static void rtc_ctrl_pulse(ha1588_t *ha, uint32_t bit)
{
    HA1588_REG(ha, HA1588_RTC_CTRL) = bit;
    HA1588_REG(ha, HA1588_RTC_CTRL) = 0;
}

void ha1588_rtc_read_time(ha1588_t *ha, ha1588_ts_t *ts)
{
    rtc_ctrl_pulse(ha, HA1588_RTC_CTRL_TIME_RD);

    /* Wait for time_ok flag (bit 0 of RTC_CTRL readback) — BOUNDED so a dead
     * rtc_clk can't hang the servo; on timeout we read whatever is latched. */
    {
        uint32_t w = 1000000u;
        while (!(HA1588_REG(ha, HA1588_RTC_CTRL) & HA1588_RTC_CTRL_TIME_OK)) {
            if (--w == 0u)
                break;
        }
    }

    ts->sec_hi      = HA1588_REG(ha, HA1588_RTC_SEC_HI);
    ts->sec_lo      = HA1588_REG(ha, HA1588_RTC_SEC_LO);
    ts->nanoseconds = HA1588_REG(ha, HA1588_RTC_NS);
    ts->hash        = 0;
}

void ha1588_rtc_set_time(ha1588_t *ha, uint32_t sec_hi, uint32_t sec_lo,
                          uint32_t ns)
{
    HA1588_REG(ha, HA1588_RTC_SEC_HI) = sec_hi;
    HA1588_REG(ha, HA1588_RTC_SEC_LO) = sec_lo;
    HA1588_REG(ha, HA1588_RTC_NS)     = ns;
    HA1588_REG(ha, HA1588_RTC_NSF)    = 0;
    rtc_ctrl_pulse(ha, HA1588_RTC_CTRL_TIME_LD);
}

void ha1588_rtc_set_period(ha1588_t *ha, uint32_t ns, uint32_t nsf)
{
    HA1588_REG(ha, HA1588_RTC_PERIOD_NS)  = ns;
    HA1588_REG(ha, HA1588_RTC_PERIOD_NSF) = nsf;
    rtc_ctrl_pulse(ha, HA1588_RTC_CTRL_PERIOD_LD);
}

void ha1588_rtc_set_adj(ha1588_t *ha, uint32_t adj_ns, uint32_t adj_nsf,
                         uint32_t cycles)
{
    HA1588_REG(ha, HA1588_RTC_ADJPER_NS)  = adj_ns;
    HA1588_REG(ha, HA1588_RTC_ADJPER_NSF) = adj_nsf;
    HA1588_REG(ha, HA1588_RTC_ADJLD)      = cycles;
    rtc_ctrl_pulse(ha, HA1588_RTC_CTRL_ADJ_LD);
}

/* ── Queue read helper ─────────────────────────────────────────────────── */

static int tsu_queue_read(ha1588_t *ha, uint32_t ctrl_off, uint32_t stat_off,
                           uint32_t data0_off, ha1588_ts_t *ts)
{
    /* Check queue depth — if 0 there is nothing to read. */
    if ((HA1588_REG(ha, stat_off) & HA1588_TSU_STAT_Q_DEPTH_Msk) == 0)
        return -1;

    /* Read front-of-queue data (DATA registers present the current head). */
    ts->sec_hi      = HA1588_REG(ha, data0_off);
    ts->sec_lo      = HA1588_REG(ha, data0_off + 4u);
    ts->nanoseconds = HA1588_REG(ha, data0_off + 8u);
    ts->hash        = HA1588_REG(ha, data0_off + 12u);

    /* Advance the FIFO to the next entry. */
    HA1588_REG(ha, ctrl_off) = HA1588_TSU_CTRL_Q_RD;

    /* Wait for the queue read handshake to complete — BOUNDED so a wedged TSU
     * or dead rtc_clk can't hang the caller (the data was already read above;
     * on timeout we return -1 and the caller treats the timestamp as missing). */
    {
        uint32_t w = 1000000u;
        while (!(HA1588_REG(ha, ctrl_off) & HA1588_TSU_CTRL_QU_OK)) {
            if (--w == 0u)
                return -1;
        }
    }

    return 0;
}

/* ── RX Timestamp Queue ────────────────────────────────────────────────── */

int ha1588_rx_queue_read(ha1588_t *ha, ha1588_ts_t *ts)
{
    return tsu_queue_read(ha, HA1588_RX_TSU_CTRL, HA1588_RX_TSU_STAT,
                          HA1588_RX_TSU_DATA0, ts);
}

void ha1588_rx_queue_reset(ha1588_t *ha)
{
    HA1588_REG(ha, HA1588_RX_TSU_CTRL) = HA1588_TSU_CTRL_Q_RST;
}

/* ── TX Timestamp Queue ────────────────────────────────────────────────── */

int ha1588_tx_queue_read(ha1588_t *ha, ha1588_ts_t *ts)
{
    return tsu_queue_read(ha, HA1588_TX_TSU_CTRL, HA1588_TX_TSU_STAT,
                          HA1588_TX_TSU_DATA0, ts);
}

void ha1588_tx_queue_reset(ha1588_t *ha)
{
    HA1588_REG(ha, HA1588_TX_TSU_CTRL) = HA1588_TSU_CTRL_Q_RST;
}
