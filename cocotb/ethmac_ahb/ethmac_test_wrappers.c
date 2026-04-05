/*-----------------------------------------------------------------------------
 * Ethmac Test Wrappers — Export Inline Functions for ctypes
 *
 * Build: gcc -shared -fPIC -DHAL_TEST_MODE -O0 -include hal_io.h \
 *        -I../../src/sw ethmac_test_wrappers.c ../../src/sw/ethmac.c -o libethmac_driver.so
 *---------------------------------------------------------------------------*/

#include "ethmac.h"
#include <stddef.h>

/* ── Struct Layout Assertions ───────────────────────────────────────────── */

_Static_assert(sizeof(ETHMAC_REGS_TypeDef) == 0x058,
               "ETHMAC_REGS_TypeDef size mismatch");
_Static_assert(offsetof(ETHMAC_REGS_TypeDef, MODER) == 0x000,
               "MODER offset mismatch");
_Static_assert(offsetof(ETHMAC_REGS_TypeDef, INT_SOURCE) == 0x004,
               "INT_SOURCE offset mismatch");
_Static_assert(offsetof(ETHMAC_REGS_TypeDef, MIIMODER) == 0x028,
               "MIIMODER offset mismatch");
_Static_assert(offsetof(ETHMAC_REGS_TypeDef, MIISTATUS) == 0x03C,
               "MIISTATUS offset mismatch");
_Static_assert(offsetof(ETHMAC_REGS_TypeDef, MAC_ADDR0) == 0x040,
               "MAC_ADDR0 offset mismatch");
_Static_assert(offsetof(ETHMAC_REGS_TypeDef, RX_CTRL) == 0x054,
               "RX_CTRL offset mismatch");

/* ── 64-bit safe init wrapper ───────────────────────────────────────────── */

void ethmac_init_host(ethmac_t *eth, void *base_ptr, uint32_t tx_bd_num)
{
    eth->regs     = (ETHMAC_REGS_TypeDef *)base_ptr;
    eth->bd       = (uint32_t *)((uint8_t *)base_ptr + ETHMAC_BD_BASE);
    eth->tx_bd_num = tx_bd_num;
    eth->regs->TX_BD_NUM = tx_bd_num & 0xFFU;
}

/* ── Exported Wrappers for static inline Functions ──────────────────────── */

void ethmac_enable_wrap(ethmac_t *eth)
{
    ethmac_enable(eth);
}

void ethmac_disable_wrap(ethmac_t *eth)
{
    ethmac_disable(eth);
}

void ethmac_set_full_duplex_wrap(ethmac_t *eth)
{
    ethmac_set_full_duplex(eth);
}

void ethmac_set_half_duplex_wrap(ethmac_t *eth)
{
    ethmac_set_half_duplex(eth);
}

void ethmac_set_promiscuous_wrap(ethmac_t *eth, uint32_t en)
{
    ethmac_set_promiscuous(eth, en);
}

void ethmac_set_loopback_wrap(ethmac_t *eth, uint32_t en)
{
    ethmac_set_loopback(eth, en);
}

uint32_t ethmac_get_int_source_wrap(ethmac_t *eth)
{
    return ethmac_get_int_source(eth);
}

void ethmac_set_int_mask_wrap(ethmac_t *eth, uint32_t mask)
{
    ethmac_set_int_mask(eth, mask);
}

void ethmac_mii_set_clkdiv_wrap(ethmac_t *eth, uint32_t clkdiv)
{
    ethmac_mii_set_clkdiv(eth, clkdiv);
}

void ethmac_tx_bd_ready_wrap(ethmac_t *eth, uint32_t idx)
{
    ethmac_tx_bd_ready(eth, idx);
}

uint32_t ethmac_tx_bd_done_wrap(ethmac_t *eth, uint32_t idx)
{
    return ethmac_tx_bd_done(eth, idx);
}

void ethmac_rx_bd_empty_wrap(ethmac_t *eth, uint32_t idx)
{
    ethmac_rx_bd_empty(eth, idx);
}

uint32_t ethmac_rx_bd_received_wrap(ethmac_t *eth, uint32_t idx)
{
    return ethmac_rx_bd_received(eth, idx);
}

uint32_t ethmac_rx_bd_length_wrap(ethmac_t *eth, uint32_t idx)
{
    return ethmac_rx_bd_length(eth, idx);
}
