import cocotb
from cocotb.triggers import RisingEdge, Timer, with_timeout
from test_ethmac_ahb import (
    EthmacAhbTB, HAS_COCOTBEXT_ETH,
    REG_MODER, REG_INT_MASK, REG_TX_BD_NUM,
    REG_MAC_ADDR0, REG_MAC_ADDR1, REG_IPGT, REG_PACKETLEN,
    MODER_TXEN, MODER_PAD, MODER_CRCEN, MODER_FULLD,
    TX_BD_RD, TX_BD_IRQ, TX_BD_WR, TX_BD_PAD, TX_BD_CRC,
    INT_TXB,
)

@cocotb.test()
async def test_tx_simple(dut):
    tb = EthmacAhbTB(dut)
    await tb.reset()
    log = dut._log

    assert HAS_COCOTBEXT_ETH, "Need cocotbext-eth"
    assert tb.mii_phy is not None, "Need MiiPhy"

    await tb.reg_write(REG_MAC_ADDR0, 0x5E4D3C2B)
    await tb.reg_write(REG_MAC_ADDR1, 0x0000001A)
    await tb.reg_write(REG_IPGT, 0x00000015)
    await tb.reg_write(REG_PACKETLEN, (1518 << 16) | 64)
    await tb.reg_write(REG_TX_BD_NUM, 1)

    frame = bytearray(b'\xFF' * 6 + b'\x00\x1A\x2B\x3C\x4D\x5E' + b'\x08\x00' + b'\xAA' * 46)
    tb.dma_write_mem(0x0000, frame)

    tx_flags = TX_BD_RD | TX_BD_IRQ | TX_BD_WR | TX_BD_PAD | TX_BD_CRC
    await tb.setup_tx_bd(0, 0x0000, len(frame), tx_flags)

    moder = 0x0000A000 | MODER_TXEN | MODER_PAD | MODER_CRCEN | MODER_FULLD
    await tb.reg_write(REG_MODER, moder)

    log.info("TX enabled, waiting for MiiPhy recv (up to 500us)...")
    try:
        captured = await with_timeout(tb.mii_phy.tx.recv(), 500, "us")
        log.info("CAPTURED: %d bytes", len(captured.data))
        log.info("Data[:30]: %s", captured.data[:30].hex())
    except Exception as e:
        log.error("recv failed: %s", e)
        # Check if tx.active
        log.info("tx.active=%s, tx.count=%d", tb.mii_phy.tx.active, tb.mii_phy.tx.count())
        # Manually check txen
        for i in range(100):
            await RisingEdge(dut.mtx_clk_pad_i)
            txen = int(dut.mtxen_pad_o.value)
            if txen:
                log.info("txen=1 at mtx_clk edge %d", i)
                break
        else:
            log.warning("txen never asserted on mtx_clk edges")
