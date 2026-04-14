"""
Cocotb tests for ethmac_subsystem_apb — combined Ethernet MAC + PTP subsystem.

Implements the functional coverage verification plan (VERIFICATION_PLAN.md).
Each test is tagged with its coverage point ID (CP1–CP9).

Uses:
  - Manual APB driver (setup + access phase)
  - cocotbext-ahb: AHBLiteSlaveRAM (responds to DMA master)
  - cocotbext-eth: MiiSource/MiiSink (optional, for MII data path)

Address map:
  0x0000 – 0x0FFF  Ethernet MAC (Port 0)
  0x1000 – 0x1FFF  HA1588 PTP   (Port 1)
"""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ClockCycles, Timer
from cocotbext.ahb import AHBBus, AHBLiteSlaveRAM

try:
    from cocotbext.eth import MiiSource, MiiSink, GmiiFrame
    from cocotb.types import Logic
    if not hasattr(Logic, 'integer'):
        Logic.integer = property(lambda self: int(self))
    HAS_COCOTBEXT_ETH = True
except ImportError:
    HAS_COCOTBEXT_ETH = False


# ---------------------------------------------------------------------------
# Ethernet MAC register addresses (within Port 0: 0x0000–0x0FFF)
# ---------------------------------------------------------------------------
ETH_BASE         = 0x0000
ETH_MODER        = ETH_BASE + 0x00
ETH_INT_SOURCE   = ETH_BASE + 0x04
ETH_INT_MASK     = ETH_BASE + 0x08
ETH_IPGT         = ETH_BASE + 0x0C
ETH_IPGR1        = ETH_BASE + 0x10
ETH_IPGR2        = ETH_BASE + 0x14
ETH_PACKETLEN    = ETH_BASE + 0x18
ETH_TX_BD_NUM    = ETH_BASE + 0x20
ETH_MIIMODER     = ETH_BASE + 0x28
ETH_MAC_ADDR0    = ETH_BASE + 0x40
ETH_MAC_ADDR1    = ETH_BASE + 0x44
ETH_HASH0        = ETH_BASE + 0x48
ETH_HASH1        = ETH_BASE + 0x4C
ETH_BD_BASE      = ETH_BASE + 0x400

# MODER bits
MODER_RXEN   = (1 << 0)
MODER_TXEN   = (1 << 1)
MODER_FULLD  = (1 << 10)
MODER_CRCEN  = (1 << 13)
MODER_PAD    = (1 << 15)
MODER_PRO    = (1 << 5)

# TX BD bits
TX_BD_RD  = (1 << 15)
TX_BD_IRQ = (1 << 14)
TX_BD_WR  = (1 << 13)
TX_BD_PAD = (1 << 12)
TX_BD_CRC = (1 << 11)

# RX BD bits
RX_BD_E   = (1 << 15)
RX_BD_IRQ = (1 << 14)
RX_BD_WR  = (1 << 13)

# INT bits
INT_TXB = (1 << 0)
INT_RXB = (1 << 2)

# ---------------------------------------------------------------------------
# HA1588 PTP register addresses (within Port 1: 0x1000–0x1FFF)
# ---------------------------------------------------------------------------
PTP_BASE          = 0x1000
PTP_RTC_CTRL      = PTP_BASE + 0x00
PTP_SCRATCH       = PTP_BASE + 0x04
PTP_TIME_SEC_H    = PTP_BASE + 0x10
PTP_TIME_SEC_L    = PTP_BASE + 0x14
PTP_TIME_NSC_H    = PTP_BASE + 0x18
PTP_TIME_NSC_L    = PTP_BASE + 0x1C
PTP_PERIOD_H      = PTP_BASE + 0x20
PTP_PERIOD_L      = PTP_BASE + 0x24
PTP_ADJ_PERIOD_H  = PTP_BASE + 0x28
PTP_ADJ_PERIOD_L  = PTP_BASE + 0x2C
PTP_ADJ_NUM       = PTP_BASE + 0x30
PTP_TSU_RXCTRL    = PTP_BASE + 0x40
PTP_TSU_RXSTAT    = PTP_BASE + 0x44
PTP_TSU_RXDATA0   = PTP_BASE + 0x50
PTP_TSU_TXCTRL    = PTP_BASE + 0x60
PTP_TSU_TXSTAT    = PTP_BASE + 0x64
PTP_TSU_TXDATA0   = PTP_BASE + 0x70

