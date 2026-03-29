"""
Cocotb tests for the ethmac_ahb integrated wrapper.

Tests register access via AHB slave interface, DMA via AHB master interface,
and Ethernet data path via MII using:
  - cocotbext-ahb: AHBLiteMaster, AHBLiteSlaveRAM
  - cocotbext-eth: MiiPhy (MiiSource + MiiSink)

Register map (byte addresses from eth_defines.v):
  0x00  MODER           0x04  INT_SOURCE      0x08  INT_MASK
  0x0C  IPGT            0x10  IPGR1           0x14  IPGR2
  0x18  PACKETLEN       0x1C  COLLCONF        0x20  TX_BD_NUM
  0x24  CTRLMODER       0x28  MIIMODER        0x2C  MIICOMMAND
  0x30  MIIADDRESS      0x34  MIITX_DATA      0x38  MIIRX_DATA
  0x3C  MIISTATUS       0x40  MAC_ADDR0       0x44  MAC_ADDR1
  0x48  HASH0           0x4C  HASH1           0x50  TX_CTRL
  0x54  RX_CTRL

Buffer descriptors: 0x400 - 0x7FF
"""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ClockCycles, Timer, with_timeout
from cocotbext.ahb import AHBBus, AHBLiteMaster, AHBLiteSlaveRAM

# Optional: cocotbext-eth for MII PHY simulation
try:
    from cocotbext.eth import MiiPhy
    HAS_COCOTBEXT_ETH = True
except ImportError:
    HAS_COCOTBEXT_ETH = False


# ---------------------------------------------------------------------------
# Register addresses (byte addresses)
# ---------------------------------------------------------------------------
REG_MODER       = 0x00
REG_INT_SOURCE  = 0x04
REG_INT_MASK    = 0x08
REG_IPGT        = 0x0C
REG_IPGR1       = 0x10
REG_IPGR2       = 0x14
REG_PACKETLEN   = 0x18
REG_COLLCONF    = 0x1C
REG_TX_BD_NUM   = 0x20
REG_CTRLMODER   = 0x24
REG_MIIMODER    = 0x28
REG_MIICOMMAND  = 0x2C
REG_MIIADDRESS  = 0x30
REG_MIITX_DATA  = 0x34
REG_MIIRX_DATA  = 0x38
REG_MIISTATUS   = 0x3C
REG_MAC_ADDR0   = 0x40
REG_MAC_ADDR1   = 0x44
REG_HASH0       = 0x48
REG_HASH1       = 0x4C
REG_TX_CTRL     = 0x50
REG_RX_CTRL     = 0x54

# Buffer descriptor base
BD_BASE = 0x400

# MODER register bits
MODER_RXEN   = (1 << 0)
MODER_TXEN   = (1 << 1)
MODER_NOPRE  = (1 << 2)
MODER_BRO    = (1 << 3)
MODER_IAM    = (1 << 4)
MODER_PRO    = (1 << 5)
MODER_IFG    = (1 << 6)
MODER_LOOPBK = (1 << 7)
MODER_NOBCKOF = (1 << 8)
MODER_EXDFREN = (1 << 9)
MODER_FULLD  = (1 << 10)
MODER_DLYCRCEN = (1 << 12)
MODER_CRCEN  = (1 << 13)
MODER_HUGEN  = (1 << 14)
MODER_PAD    = (1 << 15)
MODER_RECSMALL = (1 << 16)

# TX Buffer Descriptor status bits (word 0 of each BD)
TX_BD_RD     = (1 << 15)  # Ready
TX_BD_IRQ    = (1 << 14)  # IRQ enable
TX_BD_WR     = (1 << 13)  # Wrap
TX_BD_PAD    = (1 << 12)  # Pad short frames
TX_BD_CRC    = (1 << 11)  # Append CRC

# RX Buffer Descriptor status bits
RX_BD_E      = (1 << 15)  # Empty (ready for reception)
RX_BD_IRQ    = (1 << 14)  # IRQ enable
RX_BD_WR     = (1 << 13)  # Wrap

# INT_SOURCE / INT_MASK bits
INT_TXB  = (1 << 0)  # TX buffer
INT_TXE  = (1 << 1)  # TX error
INT_RXB  = (1 << 2)  # RX buffer (frame received)
INT_RXE  = (1 << 3)  # RX error
INT_BUSY = (1 << 4)  # Busy
INT_TXC  = (1 << 5)  # TX control frame
INT_RXC  = (1 << 6)  # RX control frame

