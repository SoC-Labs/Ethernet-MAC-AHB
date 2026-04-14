"""
Byte-swap DMA verification for ethmac_ahb.

The DUT here is `tb_ethmac_ahb_swap` — the same testbench structure as the
default-param suite under ../ethmac_ahb/, but with the DUT instantiated as
`ethmac_ahb #(.SWAP_DMA_BYTES(1'b1))`. That should place in-memory frame
bytes in *on-wire order* (byte 0 of the frame at address N+0, byte 1 at
N+1, …), exactly what a little-endian CPU-side stack like PicoTCP
expects.

The default-param tests in ../ethmac_ahb/ use an explicit
`[w[3],w[2],w[1],w[0]]` un-swap helper to compensate for the MAC's BE
Wishbone byte order. Those still apply to SWAP_DMA_BYTES=0. When swap is
enabled, the helper must NOT be used — that's the distinction these
focused tests verify.

Run with:
    make MODULE=test_ethmac_ahb_swap_dma
"""

import cocotb
from cocotb.triggers import ClockCycles, Timer
from cocotb.clock import Clock

import sys, os
# Reuse the TB helpers next door (adds that dir to sys.path).
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "ethmac_ahb"))

from test_ethmac_ahb import (  # noqa: E402
    EthmacAhbTB, HAS_COCOTBEXT_ETH,
    REG_MODER, REG_INT_SOURCE, REG_INT_MASK,
    REG_IPGT, REG_IPGR1, REG_IPGR2, REG_PACKETLEN, REG_TX_BD_NUM,
    REG_MIIMODER, REG_MAC_ADDR0, REG_MAC_ADDR1,
    BD_BASE,
    MODER_RXEN, MODER_TXEN, MODER_PRO, MODER_FULLD, MODER_CRCEN, MODER_PAD,
    RX_BD_E, RX_BD_IRQ, RX_BD_WR,
    INT_RXB,
    HCLK_PERIOD_NS,
)

try:
    from cocotbext.eth import GmiiFrame
    HAS_GMII = True
except ImportError:
    HAS_GMII = False


# ---------------------------------------------------------------------------
# Helper: build a small known frame with a recognisable byte signature
# ---------------------------------------------------------------------------
def build_known_frame():
    """Return a 60-byte bytes() that looks like an ARP request for
    192.168.1.100 from 192.168.1.1. The byte layout is explicit and
    checked in the test."""
    return bytes([
        # dst MAC = ff:ff:ff:ff:ff:ff
        0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
        # src MAC = 02:00:00:00:00:01
        0x02, 0x00, 0x00, 0x00, 0x00, 0x01,
        # EtherType = 0x0806 (ARP)
        0x08, 0x06,
        # ARP: htype=1, ptype=0x0800, hlen=6, plen=4, op=1 (request)
        0x00, 0x01, 0x08, 0x00, 0x06, 0x04, 0x00, 0x01,
        # SHA = 02:00:00:00:00:01
        0x02, 0x00, 0x00, 0x00, 0x00, 0x01,
        # SPA = 192.168.1.1
        0xC0, 0xA8, 0x01, 0x01,
        # THA = 00:00:00:00:00:00
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        # TPA = 192.168.1.100
        0xC0, 0xA8, 0x01, 0x64,
        # Padding to 60 bytes (MAC would also pad, but be explicit)
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    ])


# ---------------------------------------------------------------------------
# Test: inject a known ARP frame on MII RX and verify DMA memory holds
# the frame bytes in on-wire order (no reversal required).
# ---------------------------------------------------------------------------
@cocotb.test()
async def test_swap_rx_in_wire_order(dut):
    if not (HAS_COCOTBEXT_ETH and HAS_GMII):
        raise cocotb.result.TestSuccess("cocotbext-eth not installed; skipping")

    tb = EthmacAhbTB(dut)
    cocotb.start_soon(Clock(dut.hclk, HCLK_PERIOD_NS, unit="ns").start())
    await tb.reset()
    await tb.start_mii_clocks()
    await tb.build_mii()

    # -- Bring the MAC up in the standard mode mask (full-duplex, promiscuous,
    #    PAD+CRC, TX+RX enable). Same init sequence as ../ethmac_ahb/test_*.py.
    await tb.reg_write(REG_MODER,     0)
    await tb.reg_write(REG_IPGT,      0x00000015)
    await tb.reg_write(REG_IPGR1,     0x0000000C)
    await tb.reg_write(REG_IPGR2,     0x00000012)
    await tb.reg_write(REG_PACKETLEN, 0x00400600)
    await tb.reg_write(REG_TX_BD_NUM, 0x00000004)
    await tb.reg_write(REG_MIIMODER,  0x00000064)
    await tb.reg_write(REG_MAC_ADDR0, 0x00000001)  # 02:00:00:00:00:01
    await tb.reg_write(REG_MAC_ADDR1, 0x00000200)

    # -- Arm a single RX BD (BD4) with WR set so the MAC has a landing pad.
    rx_buf_addr = 0x2000
    rx_bd_status = RX_BD_E | RX_BD_IRQ | RX_BD_WR
    await tb.reg_write(BD_BASE + 4 * 8,     rx_bd_status)
    await tb.reg_write(BD_BASE + 4 * 8 + 4, rx_buf_addr)

    # -- Clear INT_SRC, set mask, enable MAC.
    await tb.reg_write(REG_INT_SOURCE, 0xFFFFFFFF)
    await tb.reg_write(REG_INT_MASK,   INT_RXB)
    moder = (MODER_TXEN | MODER_RXEN | MODER_PAD |
             MODER_CRCEN | MODER_FULLD | MODER_PRO)
    await tb.reg_write(REG_MODER, moder)
    await ClockCycles(dut.hclk, 50)

    # -- Inject the frame on MII RX.
    frame_bytes = build_known_frame()
    await tb.mii_rx_source.send(GmiiFrame.from_payload(frame_bytes))
    await ClockCycles(dut.hclk, 20000)

    # -- Read DMA memory raw.
    got = bytes(tb.dma_read_mem(rx_buf_addr, len(frame_bytes)))

    # With SWAP_DMA_BYTES=1 the in-memory bytes must match wire order.
    assert got == frame_bytes, (
        "With SWAP_DMA_BYTES=1, in-memory RX bytes should match on-wire "
        "order, but they differ:\n"
        f"  expected (wire): {frame_bytes.hex(' ')}\n"
        f"  got (memory):    {got.hex(' ')}\n"
        "If this fails with every 4-byte group reversed, the parameter "
        "override in tb_ethmac_ahb_swap.v didn't take effect."
    )

    # Spot-check the critical fields that PicoTCP cares about.
    assert got[12] == 0x08 and got[13] == 0x06, (
        f"EtherType bytes at offset 12..13 should read as 08 06 (ARP); got "
        f"{got[12]:02x} {got[13]:02x}"
    )
    assert got[20] == 0x00 and got[21] == 0x01, (
        f"ARP opcode at offset 20..21 should be 00 01 (request); got "
        f"{got[20]:02x} {got[21]:02x}"
    )
    assert got[38:42] == bytes([0xC0, 0xA8, 0x01, 0x64]), (
        f"ARP target-IP at offset 38..41 should be c0 a8 01 64 "
        f"(192.168.1.100); got {got[38:42].hex(' ')}"
    )