RTC_CTRL_GET_TIME   = (1 << 0)
RTC_CTRL_SET_ADJ    = (1 << 1)
RTC_CTRL_SET_PERIOD = (1 << 2)
RTC_CTRL_SET_TIME   = (1 << 3)
RTC_CTRL_SET_RESET  = (1 << 4)

HCLK_PERIOD_NS = 10


# ---------------------------------------------------------------------------
# APB master driver (manual — no cocotbext-apb dependency)
# ---------------------------------------------------------------------------
async def apb_write(dut, addr, data, strb=0xF):
    """Perform a single APB write transaction."""
    # Setup phase
    dut.apb_psel.value = 1
    dut.apb_penable.value = 0
    dut.apb_paddr.value = addr
    dut.apb_pwrite.value = 1
    dut.apb_pwdata.value = data
    dut.apb_pstrb.value = strb
    await RisingEdge(dut.pclk)

    # Access phase
    dut.apb_penable.value = 1
    await RisingEdge(dut.pclk)

    # Wait for PREADY
    timeout = 100
    while not dut.apb_pready.value and timeout > 0:
        await RisingEdge(dut.pclk)
        timeout -= 1

    # Deassert
    dut.apb_psel.value = 0
    dut.apb_penable.value = 0
    dut.apb_pwrite.value = 0
    await RisingEdge(dut.pclk)


async def apb_read(dut, addr):
    """Perform a single APB read transaction, return integer value."""
    # Setup phase
    dut.apb_psel.value = 1
    dut.apb_penable.value = 0
    dut.apb_paddr.value = addr
    dut.apb_pwrite.value = 0
    dut.apb_pstrb.value = 0xF
    await RisingEdge(dut.pclk)

    # Access phase
    dut.apb_penable.value = 1
    await RisingEdge(dut.pclk)

    timeout = 100
    while not dut.apb_pready.value and timeout > 0:
        await RisingEdge(dut.pclk)
        timeout -= 1

    val = int(dut.apb_prdata.value)

    # Deassert
    dut.apb_psel.value = 0
    dut.apb_penable.value = 0
    await RisingEdge(dut.pclk)

    return val