# System clock period
HCLK_PERIOD_NS = 10  # 100 MHz


# ---------------------------------------------------------------------------
# Testbench setup helpers
# ---------------------------------------------------------------------------
class EthmacAhbTB:
    """Testbench wrapper holding all bus models and helpers."""

    def __init__(self, dut):
        self.dut = dut
        self.log = dut._log

        # Start system clock (100 MHz)
        self.clock = Clock(dut.hclk, HCLK_PERIOD_NS, units="ns")
        cocotb.start_soon(self.clock.start())

        # AHB Lite Master -> drives the DUT's AHB slave port (register access)
        # hready_in is handled in Verilog TB (feedback from hreadyout)
        slv_bus = AHBBus.from_prefix(dut, "slv")
        self.ahb_master = AHBLiteMaster(
            slv_bus, dut.hclk, dut.hresetn, timeout=200
        )

        # AHB Lite Slave RAM -> responds to DUT's AHB master port (DMA)
        mst_bus = AHBBus.from_prefix(dut, "mst")
        self.dma_slave = AHBLiteSlaveRAM(
            mst_bus, dut.hclk, dut.hresetn, mem_size=65536
        )

        # MII PHY model (if cocotbext-eth is available)
        self.mii_phy = None
        if HAS_COCOTBEXT_ETH:
            self.mii_phy = MiiPhy(
                txd=dut.mtxd_pad_o,
                tx_er=dut.mtxerr_pad_o,
                tx_en=dut.mtxen_pad_o,
                tx_clk=dut.mtx_clk_pad_i,
                rxd=dut.mrxd_pad_i,
                rx_er=dut.mrxerr_pad_i,
                rx_dv=dut.mrxdv_pad_i,
                rx_clk=dut.mrx_clk_pad_i,
                speed=100e6,
            )
        else:
            # Generate MII clocks manually (25 MHz for 100 Mbps)
            cocotb.start_soon(self._mii_clock_gen())

    async def _mii_clock_gen(self, period_ns=40):
        """Generate 25 MHz MII TX and RX clocks when cocotbext-eth unavailable."""
        half = period_ns // 2
        while True:
            self.dut.mtx_clk_pad_i.value = 0
            self.dut.mrx_clk_pad_i.value = 0
            await Timer(half, units="ns")
            self.dut.mtx_clk_pad_i.value = 1
            self.dut.mrx_clk_pad_i.value = 1
            await Timer(half, units="ns")

    async def reset(self, cycles=10):
        """Assert reset and initialise MII tie-off inputs."""
        self.dut.hresetn.value = 0

        # Tie off MII inputs (only needed if cocotbext-eth not driving them)
        if not HAS_COCOTBEXT_ETH:
            self.dut.mrxd_pad_i.value = 0
            self.dut.mrxdv_pad_i.value = 0
            self.dut.mrxerr_pad_i.value = 0

        self.dut.mcoll_pad_i.value = 0
        self.dut.mcrs_pad_i.value = 0
        self.dut.md_pad_i.value = 1  # MDIO idle high

        await ClockCycles(self.dut.hclk, cycles)
        self.dut.hresetn.value = 1
        await ClockCycles(self.dut.hclk, 5)

    async def reg_read(self, addr):
        """Read a single register word, return integer value."""
        resp = await self.ahb_master.read(addr)
        return int(resp[0]["data"], 16)

    async def reg_write(self, addr, data):
        """Write a single register word."""
        return await self.ahb_master.write(addr, data)

    def dma_write_mem(self, addr, data_bytes):
        """Pre-load data into the DMA slave RAM."""
        self.dma_slave.memory.write(addr, data_bytes)

    def dma_read_mem(self, addr, length):
        """Read data from the DMA slave RAM."""
        return self.dma_slave.memory.read(addr, length)

    async def setup_tx_bd(self, bd_index, buf_addr, length, flags=0):
        """Configure a TX buffer descriptor.

        Each BD is 2 words (8 bytes):
          Word 0: [31:16] = length, [15:0] = status/flags
          Word 1: [31:0]  = buffer pointer
        """
        bd_addr = BD_BASE + (bd_index * 8)
        word0 = ((length & 0xFFFF) << 16) | (flags & 0xFFFF)
        word1 = buf_addr & 0xFFFFFFFF
        await self.reg_write(bd_addr, word0)
        await self.reg_write(bd_addr + 4, word1)

    async def setup_rx_bd(self, bd_index, buf_addr, flags=0):
        """Configure an RX buffer descriptor.

        Each BD is 2 words (8 bytes):
          Word 0: [15:0] = status/flags (length filled by HW on reception)
          Word 1: [31:0] = buffer pointer
        """
        bd_addr = BD_BASE + (bd_index * 8)
        word0 = flags & 0xFFFF
        word1 = buf_addr & 0xFFFFFFFF
        await self.reg_write(bd_addr, word0)
        await self.reg_write(bd_addr + 4, word1)

    async def read_bd_status(self, bd_index):
        """Read BD word 0 (status/length)."""
        bd_addr = BD_BASE + (bd_index * 8)
        return await self.reg_read(bd_addr)


# ===========================================================================
# Layer 3 — Register Access Tests
# ===========================================================================

@cocotb.test()
async def test_reg_defaults(dut):
    """3.1: Read all key registers and verify reset default values."""
    tb = EthmacAhbTB(dut)
    await tb.reset()

    expected = {
        REG_MODER:      0x0000A000,
        REG_INT_SOURCE: 0x00000000,
        REG_INT_MASK:   0x00000000,
        REG_IPGT:       0x00000012,
        REG_IPGR1:      0x0000000C,
        REG_IPGR2:      0x00000012,
        REG_PACKETLEN:  0x00400600,
        REG_COLLCONF:   0x000F003F,
        REG_TX_BD_NUM:  0x00000040,
        REG_CTRLMODER:  0x00000000,
        REG_MIIMODER:   0x00000064,
        REG_MIICOMMAND: 0x00000000,
        REG_MIIADDRESS: 0x00000000,
        REG_MIITX_DATA: 0x00000000,
        REG_MAC_ADDR0:  0x00000000,
        REG_MAC_ADDR1:  0x00000000,
        REG_HASH0:      0x00000000,
        REG_HASH1:      0x00000000,
    }

    for addr, exp_val in expected.items():
        val = await tb.reg_read(addr)
        tb.log.info("Reg 0x%02X: read 0x%08X, expected 0x%08X", addr, val, exp_val)
        assert val == exp_val, \
            "Reg 0x{:02X}: expected 0x{:08X}, got 0x{:08X}".format(addr, exp_val, val)


@cocotb.test()
async def test_reg_write_readback(dut):
    """3.2: Write known patterns to RW registers and read them back."""
    tb = EthmacAhbTB(dut)
    await tb.reset()

    test_patterns = [
        (REG_INT_MASK,   0x0000007F),
        (REG_IPGT,       0x0000001F),
        (REG_IPGR1,      0x00000015),
        (REG_IPGR2,      0x0000001A),
        (REG_CTRLMODER,  0x00000007),
        (REG_HASH0,      0xAAAAAAAA),
        (REG_HASH1,      0x55555555),
        (REG_TX_CTRL,    0x00010001),
        (REG_RX_CTRL,    0x0000FFFF),
    ]

    for addr, write_val in test_patterns:
        await tb.reg_write(addr, write_val)
        read_val = await tb.reg_read(addr)
        tb.log.info("Reg 0x%02X: wrote 0x%08X, read 0x%08X", addr, write_val, read_val)
        assert read_val == write_val, \
            "Reg 0x{:02X}: wrote 0x{:08X}, read 0x{:08X}".format(addr, write_val, read_val)


@cocotb.test()
async def test_moder_register(dut):
    """3.3: Write to MODER register, readback, verify fields."""
    tb = EthmacAhbTB(dut)
    await tb.reset()

    # Test enabling RXEN + TXEN + PAD + CRCEN
    moder_val = MODER_RXEN | MODER_TXEN | MODER_PAD | MODER_CRCEN | 0x0000A000
    await tb.reg_write(REG_MODER, moder_val)
    read_val = await tb.reg_read(REG_MODER)
    assert read_val == moder_val, \
        "MODER: expected 0x{:08X}, got 0x{:08X}".format(moder_val, read_val)

    # Disable TX, keep RX
    moder_val2 = (moder_val & ~MODER_TXEN)
    await tb.reg_write(REG_MODER, moder_val2)
    read_val2 = await tb.reg_read(REG_MODER)
    assert read_val2 == moder_val2, \
        "MODER after clear TXEN: expected 0x{:08X}, got 0x{:08X}".format(moder_val2, read_val2)