# ---------------------------------------------------------------------------
# Testbench class
# ---------------------------------------------------------------------------
class SubsystemTB:
    def __init__(self, dut):
        self.dut = dut
        self.log = dut._log

        # System clock (100 MHz)
        self.clock = Clock(dut.pclk, HCLK_PERIOD_NS, unit="ns")
        cocotb.start_soon(self.clock.start())

        # RTC clock (125 MHz)
        cocotb.start_soon(self._rtc_clock_gen())

        # MII clocks (25 MHz)
        cocotb.start_soon(self._mii_clock_gen())

        # AHB slave RAM for DMA master
        mst_bus = AHBBus.from_prefix(dut, "mst")
        self.dma_slave = AHBLiteSlaveRAM(
            mst_bus, dut.pclk, dut.presetn, mem_size=65536
        )

        # MII source/sink
        self.mii_tx_sink = None
        self.mii_rx_source = None
        if HAS_COCOTBEXT_ETH:
            self.mii_tx_sink = MiiSink(
                data=dut.mtxd_pad_o, er=dut.mtxerr_pad_o,
                dv=dut.mtxen_pad_o, clock=dut.mtx_clk_inv)
            self.mii_rx_source = MiiSource(
                data=dut.mrxd_pad_i, er=dut.mrxerr_pad_i,
                dv=dut.mrxdv_pad_i, clock=dut.mrx_clk_inv)

    async def _rtc_clock_gen(self):
        while True:
            self.dut.rtc_clk.value = 0
            await Timer(4, unit="ns")
            self.dut.rtc_clk.value = 1
            await Timer(4, unit="ns")

    async def _mii_clock_gen(self):
        while True:
            self.dut.mtx_clk_pad_i.value = 0
            self.dut.mrx_clk_pad_i.value = 0
            await Timer(20, unit="ns")
            self.dut.mtx_clk_pad_i.value = 1
            self.dut.mrx_clk_pad_i.value = 1
            await Timer(20, unit="ns")

    async def reset(self, cycles=10):
        self.dut.presetn.value = 0
        self.dut.apb_psel.value = 0
        self.dut.apb_penable.value = 0
        self.dut.apb_paddr.value = 0
        self.dut.apb_pwrite.value = 0
        self.dut.apb_pwdata.value = 0
        self.dut.apb_pstrb.value = 0
        if not HAS_COCOTBEXT_ETH:
            self.dut.mrxd_pad_i.value = 0
            self.dut.mrxdv_pad_i.value = 0
            self.dut.mrxerr_pad_i.value = 0
        self.dut.mcoll_pad_i.value = 0
        self.dut.mcrs_pad_i.value = 0
        self.dut.md_pad_i.value = 1
        await ClockCycles(self.dut.pclk, cycles)
        self.dut.presetn.value = 1
        await ClockCycles(self.dut.pclk, 5)

    def dma_write_mem(self, addr, data_bytes):
        self.dma_slave.memory.write(addr, data_bytes)

    def dma_read_mem(self, addr, length):
        return self.dma_slave.memory.read(addr, length)

    def check_no_x(self, signal, name):
        """Assert signal contains no X/Z bits (CP9 xprop checks)."""
        raw = signal.value
        assert 'x' not in str(raw).lower() and 'z' not in str(raw).lower(), \
            f"X/Z detected on {name}: {raw}"


# ===========================================================================
# CP1 — APB Mux Address Decode
# ===========================================================================

@cocotb.test()
async def test_cp1_1_apb_mux_eth_access(dut):
    """CP1.1: Write/read to Ethernet MAC register space."""
    tb = SubsystemTB(dut)
    await tb.reset()

    await apb_write(dut, ETH_HASH0, 0xAAAA5555)
    val = await apb_read(dut, ETH_HASH0)
    assert val == 0xAAAA5555, f"CP1.1: ETH HASH0 expected 0xAAAA5555, got 0x{val:08X}"


@cocotb.test()
async def test_cp1_2_apb_mux_ptp_access(dut):
    """CP1.2: Write/read to HA1588 PTP register space."""
    tb = SubsystemTB(dut)
    await tb.reset()

    await apb_write(dut, PTP_SCRATCH, 0xDEADBEEF)
    val = await apb_read(dut, PTP_SCRATCH)
    assert val == 0xDEADBEEF, f"CP1.2: PTP SCRATCH expected 0xDEADBEEF, got 0x{val:08X}"


@cocotb.test()
async def test_cp1_3_apb_mux_interleaved(dut):
    """CP1.3: Interleaved access across both peripherals."""
    tb = SubsystemTB(dut)
    await tb.reset()

    await apb_write(dut, ETH_HASH0, 0x11111111)
    await apb_write(dut, PTP_SCRATCH, 0x22222222)
    await apb_write(dut, ETH_HASH1, 0x33333333)
    await apb_write(dut, PTP_PERIOD_H, 0x00000008)

    assert await apb_read(dut, ETH_HASH0) == 0x11111111
    assert await apb_read(dut, PTP_SCRATCH) == 0x22222222
    assert await apb_read(dut, ETH_HASH1) == 0x33333333
    assert await apb_read(dut, PTP_PERIOD_H) == 0x00000008


@cocotb.test()
async def test_cp1_4_apb_mux_disabled_port(dut):
    """CP1.4: Access to disabled mux port completes without hang."""
    tb = SubsystemTB(dut)
    await tb.reset()

    # Port 2 (0x2000) is disabled — mux returns PREADY=1 (default)
    val = await apb_read(dut, 0x2000)
    dut._log.info("CP1.4: Read from disabled port 0x2000 = 0x%08X", val)
    # Just verify it doesn't hang; data is undefined (likely 0)