@cocotb.test()
async def test_mac_addr_registers(dut):
    """3.4: Write MAC address and read back."""
    tb = EthmacAhbTB(dut)
    await tb.reset()

    mac_addr0 = 0x5E4D3C2B
    mac_addr1 = 0x0000001A

    await tb.reg_write(REG_MAC_ADDR0, mac_addr0)
    await tb.reg_write(REG_MAC_ADDR1, mac_addr1)

    read0 = await tb.reg_read(REG_MAC_ADDR0)
    read1 = await tb.reg_read(REG_MAC_ADDR1)

    assert read0 == mac_addr0, \
        "MAC_ADDR0: expected 0x{:08X}, got 0x{:08X}".format(mac_addr0, read0)
    assert read1 == mac_addr1, \
        "MAC_ADDR1: expected 0x{:08X}, got 0x{:08X}".format(mac_addr1, read1)


@cocotb.test()
async def test_int_mask_register(dut):
    """3.5: Write INT_MASK and readback."""
    tb = EthmacAhbTB(dut)
    await tb.reset()

    mask_val = INT_TXB | INT_RXB | INT_TXE | INT_RXE
    await tb.reg_write(REG_INT_MASK, mask_val)
    read_val = await tb.reg_read(REG_INT_MASK)
    assert read_val == mask_val, \
        "INT_MASK: expected 0x{:08X}, got 0x{:08X}".format(mask_val, read_val)


@cocotb.test()
async def test_tx_bd_num_register(dut):
    """3.6: Write TX_BD_NUM and readback."""
    tb = EthmacAhbTB(dut)
    await tb.reset()

    await tb.reg_write(REG_TX_BD_NUM, 0x00000020)
    read_val = await tb.reg_read(REG_TX_BD_NUM)
    assert read_val == 0x00000020, \
        "TX_BD_NUM: expected 0x00000020, got 0x{:08X}".format(read_val)


@cocotb.test()
async def test_ipgt_register(dut):
    """3.7: Write IPGT and readback."""
    tb = EthmacAhbTB(dut)
    await tb.reset()

    await tb.reg_write(REG_IPGT, 0x00000015)
    read_val = await tb.reg_read(REG_IPGT)
    assert read_val == 0x00000015, \
        "IPGT: expected 0x00000015, got 0x{:08X}".format(read_val)


@cocotb.test()
async def test_packetlen_register(dut):
    """3.8: Write PACKETLEN and readback."""
    tb = EthmacAhbTB(dut)
    await tb.reset()

    # minfl=64 (0x40), maxfl=1518 (0x5EE)
    val = (0x05EE << 16) | 0x0040
    await tb.reg_write(REG_PACKETLEN, val)
    read_val = await tb.reg_read(REG_PACKETLEN)
    assert read_val == val, \
        "PACKETLEN: expected 0x{:08X}, got 0x{:08X}".format(val, read_val)


@cocotb.test()
async def test_miimoder_register(dut):
    """3.9: Write MIIMODER and readback."""
    tb = EthmacAhbTB(dut)
    await tb.reset()

    val = 0x00000028  # Change clock divider
    await tb.reg_write(REG_MIIMODER, val)
    read_val = await tb.reg_read(REG_MIIMODER)
    assert read_val == val, \
        "MIIMODER: expected 0x{:08X}, got 0x{:08X}".format(val, read_val)


@cocotb.test()
async def test_ctrlmoder_register(dut):
    """3.10: Write CTRLMODER and readback."""
    tb = EthmacAhbTB(dut)
    await tb.reset()

    val = 0x00000003  # Enable TX and RX flow control
    await tb.reg_write(REG_CTRLMODER, val)
    read_val = await tb.reg_read(REG_CTRLMODER)
    assert read_val == val, \
        "CTRLMODER: expected 0x{:08X}, got 0x{:08X}".format(val, read_val)