# ===========================================================================
# CP2 — Ethernet MAC Register Access via APB
# ===========================================================================

@cocotb.test()
async def test_cp2_1_eth_moder_default(dut):
    """CP2.1: Read MODER default after reset."""
    tb = SubsystemTB(dut)
    await tb.reset()

    val = await apb_read(dut, ETH_MODER)
    assert val == 0x0000A000, f"CP2.1: MODER default expected 0xA000, got 0x{val:08X}"


@cocotb.test()
async def test_cp2_2_eth_moder_write_readback(dut):
    """CP2.2: Write/readback MODER."""
    tb = SubsystemTB(dut)
    await tb.reset()

    moder = 0xA000 | MODER_TXEN | MODER_RXEN | MODER_PAD | MODER_CRCEN
    await apb_write(dut, ETH_MODER, moder)
    val = await apb_read(dut, ETH_MODER)
    assert val == moder, f"CP2.2: MODER expected 0x{moder:08X}, got 0x{val:08X}"


@cocotb.test()
async def test_cp2_3_eth_int_mask(dut):
    """CP2.3: Write/readback INT_MASK."""
    tb = SubsystemTB(dut)
    await tb.reset()

    await apb_write(dut, ETH_INT_MASK, 0x7F)
    val = await apb_read(dut, ETH_INT_MASK)
    assert val == 0x7F, f"CP2.3: INT_MASK expected 0x7F, got 0x{val:08X}"


@cocotb.test()
async def test_cp2_4_eth_mac_addr(dut):
    """CP2.4: Write/readback MAC address."""
    tb = SubsystemTB(dut)
    await tb.reset()

    await apb_write(dut, ETH_MAC_ADDR0, 0xDEADBEEF)
    await apb_write(dut, ETH_MAC_ADDR1, 0x00001234)
    assert await apb_read(dut, ETH_MAC_ADDR0) == 0xDEADBEEF
    assert await apb_read(dut, ETH_MAC_ADDR1) == 0x00001234


@cocotb.test()
async def test_cp2_5_eth_bd_write_read(dut):
    """CP2.5: Buffer descriptor write/read."""
    tb = SubsystemTB(dut)
    await tb.reset()

    bd_addr = ETH_BD_BASE
    await apb_write(dut, bd_addr, 0x12345678)
    await apb_write(dut, bd_addr + 4, 0x00010000)
    val0 = await apb_read(dut, bd_addr)
    val1 = await apb_read(dut, bd_addr + 4)
    assert val0 == 0x12345678, f"CP2.5: BD word0 mismatch: 0x{val0:08X}"
    assert val1 == 0x00010000, f"CP2.5: BD word1 mismatch: 0x{val1:08X}"


@cocotb.test()
async def test_cp2_6_eth_walking_ones(dut):
    """CP2.6: Walking ones on HASH0 register."""
    tb = SubsystemTB(dut)
    await tb.reset()

    for bit in range(32):
        pattern = 1 << bit
        await apb_write(dut, ETH_HASH0, pattern)
        val = await apb_read(dut, ETH_HASH0)
        assert val == pattern, f"CP2.6: bit {bit}: wrote 0x{pattern:08X}, got 0x{val:08X}"


# ===========================================================================
# CP3 — HA1588 PTP Register Access via APB
# ===========================================================================

@cocotb.test()
async def test_cp3_1_ptp_scratch(dut):
    """CP3.1: Write/readback PTP scratch register."""
    tb = SubsystemTB(dut)
    await tb.reset()

    await apb_write(dut, PTP_SCRATCH, 0xCAFEBABE)
    val = await apb_read(dut, PTP_SCRATCH)
    assert val == 0xCAFEBABE, f"CP3.1: expected 0xCAFEBABE, got 0x{val:08X}"


@cocotb.test()
async def test_cp3_2_ptp_period_regs(dut):
    """CP3.2: Write/readback RTC period registers."""
    tb = SubsystemTB(dut)
    await tb.reset()

    await apb_write(dut, PTP_PERIOD_H, 0x00000008)
    await apb_write(dut, PTP_PERIOD_L, 0x00000000)
    assert await apb_read(dut, PTP_PERIOD_H) == 0x00000008
    assert await apb_read(dut, PTP_PERIOD_L) == 0x00000000