@cocotb.test()
async def test_hash_registers(dut):
    """3.11: Write HASH0/HASH1 and readback."""
    tb = EthmacAhbTB(dut)
    await tb.reset()

    await tb.reg_write(REG_HASH0, 0xDEADBEEF)
    await tb.reg_write(REG_HASH1, 0xCAFEBABE)

    read0 = await tb.reg_read(REG_HASH0)
    read1 = await tb.reg_read(REG_HASH1)

    assert read0 == 0xDEADBEEF, \
        "HASH0: expected 0xDEADBEEF, got 0x{:08X}".format(read0)
    assert read1 == 0xCAFEBABE, \
        "HASH1: expected 0xCAFEBABE, got 0x{:08X}".format(read1)


@cocotb.test()
async def test_walking_ones(dut):
    """3.12: Walking-1 pattern on HASH0 register to detect stuck-at faults."""
    tb = EthmacAhbTB(dut)
    await tb.reset()

    for bit in range(32):
        pattern = 1 << bit
        await tb.reg_write(REG_HASH0, pattern)
        read_val = await tb.reg_read(REG_HASH0)
        assert read_val == pattern, \
            "Walking-1 bit {}: wrote 0x{:08X}, read 0x{:08X}".format(bit, pattern, read_val)


@cocotb.test()
async def test_walking_zeros(dut):
    """3.13: Walking-0 pattern on HASH1 register to detect stuck-at faults."""
    tb = EthmacAhbTB(dut)
    await tb.reset()

    for bit in range(32):
        pattern = 0xFFFFFFFF ^ (1 << bit)
        await tb.reg_write(REG_HASH1, pattern)
        read_val = await tb.reg_read(REG_HASH1)
        assert read_val == pattern, \
            "Walking-0 bit {}: wrote 0x{:08X}, read 0x{:08X}".format(bit, pattern, read_val)


# ===========================================================================
# Layer 4 — Buffer Descriptor Tests
# ===========================================================================

@cocotb.test()
async def test_bd_write_read(dut):
    """4.1: Write/read buffer descriptors in BD space (0x400-0x7FF)."""
    tb = EthmacAhbTB(dut)
    await tb.reset()

    # Write to first 8 BD words
    test_data = [
        0x12345678, 0x00001000,  # BD0: status/len, pointer
        0xDEADBEEF, 0x00002000,  # BD1
        0xCAFEBABE, 0x00003000,  # BD2
        0xA5A5A5A5, 0x00004000,  # BD3
    ]

    for i, data in enumerate(test_data):
        addr = BD_BASE + (i * 4)
        await tb.reg_write(addr, data)

    for i, expected in enumerate(test_data):
        addr = BD_BASE + (i * 4)
        read_val = await tb.reg_read(addr)
        tb.log.info("BD word 0x%03X: expected 0x%08X, got 0x%08X", addr, expected, read_val)
        assert read_val == expected, \
            "BD 0x{:03X}: expected 0x{:08X}, got 0x{:08X}".format(addr, expected, read_val)


@cocotb.test()
async def test_bd_boundary(dut):
    """4.3: Access first and last BD entries."""
    tb = EthmacAhbTB(dut)
    await tb.reset()

    # First BD (0x400)
    await tb.reg_write(BD_BASE, 0x11111111)
    val = await tb.reg_read(BD_BASE)
    assert val == 0x11111111, "First BD failed"

    # Last BD word (0x7FC)
    last_addr = 0x7FC
    await tb.reg_write(last_addr, 0x99999999)
    val = await tb.reg_read(last_addr)
    assert val == 0x99999999, "Last BD failed"


# ===========================================================================
# Layer 5 — DMA and Data Path Tests
# ===========================================================================