@cocotb.test()
async def test_cp3_3_ptp_time_regs(dut):
    """CP3.3: Write/readback RTC time registers via TIME_LD + TIME_RD.

    The HA1588 time registers (0x10-0x1C) are write-only staging registers.
    To read back the time, the value must first be loaded into the RTC via
    TIME_LD (CTRL[3]), then read back via TIME_RD (CTRL[0]) which captures
    the RTC's current time through a CDC handshake.
    """
    tb = SubsystemTB(dut)
    await tb.reset()

    # First load a period so the RTC can operate
    await apb_write(dut, PTP_PERIOD_H, 0x00000008)
    await apb_write(dut, PTP_PERIOD_L, 0x00000000)
    await apb_write(dut, PTP_RTC_CTRL, 0x04)  # PERIOD_LD
    await ClockCycles(dut.pclk, 10)

    # Write time staging registers
    await apb_write(dut, PTP_TIME_SEC_H, 0x00001234)
    await apb_write(dut, PTP_TIME_SEC_L, 0xABCD0000)
    await apb_write(dut, PTP_TIME_NSC_H, 0x12345678)
    await apb_write(dut, PTP_TIME_NSC_L, 0x000000FF)

    # Load time into RTC: pulse TIME_LD (CTRL[3])
    await apb_write(dut, PTP_RTC_CTRL, 0x08)
    await ClockCycles(dut.pclk, 20)  # Wait for CDC

    # Read back via TIME_RD (CTRL[0])
    await apb_write(dut, PTP_RTC_CTRL, 0x01)
    await ClockCycles(dut.pclk, 20)  # Wait for CDC handshake

    sec_h = await apb_read(dut, PTP_TIME_SEC_H)
    sec_l = await apb_read(dut, PTP_TIME_SEC_L)
    assert sec_h == 0x00001234, f"SEC_H mismatch: 0x{sec_h:08X}"
    assert sec_l == 0xABCD0000, f"SEC_L mismatch: 0x{sec_l:08X}"


@cocotb.test()
async def test_cp3_4_ptp_adj_regs(dut):
    """CP3.4: Write/readback adjustment registers."""
    tb = SubsystemTB(dut)
    await tb.reset()

    await apb_write(dut, PTP_ADJ_PERIOD_H, 0x00000001)
    await apb_write(dut, PTP_ADJ_PERIOD_L, 0x80000000)
    await apb_write(dut, PTP_ADJ_NUM, 0x00001000)

    assert await apb_read(dut, PTP_ADJ_PERIOD_H) == 0x00000001
    assert await apb_read(dut, PTP_ADJ_PERIOD_L) == 0x80000000
    assert await apb_read(dut, PTP_ADJ_NUM) == 0x00001000


@cocotb.test()
async def test_cp3_5_ptp_tsu_msgid_mask(dut):
    """CP3.5: Write TSU RX message ID mask."""
    tb = SubsystemTB(dut)
    await tb.reset()

    await apb_write(dut, PTP_TSU_RXSTAT, 0xFF000000)
    val = await apb_read(dut, PTP_TSU_RXSTAT)
    assert (val & 0xFF000000) == 0xFF000000, f"CP3.5: mask mismatch: 0x{val:08X}"


@cocotb.test()
async def test_cp3_6_ptp_walking_ones(dut):
    """CP3.6: Walking ones on PTP scratch register."""
    tb = SubsystemTB(dut)
    await tb.reset()

    for bit in range(32):
        pattern = 1 << bit
        await apb_write(dut, PTP_SCRATCH, pattern)
        val = await apb_read(dut, PTP_SCRATCH)
        assert val == pattern, f"CP3.6: bit {bit}: wrote 0x{pattern:08X}, got 0x{val:08X}"


# ===========================================================================
# CP4 — RTC Functional Operation
# ===========================================================================