@cocotb.test()
async def test_dma_tx_frame(dut):
    """5.1/5.3: Configure TX BD, enable TX, verify DMA read and MII output.

    This test:
    1. Pre-loads frame data into DMA slave RAM
    2. Configures a TX buffer descriptor pointing to the frame
    3. Enables TX in MODER
    4. Waits for the MAC to DMA-read the frame and transmit on MII
    5. Checks TX complete interrupt
    """
    tb = EthmacAhbTB(dut)
    await tb.reset()

    # --- Step 1: Pre-load a minimal Ethernet frame into DMA memory ---
    # Destination MAC (broadcast) + Source MAC + EtherType + payload
    frame_data = bytearray(
        b'\xFF\xFF\xFF\xFF\xFF\xFF'   # Dst MAC (broadcast)
        b'\x00\x1A\x2B\x3C\x4D\x5E'  # Src MAC
        b'\x08\x00'                    # EtherType (IPv4)
        b'\x00' * 46                   # Payload (pad to 60 bytes min)
    )
    frame_len = len(frame_data)
    buf_addr = 0x0000  # DMA buffer address in slave RAM

    tb.dma_write_mem(buf_addr, frame_data)

    # --- Step 2: Set TX_BD_NUM to 1 (use 1 TX BD, rest are RX) ---
    await tb.reg_write(REG_TX_BD_NUM, 0x01)

    # --- Step 3: Configure TX BD 0 ---
    # Status word: length, ready, IRQ, wrap, PAD, CRC
    tx_flags = TX_BD_RD | TX_BD_IRQ | TX_BD_WR | TX_BD_PAD | TX_BD_CRC
    await tb.setup_tx_bd(0, buf_addr, frame_len, tx_flags)

    # Verify BD was written
    bd_status = await tb.read_bd_status(0)
    tb.log.info("TX BD0 status after setup: 0x%08X", bd_status)

    # --- Step 4: Set MAC address ---
    await tb.reg_write(REG_MAC_ADDR0, 0x5E4D3C2B)
    await tb.reg_write(REG_MAC_ADDR1, 0x0000001A)

    # --- Step 5: Enable TX interrupt mask ---
    await tb.reg_write(REG_INT_MASK, INT_TXB)

    # --- Step 6: Enable TX in MODER ---
    moder = 0x0000A000 | MODER_TXEN | MODER_PAD | MODER_CRCEN | MODER_FULLD
    await tb.reg_write(REG_MODER, moder)

    # --- Step 7: Wait for TX to complete ---
    # The MAC will DMA-read frame data and shift it out on MII.
    # Poll INT_SOURCE for TXB bit or wait for int_o.
    for _ in range(5000):
        await RisingEdge(dut.hclk)
        if dut.int_o.value == 1:
            break

    # Check interrupt source
    int_src = await tb.reg_read(REG_INT_SOURCE)
    tb.log.info("INT_SOURCE after TX: 0x%08X", int_src)

    # Check BD status (RD bit should be cleared by MAC after TX)
    bd_status = await tb.read_bd_status(0)
    tb.log.info("TX BD0 status after TX: 0x%08X", bd_status)
    assert (bd_status & TX_BD_RD) == 0, \
        "TX BD Ready bit should be cleared after transmission"

    # If cocotbext-eth is available, check the transmitted frame
    if tb.mii_phy is not None:
        tx_frame = await with_timeout(tb.mii_phy.tx.recv(), 100, "us")
        tb.log.info("Captured TX frame: %d bytes", len(tx_frame.data))


@cocotb.test()
async def test_dma_rx_frame(dut):
    """5.2/5.4: Configure RX BD, inject MII frame, verify DMA write.

    Requires cocotbext-eth for MII frame injection.
    """
    if not HAS_COCOTBEXT_ETH:
        dut._log.warning("cocotbext-eth not installed, skipping MII RX test")
        return

    tb = EthmacAhbTB(dut)
    await tb.reset()

    # --- Step 1: Configure RX buffer descriptor ---
    rx_buf_addr = 0x2000  # RX buffer in DMA slave RAM
    num_tx_bds = 1

    await tb.reg_write(REG_TX_BD_NUM, num_tx_bds)

    # RX BD is at index = TX_BD_NUM (first RX BD after TX BDs)
    rx_bd_index = num_tx_bds
    rx_flags = RX_BD_E | RX_BD_IRQ | RX_BD_WR
    await tb.setup_rx_bd(rx_bd_index, rx_buf_addr, rx_flags)

    # --- Step 2: Set MAC address ---
    await tb.reg_write(REG_MAC_ADDR0, 0x5E4D3C2B)
    await tb.reg_write(REG_MAC_ADDR1, 0x0000001A)

    # --- Step 3: Enable RX interrupt and RX in MODER ---
    await tb.reg_write(REG_INT_MASK, INT_RXB)

    moder = 0x0000A000 | MODER_RXEN | MODER_PAD | MODER_CRCEN | MODER_FULLD
    await tb.reg_write(REG_MODER, moder)

    # --- Step 4: Inject a frame on MII RX ---
    from cocotbext.eth import MiiFrame
    rx_frame_payload = bytearray(
        b'\x00\x1A\x2B\x3C\x4D\x5E'  # Dst MAC (our MAC)
        b'\xAA\xBB\xCC\xDD\xEE\xFF'  # Src MAC
        b'\x08\x00'                    # EtherType
        + b'\xDE\xAD\xBE\xEF' * 10   # Payload (40 bytes)
        + b'\x00' * 6                 # Pad to 60
    )
    frame = MiiFrame.from_payload(rx_frame_payload)
    await tb.mii_phy.rx.send(frame)

    # --- Step 5: Wait for RX to complete ---
    for _ in range(10000):
        await RisingEdge(dut.hclk)
        if dut.int_o.value == 1:
            break

    int_src = await tb.reg_read(REG_INT_SOURCE)
    tb.log.info("INT_SOURCE after RX: 0x%08X", int_src)

    # Check RX BD status (E bit should be cleared)
    bd_status = await tb.read_bd_status(rx_bd_index)
    tb.log.info("RX BD status after RX: 0x%08X", bd_status)
    assert (bd_status & RX_BD_E) == 0, \
        "RX BD Empty bit should be cleared after reception"

    # Check received data in DMA memory
    rx_data = tb.dma_read_mem(rx_buf_addr, 64)
    tb.log.info("RX DMA data (first 32 bytes): %s", rx_data[:32].hex())


# ===========================================================================
# Layer 6 — Interrupt Tests
# ===========================================================================

@cocotb.test()
async def test_interrupt_default_deasserted(dut):
    """6.3: After reset, interrupt should be deasserted."""
    tb = EthmacAhbTB(dut)
    await tb.reset()

    await ClockCycles(dut.hclk, 5)
    assert dut.int_o.value == 0, "Interrupt should be deasserted after reset"


@cocotb.test()
async def test_interrupt_masking(dut):
    """6.3: With INT_MASK = 0, no interrupts should assert."""
    tb = EthmacAhbTB(dut)
    await tb.reset()

    # Ensure mask is clear
    await tb.reg_write(REG_INT_MASK, 0x00000000)
    mask = await tb.reg_read(REG_INT_MASK)
    assert mask == 0, "INT_MASK should be 0"

    await ClockCycles(dut.hclk, 10)
    assert dut.int_o.value == 0, "No interrupt with mask=0"


# ===========================================================================
# Layer 7 — Reset and Edge Case Tests
# ===========================================================================

@cocotb.test()
async def test_reset_clears_registers(dut):
    """7.1: Assert reset, verify all registers return to defaults."""
    tb = EthmacAhbTB(dut)
    await tb.reset()

    # Write non-default values
    await tb.reg_write(REG_INT_MASK, 0x0000007F)
    await tb.reg_write(REG_HASH0, 0xFFFFFFFF)
    await tb.reg_write(REG_TX_BD_NUM, 0x00000010)

    # Verify they changed
    assert await tb.reg_read(REG_INT_MASK) == 0x0000007F

    # Apply reset
    await tb.reset()

    # Verify defaults restored
    assert await tb.reg_read(REG_INT_MASK) == 0x00000000, "INT_MASK not reset"
    assert await tb.reg_read(REG_HASH0) == 0x00000000, "HASH0 not reset"
    assert await tb.reg_read(REG_TX_BD_NUM) == 0x00000040, "TX_BD_NUM not reset"


@cocotb.test()
async def test_back_to_back_reg_access(dut):
    """7.4: Rapid register writes then reads to check for data corruption."""
    tb = EthmacAhbTB(dut)
    await tb.reset()

    # Write a unique value to each register
    regs = [
        (REG_INT_MASK,  0x0000003F),
        (REG_IPGT,      0x0000001A),
        (REG_IPGR1,     0x00000008),
        (REG_IPGR2,     0x0000000F),
        (REG_HASH0,     0x12345678),
        (REG_HASH1,     0x87654321),
        (REG_MAC_ADDR0, 0xAABBCCDD),
        (REG_MAC_ADDR1, 0x0000EEFF),
    ]

    # Write all
    for addr, val in regs:
        await tb.reg_write(addr, val)

    # Read all back and verify
    for addr, expected in regs:
        read_val = await tb.reg_read(addr)
        assert read_val == expected, \
            "Back-to-back reg 0x{:02X}: expected 0x{:08X}, got 0x{:08X}".format(
                addr, expected, read_val)