@cocotb.test()
async def test_cp4_1_rtc_period_load(dut):
    """CP4.1: RTC period load and time advance."""
    tb = SubsystemTB(dut)
    await tb.reset()

    await apb_write(dut, PTP_PERIOD_H, 0x00000008)
    await apb_write(dut, PTP_PERIOD_L, 0x00000000)
    await apb_write(dut, PTP_RTC_CTRL, RTC_CTRL_SET_PERIOD)
    await ClockCycles(dut.pclk, 20)
    await apb_write(dut, PTP_RTC_CTRL, 0)
    await ClockCycles(dut.pclk, 200)

    await apb_write(dut, PTP_RTC_CTRL, RTC_CTRL_GET_TIME)
    for _ in range(50):
        ctrl = await apb_read(dut, PTP_RTC_CTRL)
        if ctrl & 0x1:
            break
        await ClockCycles(dut.pclk, 5)

    ns_h = await apb_read(dut, PTP_TIME_NSC_H)
    dut._log.info("CP4.1: RTC ns = 0x%08X", ns_h)
    assert ns_h > 0, "CP4.1: RTC time did not advance"


@cocotb.test()
async def test_cp4_2_rtc_time_load(dut):
    """CP4.2: Direct time load."""
    tb = SubsystemTB(dut)
    await tb.reset()

    # Load period first
    await apb_write(dut, PTP_PERIOD_H, 0x00000008)
    await apb_write(dut, PTP_PERIOD_L, 0x00000000)
    await apb_write(dut, PTP_RTC_CTRL, RTC_CTRL_SET_PERIOD)
    await ClockCycles(dut.pclk, 20)
    await apb_write(dut, PTP_RTC_CTRL, 0)

    # Load time: 100 seconds
    await apb_write(dut, PTP_TIME_SEC_H, 0x0000)
    await apb_write(dut, PTP_TIME_SEC_L, 0x00000064)
    await apb_write(dut, PTP_TIME_NSC_H, 0x00000000)
    await apb_write(dut, PTP_TIME_NSC_L, 0x00000000)
    await apb_write(dut, PTP_RTC_CTRL, RTC_CTRL_SET_TIME)
    await ClockCycles(dut.pclk, 20)
    await apb_write(dut, PTP_RTC_CTRL, 0)
    await ClockCycles(dut.pclk, 50)

    await apb_write(dut, PTP_RTC_CTRL, RTC_CTRL_GET_TIME)
    for _ in range(50):
        ctrl = await apb_read(dut, PTP_RTC_CTRL)
        if ctrl & 0x1:
            break
        await ClockCycles(dut.pclk, 5)

    sec_l = await apb_read(dut, PTP_TIME_SEC_L)
    assert sec_l >= 0x64, f"CP4.2: seconds {sec_l} < 100 after time load"


@cocotb.test()
async def test_cp4_3_ptp_ns_output(dut):
    """CP4.3: PTP ns output advances."""
    tb = SubsystemTB(dut)
    await tb.reset()

    await apb_write(dut, PTP_PERIOD_H, 0x00000008)
    await apb_write(dut, PTP_PERIOD_L, 0x00000000)
    await apb_write(dut, PTP_RTC_CTRL, RTC_CTRL_SET_PERIOD)
    await ClockCycles(dut.pclk, 20)
    await apb_write(dut, PTP_RTC_CTRL, 0)
    await ClockCycles(dut.pclk, 500)

    ptp_ns = int(dut.rtc_time_ptp_ns.value)
    dut._log.info("CP4.3: rtc_time_ptp_ns = 0x%08X", ptp_ns)
    assert ptp_ns > 0, "CP4.3: PTP ns output is zero"


@cocotb.test()
async def test_cp4_4_one_pps(dut):
    """CP4.4: One-PPS pulse generation (long test, verify signal exists)."""
    tb = SubsystemTB(dut)
    await tb.reset()

    # Load period and set time close to rollover (999,999,000 ns)
    await apb_write(dut, PTP_PERIOD_H, 0x00000008)
    await apb_write(dut, PTP_PERIOD_L, 0x00000000)
    await apb_write(dut, PTP_RTC_CTRL, RTC_CTRL_SET_PERIOD)
    await ClockCycles(dut.pclk, 20)
    await apb_write(dut, PTP_RTC_CTRL, 0)

    # Set time near 1-second boundary
    await apb_write(dut, PTP_TIME_SEC_L, 0x00000000)
    await apb_write(dut, PTP_TIME_NSC_H, 0x3B9AC600)  # ~999,999,488 ns
    await apb_write(dut, PTP_TIME_NSC_L, 0x00000000)
    await apb_write(dut, PTP_RTC_CTRL, RTC_CTRL_SET_TIME)
    await ClockCycles(dut.pclk, 20)
    await apb_write(dut, PTP_RTC_CTRL, 0)

    # Wait for PPS pulse
    pps_seen = False
    for _ in range(20000):
        await RisingEdge(dut.pclk)
        if dut.rtc_time_one_pps.value == 1:
            pps_seen = True
            break

    dut._log.info("CP4.4: one_pps seen = %s", pps_seen)
    assert pps_seen, "CP4.4: one_pps pulse not detected"


# ===========================================================================
# CP5 — Ethernet MAC DMA via AHB Master
# ===========================================================================

@cocotb.test()
async def test_cp5_1_tx_dma(dut):
    """CP5.1: TX DMA read from AHB memory."""
    tb = SubsystemTB(dut)
    await tb.reset()

    # Configure MAC
    await apb_write(dut, ETH_IPGT, 0x15)
    await apb_write(dut, ETH_IPGR1, 0x0C)
    await apb_write(dut, ETH_IPGR2, 0x12)
    await apb_write(dut, ETH_PACKETLEN, 0x00400600)
    await apb_write(dut, ETH_TX_BD_NUM, 0x02)
    await apb_write(dut, ETH_MAC_ADDR0, 0xEF00DEAD)
    await apb_write(dut, ETH_MAC_ADDR1, 0x0000BE00)

    # Build frame (64 bytes minimum)
    frame = (b'\xFF\xFF\xFF\xFF\xFF\xFF'   # dst MAC
             b'\x02\x00\xDE\xAD\xBE\xEF'   # src MAC
             b'\x08\x00'                     # EtherType
             + b'\x55' * 46)                 # payload (pad to 60 bytes)

    tx_buf = 0x0000
    tb.dma_write_mem(tx_buf, frame)

    # Setup TX BD at index 0
    frame_len = len(frame)
    bd_addr = ETH_BD_BASE
    word0 = ((frame_len & 0xFFFF) << 16) | TX_BD_RD | TX_BD_IRQ | TX_BD_WR | TX_BD_PAD | TX_BD_CRC
    await apb_write(dut, bd_addr, word0)
    await apb_write(dut, bd_addr + 4, tx_buf)

    # Enable MAC TX
    await apb_write(dut, ETH_INT_MASK, INT_TXB)
    moder = 0xA000 | MODER_TXEN | MODER_PAD | MODER_CRCEN | MODER_FULLD
    await apb_write(dut, ETH_MODER, moder)

    # Wait for TX to complete (poll BD RD bit clear)
    for _ in range(30000):
        await RisingEdge(dut.pclk)
        bd_status = await apb_read(dut, bd_addr)
        if not (bd_status & TX_BD_RD):
            break

    dut._log.info("CP5.1: TX BD status = 0x%08X", bd_status)
    assert not (bd_status & TX_BD_RD), "CP5.1: TX BD RD bit never cleared"


@cocotb.test()
async def test_cp5_4_tx_interrupt(dut):
    """CP5.4: TX interrupt fires after transmission."""
    tb = SubsystemTB(dut)
    await tb.reset()

    # Configure MAC
    await apb_write(dut, ETH_IPGT, 0x15)
    await apb_write(dut, ETH_PACKETLEN, 0x00400600)
    await apb_write(dut, ETH_TX_BD_NUM, 0x02)

    frame = b'\xFF' * 6 + b'\x02\x00\xDE\xAD\xBE\xEF' + b'\x08\x00' + b'\xAA' * 46
    tb.dma_write_mem(0x0000, frame)

    bd_addr = ETH_BD_BASE
    word0 = ((len(frame) & 0xFFFF) << 16) | TX_BD_RD | TX_BD_IRQ | TX_BD_WR | TX_BD_PAD | TX_BD_CRC
    await apb_write(dut, bd_addr, word0)
    await apb_write(dut, bd_addr + 4, 0x0000)

    await apb_write(dut, ETH_INT_MASK, INT_TXB)
    moder = 0xA000 | MODER_TXEN | MODER_PAD | MODER_CRCEN | MODER_FULLD
    await apb_write(dut, ETH_MODER, moder)

    int_seen = False
    for _ in range(30000):
        await RisingEdge(dut.pclk)
        if dut.int_o.value == 1:
            int_seen = True
            break

    dut._log.info("CP5.4: int_o asserted = %s", int_seen)
    assert int_seen, "CP5.4: TX interrupt never asserted"

    # Clear interrupt
    int_src = await apb_read(dut, ETH_INT_SOURCE)
    assert int_src & INT_TXB, f"CP5.4: INT_SOURCE missing TXB: 0x{int_src:08X}"
    await apb_write(dut, ETH_INT_SOURCE, INT_TXB)


# ===========================================================================
# CP8 — Reset Behaviour
# ===========================================================================

@cocotb.test()
async def test_cp8_1_reset_clears_regs(dut):
    """CP8.1: Reset clears MAC registers to defaults."""
    tb = SubsystemTB(dut)
    await tb.reset()

    await apb_write(dut, ETH_INT_MASK, 0x7F)
    await apb_write(dut, PTP_SCRATCH, 0xBEEF)

    await tb.reset()

    moder = await apb_read(dut, ETH_MODER)
    int_mask = await apb_read(dut, ETH_INT_MASK)
    assert moder == 0xA000, f"CP8.1: MODER after reset: 0x{moder:08X}"
    assert int_mask == 0, f"CP8.1: INT_MASK after reset: 0x{int_mask:08X}"


@cocotb.test()
async def test_cp8_2_reset_int_deasserted(dut):
    """CP8.2: Reset de-asserts int_o."""
    tb = SubsystemTB(dut)
    await tb.reset()

    assert dut.int_o.value == 0, "CP8.2: int_o not 0 after reset"


@cocotb.test()
async def test_cp8_3_ahb_master_idle_after_reset(dut):
    """CP8.3: AHB master outputs IDLE after reset."""
    tb = SubsystemTB(dut)
    await tb.reset()

    htrans = int(dut.mst_htrans.value)
    assert htrans == 0, f"CP8.3: htrans after reset: {htrans} (expected IDLE=0)"


# ===========================================================================
# CP9 — X-Propagation (xprop)
# ===========================================================================

@cocotb.test()
async def test_cp9_1_apb_prdata_no_x(dut):
    """CP9.1: APB prdata is X-free on valid read."""
    tb = SubsystemTB(dut)
    await tb.reset()

    # Read from both peripherals
    await apb_read(dut, ETH_MODER)
    tb.check_no_x(dut.apb_prdata, "apb_prdata (ETH)")

    await apb_read(dut, PTP_SCRATCH)
    tb.check_no_x(dut.apb_prdata, "apb_prdata (PTP)")


@cocotb.test()
async def test_cp9_4_rtc_output_no_x(dut):
    """CP9.4: RTC outputs X-free after period load."""
    tb = SubsystemTB(dut)
    await tb.reset()

    await apb_write(dut, PTP_PERIOD_H, 0x00000008)
    await apb_write(dut, PTP_PERIOD_L, 0x00000000)
    await apb_write(dut, PTP_RTC_CTRL, RTC_CTRL_SET_PERIOD)
    await ClockCycles(dut.pclk, 50)

    tb.check_no_x(dut.rtc_time_ptp_ns, "rtc_time_ptp_ns")
    tb.check_no_x(dut.rtc_time_ptp_sec, "rtc_time_ptp_sec")
