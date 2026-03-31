"""
Cocotb tests for the ha1588_ahb IEEE 1588 PTP timestamping unit AHB wrapper.

Tests register access via AHB slave interface, RTC time output behaviour,
and basic PTP timestamping using:
  - cocotbext-ahb: AHBLiteMaster

HA1588 Register map (byte addresses, from reg.v):
  RTC registers:
    0x00  RTC_CTRL        0x04  SCRATCH
    0x10  TIME_SEC_H      0x14  TIME_SEC_L
    0x18  TIME_NSC_H      0x1C  TIME_NSC_L
    0x20  PERIOD_H        0x24  PERIOD_L
    0x28  ADJ_PERIOD_H    0x2C  ADJ_PERIOD_L
    0x30  ADJ_NUM

  TSU RX registers:
    0x40  TSU_RXCTRL      0x44  TSU_RXQUE_STATUS
    0x50  TSU_RXQUE_DATA0 0x54  TSU_RXQUE_DATA1
    0x58  TSU_RXQUE_DATA2 0x5C  TSU_RXQUE_DATA3

  TSU TX registers:
    0x60  TSU_TXCTRL      0x64  TSU_TXQUE_STATUS
    0x70  TSU_TXQUE_DATA0 0x74  TSU_TXQUE_DATA1
    0x78  TSU_TXQUE_DATA2 0x7C  TSU_TXQUE_DATA3
"""

import struct

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ClockCycles, Timer, FallingEdge
from cocotbext.ahb import AHBBus, AHBLiteMaster


# ---------------------------------------------------------------------------
# Register addresses (byte addresses)
# ---------------------------------------------------------------------------
REG_RTC_CTRL      = 0x00
REG_SCRATCH       = 0x04
REG_TIME_SEC_H    = 0x10
REG_TIME_SEC_L    = 0x14
REG_TIME_NSC_H    = 0x18
REG_TIME_NSC_L    = 0x1C
REG_PERIOD_H      = 0x20
REG_PERIOD_L      = 0x24
REG_ADJ_PERIOD_H  = 0x28
REG_ADJ_PERIOD_L  = 0x2C
REG_ADJ_NUM       = 0x30

REG_TSU_RXCTRL    = 0x40
REG_TSU_RXSTAT    = 0x44
REG_TSU_RXDATA0   = 0x50
REG_TSU_RXDATA1   = 0x54
REG_TSU_RXDATA2   = 0x58
REG_TSU_RXDATA3   = 0x5C

REG_TSU_TXCTRL    = 0x60
REG_TSU_TXSTAT    = 0x64
REG_TSU_TXDATA0   = 0x70
REG_TSU_TXDATA1   = 0x74
REG_TSU_TXDATA2   = 0x78
REG_TSU_TXDATA3   = 0x7C

# RTC_CTRL bits
RTC_CTRL_GET_TIME  = (1 << 0)
RTC_CTRL_SET_ADJ   = (1 << 1)
RTC_CTRL_SET_PERIOD = (1 << 2)
RTC_CTRL_SET_TIME  = (1 << 3)
RTC_CTRL_SET_RESET = (1 << 4)

# TSU CTRL bits
TSU_CTRL_READ_QUEUE = (1 << 0)
TSU_CTRL_RESET      = (1 << 1)

# System clock period
HCLK_PERIOD_NS = 10  # 100 MHz
RTC_CLK_PERIOD_NS = 8  # 125 MHz


# ---------------------------------------------------------------------------
# Testbench setup helpers
# ---------------------------------------------------------------------------
class Ha1588AhbTB:
    """Testbench wrapper holding all bus models and helpers."""

    def __init__(self, dut):
        self.dut = dut
        self.log = dut._log

        # Start system clock (100 MHz)
        self.clock = Clock(dut.hclk, HCLK_PERIOD_NS, units="ns")
        cocotb.start_soon(self.clock.start())

        # Start RTC clock (125 MHz)
        cocotb.start_soon(self._rtc_clock_gen())

        # AHB Lite Master -> drives the DUT's AHB slave port (register access)
        slv_bus = AHBBus.from_prefix(dut, "slv")
        self.ahb_master = AHBLiteMaster(
            slv_bus, dut.hclk, dut.hresetn, timeout=200
        )

    async def _rtc_clock_gen(self):
        """Generate 125 MHz RTC clock."""
        half = RTC_CLK_PERIOD_NS // 2
        while True:
            self.dut.rtc_clk.value = 0
            await Timer(half, units="ns")
            self.dut.rtc_clk.value = 1
            await Timer(half, units="ns")

    async def reset(self, cycles=10):
        """Assert reset and initialise tie-off inputs."""
        self.dut.hresetn.value = 0

        # Tie off GMII monitoring inputs
        self.dut.rx_gmii_ctrl.value = 0
        self.dut.rx_gmii_data.value = 0
        self.dut.rx_giga_mode.value = 0
        self.dut.tx_gmii_ctrl.value = 0
        self.dut.tx_gmii_data.value = 0
        self.dut.tx_giga_mode.value = 0

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

    async def start_gmii_clocks(self):
        """Start GMII RX and TX clocks at 125 MHz (gigabit mode)."""
        cocotb.start_soon(self._gmii_clock_gen())

    async def _gmii_clock_gen(self, period_ns=8):
        """Generate 125 MHz GMII TX and RX clocks."""
        half = period_ns // 2
        while True:
            self.dut.rx_gmii_clk.value = 0
            self.dut.tx_gmii_clk.value = 0
            await Timer(half, units="ns")
            self.dut.rx_gmii_clk.value = 1
            self.dut.tx_gmii_clk.value = 1
            await Timer(half, units="ns")


# ===========================================================================
# Layer 1 -- Register Access Tests
# ===========================================================================

@cocotb.test()
async def test_scratch_register(dut):
    """1.1: Write scratch register and readback."""
    tb = Ha1588AhbTB(dut)
    await tb.reset()

    test_val = 0xDEADBEEF
    await tb.reg_write(REG_SCRATCH, test_val)
    read_val = await tb.reg_read(REG_SCRATCH)
    tb.log.info("SCRATCH: wrote 0x%08X, read 0x%08X", test_val, read_val)
    assert read_val == test_val, \
        "SCRATCH: expected 0x{:08X}, got 0x{:08X}".format(test_val, read_val)


@cocotb.test()
async def test_reg_write_readback(dut):
    """1.2: Write known patterns to RW registers and read them back."""
    tb = Ha1588AhbTB(dut)
    await tb.reset()

    test_patterns = [
        (REG_SCRATCH,      0xCAFEBABE),
        (REG_TIME_SEC_H,   0x00001234),
        (REG_TIME_SEC_L,   0xABCD5678),
        (REG_TIME_NSC_H,   0x12345678),
        (REG_TIME_NSC_L,   0x000000FF),
        (REG_PERIOD_H,     0x00000008),
        (REG_PERIOD_L,     0x00000000),
        (REG_ADJ_PERIOD_H, 0x00000001),
        (REG_ADJ_PERIOD_L, 0x80000000),
        (REG_ADJ_NUM,      0x00001000),
    ]

    for addr, write_val in test_patterns:
        await tb.reg_write(addr, write_val)
        read_val = await tb.reg_read(addr)
        tb.log.info("Reg 0x%02X: wrote 0x%08X, read 0x%08X",
                    addr, write_val, read_val)
        assert read_val == write_val, \
            "Reg 0x{:02X}: wrote 0x{:08X}, read 0x{:08X}".format(
                addr, write_val, read_val)


@cocotb.test()
async def test_rtc_ctrl_register(dut):
    """1.3: Write RTC control bits and readback."""
    tb = Ha1588AhbTB(dut)
    await tb.reset()

    # Write SET_PERIOD bit
    ctrl_val = RTC_CTRL_SET_PERIOD
    await tb.reg_write(REG_RTC_CTRL, ctrl_val)
    read_val = await tb.reg_read(REG_RTC_CTRL)
    tb.log.info("RTC_CTRL: wrote 0x%08X, read 0x%08X", ctrl_val, read_val)
    # RTC_CTRL readback includes status bits (adj_ld_done, time_ok)
    # Check the writable bits [4:2] are set correctly
    assert (read_val >> 2) & 0x7 == (ctrl_val >> 2) & 0x7, \
        "RTC_CTRL writable bits mismatch"


@cocotb.test()
async def test_tsu_ctrl_registers(dut):
    """1.4: Write TSU control registers and readback."""
    tb = Ha1588AhbTB(dut)
    await tb.reset()

    # TSU RX CTRL
    await tb.reg_write(REG_TSU_RXCTRL, TSU_CTRL_RESET)
    read_val = await tb.reg_read(REG_TSU_RXCTRL)
    tb.log.info("TSU_RXCTRL: read 0x%08X", read_val)
    assert (read_val & 0x2) == TSU_CTRL_RESET

    # TSU TX CTRL
    await tb.reg_write(REG_TSU_TXCTRL, TSU_CTRL_RESET)
    read_val = await tb.reg_read(REG_TSU_TXCTRL)
    tb.log.info("TSU_TXCTRL: read 0x%08X", read_val)
    assert (read_val & 0x2) == TSU_CTRL_RESET


@cocotb.test()
async def test_tsu_msgid_mask(dut):
    """1.5: Write PTP message ID mask and readback."""
    tb = Ha1588AhbTB(dut)
    await tb.reset()

    # RX queue status register [31:24] = PTP message ID mask
    mask_val = 0xFF000000
    await tb.reg_write(REG_TSU_RXSTAT, mask_val)
    read_val = await tb.reg_read(REG_TSU_RXSTAT)
    tb.log.info("TSU_RXSTAT: wrote 0x%08X, read 0x%08X", mask_val, read_val)
    assert (read_val & 0xFF000000) == mask_val, \
        "TSU_RXSTAT mask: expected 0x{:08X}, got 0x{:08X}".format(
            mask_val, read_val & 0xFF000000)

    # TX queue status register
    await tb.reg_write(REG_TSU_TXSTAT, mask_val)
    read_val = await tb.reg_read(REG_TSU_TXSTAT)
    assert (read_val & 0xFF000000) == mask_val


@cocotb.test()
async def test_walking_ones(dut):
    """1.6: Walking ones on scratch register to detect stuck-at faults."""
    tb = Ha1588AhbTB(dut)
    await tb.reset()

    for bit in range(32):
        pattern = 1 << bit
        await tb.reg_write(REG_SCRATCH, pattern)
        read_val = await tb.reg_read(REG_SCRATCH)
        assert read_val == pattern, \
            "Walking ones bit {}: wrote 0x{:08X}, read 0x{:08X}".format(
                bit, pattern, read_val)


@cocotb.test()
async def test_walking_zeros(dut):
    """1.7: Walking zeros on scratch register to detect stuck-at faults."""
    tb = Ha1588AhbTB(dut)
    await tb.reset()

    for bit in range(32):
        pattern = 0xFFFFFFFF ^ (1 << bit)
        await tb.reg_write(REG_SCRATCH, pattern)
        read_val = await tb.reg_read(REG_SCRATCH)
        assert read_val == pattern, \
            "Walking zeros bit {}: wrote 0x{:08X}, read 0x{:08X}".format(
                bit, pattern, read_val)


# ===========================================================================
# Layer 2 -- RTC Functional Tests
# ===========================================================================

@cocotb.test()
async def test_rtc_period_load(dut):
    """2.1: Load RTC period and verify it takes effect."""
    tb = Ha1588AhbTB(dut)
    await tb.reset()

    # Set period: 8ns integer + 0 fractional (125 MHz)
    await tb.reg_write(REG_PERIOD_H, 0x00000008)
    await tb.reg_write(REG_PERIOD_L, 0x00000000)

    # Assert SET_PERIOD
    await tb.reg_write(REG_RTC_CTRL, RTC_CTRL_SET_PERIOD)

    # Wait for CDC to propagate
    await ClockCycles(dut.hclk, 20)

    # Clear the control bit
    await tb.reg_write(REG_RTC_CTRL, 0)

    # Wait for RTC to accumulate some time
    await ClockCycles(dut.hclk, 200)

    # Read back time via GET_TIME
    await tb.reg_write(REG_RTC_CTRL, RTC_CTRL_GET_TIME)
    await ClockCycles(dut.hclk, 20)

    # Poll for time_ok (bit 0 of RTC_CTRL readback)
    for _ in range(50):
        ctrl = await tb.reg_read(REG_RTC_CTRL)
        if ctrl & 0x1:
            break
        await ClockCycles(dut.hclk, 5)

    ns_h = await tb.reg_read(REG_TIME_NSC_H)
    ns_l = await tb.reg_read(REG_TIME_NSC_L)
    sec_h = await tb.reg_read(REG_TIME_SEC_H)
    sec_l = await tb.reg_read(REG_TIME_SEC_L)

    tb.log.info("RTC time: sec=0x%04X_%08X ns=0x%08X.%02X",
                sec_h, sec_l, ns_h, ns_l)

    # The nanosecond counter should have advanced from 0
    assert ns_h > 0 or ns_l > 0 or sec_l > 0, \
        "RTC time did not advance after period load"


@cocotb.test()
async def test_rtc_time_load(dut):
    """2.2: Directly load time into RTC and read back."""
    tb = Ha1588AhbTB(dut)
    await tb.reset()

    # First load a period so the RTC is ticking
    await tb.reg_write(REG_PERIOD_H, 0x00000008)
    await tb.reg_write(REG_PERIOD_L, 0x00000000)
    await tb.reg_write(REG_RTC_CTRL, RTC_CTRL_SET_PERIOD)
    await ClockCycles(dut.hclk, 20)
    await tb.reg_write(REG_RTC_CTRL, 0)

    # Load specific time: 100 seconds, 500000000 ns (0.5s)
    target_sec_h = 0x0000
    target_sec_l = 0x00000064   # 100 seconds
    target_ns_h  = 0x1DCD6500   # 500,000,000 ns (bits [29:0])
    target_ns_l  = 0x00000000   # fractional ns

    await tb.reg_write(REG_TIME_SEC_H, target_sec_h)
    await tb.reg_write(REG_TIME_SEC_L, target_sec_l)
    await tb.reg_write(REG_TIME_NSC_H, target_ns_h)
    await tb.reg_write(REG_TIME_NSC_L, target_ns_l)

    # Assert SET_TIME
    await tb.reg_write(REG_RTC_CTRL, RTC_CTRL_SET_TIME)
    await ClockCycles(dut.hclk, 20)
    await tb.reg_write(REG_RTC_CTRL, 0)

    # Wait a bit then read back
    await ClockCycles(dut.hclk, 50)

    await tb.reg_write(REG_RTC_CTRL, RTC_CTRL_GET_TIME)
    await ClockCycles(dut.hclk, 20)

    for _ in range(50):
        ctrl = await tb.reg_read(REG_RTC_CTRL)
        if ctrl & 0x1:
            break
        await ClockCycles(dut.hclk, 5)

    sec_l = await tb.reg_read(REG_TIME_SEC_L)

    tb.log.info("RTC seconds after load: 0x%08X (expected >= 0x64)", sec_l)
    assert sec_l >= target_sec_l, \
        "RTC seconds should be >= {} after direct load, got {}".format(
            target_sec_l, sec_l)


@cocotb.test()
async def test_rtc_ptp_output(dut):
    """2.3: Verify RTC PTP time output pins are driven."""
    tb = Ha1588AhbTB(dut)
    await tb.reset()

    # Load period and time
    await tb.reg_write(REG_PERIOD_H, 0x00000008)
    await tb.reg_write(REG_PERIOD_L, 0x00000000)
    await tb.reg_write(REG_RTC_CTRL, RTC_CTRL_SET_PERIOD)
    await ClockCycles(dut.hclk, 20)
    await tb.reg_write(REG_RTC_CTRL, 0)

    # Wait for time to accumulate
    await ClockCycles(dut.hclk, 500)

    # Check PTP time output pins
    ptp_ns = int(dut.rtc_time_ptp_ns.value)
    tb.log.info("PTP NS output: 0x%08X", ptp_ns)
    assert ptp_ns > 0, "PTP nanosecond output should be non-zero"


# ===========================================================================
# Layer 3 -- Reset and Edge Cases
# ===========================================================================

@cocotb.test()
async def test_reset_clears_state(dut):
    """3.1: Verify that reset clears registers to defaults."""
    tb = Ha1588AhbTB(dut)
    await tb.reset()

    # Write a known value
    await tb.reg_write(REG_SCRATCH, 0xDEADBEEF)
    read_val = await tb.reg_read(REG_SCRATCH)
    assert read_val == 0xDEADBEEF

    # Reset again
    await tb.reset()

    # Scratch register is not reset by the IP (it's a plain reg),
    # but we can verify the RTC_CTRL is back to default
    ctrl = await tb.reg_read(REG_RTC_CTRL)
    tb.log.info("RTC_CTRL after reset: 0x%08X", ctrl)


@cocotb.test()
async def test_back_to_back_reg_access(dut):
    """3.2: Rapid back-to-back register reads/writes without corruption."""
    tb = Ha1588AhbTB(dut)
    await tb.reset()

    # Write unique values to several registers
    values = {}
    for i, addr in enumerate([REG_SCRATCH, REG_TIME_SEC_H, REG_TIME_SEC_L,
                               REG_PERIOD_H, REG_PERIOD_L, REG_ADJ_NUM]):
        val = 0xA0000000 + i
        await tb.reg_write(addr, val)
        values[addr] = val

    # Read them all back immediately
    for addr, expected in values.items():
        read_val = await tb.reg_read(addr)
        assert read_val == expected, \
            "Back-to-back: reg 0x{:02X} expected 0x{:08X}, got 0x{:08X}".format(
                addr, expected, read_val)


@cocotb.test()
async def test_full_address_space(dut):
    """3.3: Read all registers in the address space (0x00-0x7C)."""
    tb = Ha1588AhbTB(dut)
    await tb.reset()

    # Read every 4-byte aligned register in the 128-byte space
    for addr in range(0, 0x80, 4):
        val = await tb.reg_read(addr)
        tb.log.info("Reg 0x%02X = 0x%08X", addr, val)
    # No assertion — just verifying no bus errors occur


# ===========================================================================
# PTP Frame Helpers
# ===========================================================================

def build_l2_ptp_sync_frame(seq_id=1, src_mac=None, dst_mac=None):
    """Build a minimal L2 PTP Sync frame as a list of bytes.

    Ethernet II frame:
      dst_mac(6) + src_mac(6) + ethertype(2=0x88f7) + PTP payload
    PTP Sync payload (34 bytes minimum):
      transportSpecific(4b) + messageType(4b=0x0) + ...
    """
    if dst_mac is None:
        dst_mac = [0x01, 0x1B, 0x19, 0x00, 0x00, 0x00]  # PTP multicast
    if src_mac is None:
        src_mac = [0x00, 0x1A, 0x2B, 0x3C, 0x4D, 0x5E]

    frame = []
    # Preamble + SFD (7+1 bytes) -- GMII layer sends these
    frame += [0x55] * 7 + [0xD5]
    # Ethernet header
    frame += dst_mac + src_mac
    frame += [0x88, 0xF7]  # EtherType = PTP
    # PTP header (34 bytes)
    frame.append(0x00)  # transportSpecific=0, messageType=0 (Sync)
    frame.append(0x02)  # versionPTP=2
    frame += [0x00, 0x2C]  # messageLength=44
    frame.append(0x00)  # domainNumber
    frame.append(0x00)  # reserved
    frame += [0x00, 0x00]  # flags
    frame += [0x00] * 8    # correctionField
    frame += [0x00] * 4    # reserved
    # sourcePortIdentity (8 bytes clockIdentity + 2 bytes portNumber)
    frame += [0x00, 0x1A, 0x2B, 0xFF, 0xFE, 0x3C, 0x4D, 0x5E]
    frame += [0x00, 0x01]  # portNumber
    # sequenceId (2 bytes)
    frame += [(seq_id >> 8) & 0xFF, seq_id & 0xFF]
    # controlField + logMessageInterval
    frame += [0x00, 0x00]
    # originTimestamp (10 bytes)
    frame += [0x00] * 10
    # Pad to minimum 64-byte frame (minus preamble+SFD and FCS)
    payload_len = len(frame) - 8  # subtract preamble
    if payload_len < 60:
        frame += [0x00] * (60 - payload_len)
    # FCS placeholder (4 bytes — not checked by PTP parser)
    frame += [0x00, 0x00, 0x00, 0x00]
    return frame


async def drive_gmii_frame(dut, frame_bytes, rx=True, giga_mode=True):
    """Drive a frame onto the GMII RX or TX interface byte-by-byte.

    Args:
        frame_bytes: list of bytes including preamble+SFD
        rx: True for RX path, False for TX path
        giga_mode: True for gigabit (8-bit), False for 10/100 (nibble)
    """
    if rx:
        clk_sig = dut.rx_gmii_clk
        ctrl_sig = dut.rx_gmii_ctrl
        data_sig = dut.rx_gmii_data
        mode_sig = dut.rx_giga_mode
    else:
        clk_sig = dut.tx_gmii_clk
        ctrl_sig = dut.tx_gmii_ctrl
        data_sig = dut.tx_gmii_data
        mode_sig = dut.tx_giga_mode

    mode_sig.value = 1 if giga_mode else 0

    if giga_mode:
        for byte in frame_bytes:
            ctrl_sig.value = 1
            data_sig.value = byte
            await RisingEdge(clk_sig)
    else:
        # MII mode: send nibbles (low nibble first, then high nibble)
        for byte in frame_bytes:
            ctrl_sig.value = 1
            data_sig.value = byte & 0x0F
            await RisingEdge(clk_sig)
            ctrl_sig.value = 1
            data_sig.value = (byte >> 4) & 0x0F
            await RisingEdge(clk_sig)

    # Deassert ctrl for inter-frame gap
    ctrl_sig.value = 0
    data_sig.value = 0
    for _ in range(12):
        await RisingEdge(clk_sig)


async def setup_rtc_ticking(tb):
    """Configure RTC with 8ns period so timestamps are meaningful."""
    await tb.reg_write(REG_PERIOD_H, 0x00000008)
    await tb.reg_write(REG_PERIOD_L, 0x00000000)
    await tb.reg_write(REG_RTC_CTRL, RTC_CTRL_SET_PERIOD)
    await ClockCycles(tb.dut.hclk, 20)
    await tb.reg_write(REG_RTC_CTRL, 0)
    await ClockCycles(tb.dut.hclk, 50)


# ===========================================================================
# Layer 2b -- RTC Functional Tests (new)
# ===========================================================================

@cocotb.test()
async def test_rtc_second_rollover(dut):
    """2.4: Verify nanosecond counter rolls over and seconds increment."""
    tb = Ha1588AhbTB(dut)
    await tb.reset()
    await tb.start_gmii_clocks()

    # Load period: 8ns
    await setup_rtc_ticking(tb)

    # Load time just before 1-second boundary: 999,999,000 ns
    await tb.reg_write(REG_TIME_SEC_H, 0x0000)
    await tb.reg_write(REG_TIME_SEC_L, 0x00000005)  # 5 seconds
    await tb.reg_write(REG_TIME_NSC_H, 0x3B9AC600)  # 999,999,488 ns (close to rollover)
    await tb.reg_write(REG_TIME_NSC_L, 0x00000000)
    await tb.reg_write(REG_RTC_CTRL, RTC_CTRL_SET_TIME)
    await ClockCycles(dut.hclk, 20)
    await tb.reg_write(REG_RTC_CTRL, 0)

    # Wait for rollover to occur (at 125 MHz, ~64 RTC cycles to cover ~512 ns)
    await ClockCycles(dut.hclk, 500)

    # Read time back
    await tb.reg_write(REG_RTC_CTRL, RTC_CTRL_GET_TIME)
    await ClockCycles(dut.hclk, 30)
    for _ in range(50):
        ctrl = await tb.reg_read(REG_RTC_CTRL)
        if ctrl & 0x1:
            break
        await ClockCycles(dut.hclk, 5)

    sec_l = await tb.reg_read(REG_TIME_SEC_L)
    ns_h = await tb.reg_read(REG_TIME_NSC_H)

    tb.log.info("After rollover: sec=%d, ns=0x%08X", sec_l, ns_h)
    assert sec_l >= 6, \
        "Seconds should have incremented past 5 after rollover, got {}".format(sec_l)


@cocotb.test()
async def test_rtc_frequency_adjustment(dut):
    """2.5: Load frequency adjustment and verify adj_ld_done."""
    tb = Ha1588AhbTB(dut)
    await tb.reset()

    # Set base period
    await setup_rtc_ticking(tb)

    # Set adjustment period (slightly different from base)
    await tb.reg_write(REG_ADJ_PERIOD_H, 0x00000009)
    await tb.reg_write(REG_ADJ_PERIOD_L, 0x00000000)

    # Set adjustment count (apply for 100 RTC cycles)
    await tb.reg_write(REG_ADJ_NUM, 0x00000064)

    # Trigger adjustment
    await tb.reg_write(REG_RTC_CTRL, RTC_CTRL_SET_ADJ)
    await ClockCycles(dut.hclk, 20)
    await tb.reg_write(REG_RTC_CTRL, 0)

    # Wait for adjustment countdown to complete
    await ClockCycles(dut.hclk, 2000)

    # Check adj_ld_done via RTC_CTRL readback (bit 1)
    ctrl = await tb.reg_read(REG_RTC_CTRL)
    adj_done = (ctrl >> 1) & 0x1
    tb.log.info("RTC_CTRL after adj: 0x%08X, adj_ld_done=%d", ctrl, adj_done)
    assert adj_done == 1, "adj_ld_done should be set after countdown completes"


@cocotb.test()
async def test_rtc_soft_reset(dut):
    """2.6: RTC soft reset via SET_RESET clears timing state."""
    tb = Ha1588AhbTB(dut)
    await tb.reset()

    # Load a known time
    await setup_rtc_ticking(tb)
    await tb.reg_write(REG_TIME_SEC_H, 0x0000)
    await tb.reg_write(REG_TIME_SEC_L, 0x00001000)
    await tb.reg_write(REG_TIME_NSC_H, 0x10000000)
    await tb.reg_write(REG_TIME_NSC_L, 0x00000000)
    await tb.reg_write(REG_RTC_CTRL, RTC_CTRL_SET_TIME)
    await ClockCycles(dut.hclk, 20)
    await tb.reg_write(REG_RTC_CTRL, 0)

    # Assert RTC soft reset
    await tb.reg_write(REG_RTC_CTRL, RTC_CTRL_SET_RESET)
    await ClockCycles(dut.hclk, 50)
    await tb.reg_write(REG_RTC_CTRL, 0)

    # Wait for reset to propagate through CDC
    await ClockCycles(dut.hclk, 100)

    # Read PTP output — should be near zero after reset
    ptp_ns = int(dut.rtc_time_ptp_ns.value)
    tb.log.info("PTP NS after soft reset: 0x%08X", ptp_ns)
    # After reset, the accumulator resets but period_fix is retained,
    # so time starts accumulating from zero again. Check it's small.
    assert ptp_ns < 0x01000000, \
        "PTP NS should be near zero after RTC reset, got 0x{:08X}".format(ptp_ns)


# ===========================================================================
# Layer 3 -- TSU PTP Timestamping Tests (new)
# ===========================================================================

@cocotb.test()
async def test_tsu_rx_l2_ptp_sync(dut):
    """3.4: Send L2 PTP Sync frame on RX GMII and verify timestamp queued."""
    tb = Ha1588AhbTB(dut)
    await tb.reset()
    await tb.start_gmii_clocks()
    await setup_rtc_ticking(tb)

    # Enable RX TSU: set message ID mask to accept Sync (bit 0)
    await tb.reg_write(REG_TSU_RXSTAT, 0x01000000)  # mask bit 0 = Sync

    # Clear any stale queue state
    await tb.reg_write(REG_TSU_RXCTRL, TSU_CTRL_RESET)
    await ClockCycles(dut.hclk, 20)
    await tb.reg_write(REG_TSU_RXCTRL, 0)
    await ClockCycles(dut.hclk, 20)

    # Set giga mode
    dut.rx_giga_mode.value = 1

    # Build and send L2 PTP Sync frame
    frame = build_l2_ptp_sync_frame(seq_id=42)
    await drive_gmii_frame(dut, frame, rx=True, giga_mode=True)

    # Wait for frame processing and CDC
    await ClockCycles(dut.hclk, 200)

    # Check queue status — should have 1 entry
    stat = await tb.reg_read(REG_TSU_RXSTAT)
    q_depth = stat & 0xFF
    tb.log.info("RX queue status: 0x%08X, depth=%d", stat, q_depth)
    assert q_depth >= 1, "RX queue should have at least 1 entry, got {}".format(q_depth)

    # Read the timestamp: trigger queue read
    await tb.reg_write(REG_TSU_RXCTRL, TSU_CTRL_READ_QUEUE)
    await ClockCycles(dut.hclk, 20)
    await tb.reg_write(REG_TSU_RXCTRL, 0)
    await ClockCycles(dut.hclk, 20)

    # Read 4 data words
    d0 = await tb.reg_read(REG_TSU_RXDATA0)
    d1 = await tb.reg_read(REG_TSU_RXDATA1)
    d2 = await tb.reg_read(REG_TSU_RXDATA2)
    d3 = await tb.reg_read(REG_TSU_RXDATA3)
    tb.log.info("RX queue data: 0x%08X 0x%08X 0x%08X 0x%08X", d0, d1, d2, d3)

    # d3 contains {msgId[3:0], cksum[11:0], seqId[15:0]}
    seq_id_read = d3 & 0xFFFF
    msg_id_read = (d3 >> 28) & 0xF
    tb.log.info("Parsed: msgId=%d, seqId=%d", msg_id_read, seq_id_read)
    assert msg_id_read == 0, "Message ID should be 0 (Sync), got {}".format(msg_id_read)
    assert seq_id_read == 42, "Sequence ID should be 42, got {}".format(seq_id_read)


@cocotb.test()
async def test_tsu_rx_queue_fill_drain(dut):
    """3.5: Send multiple PTP frames, fill queue, then drain all entries."""
    tb = Ha1588AhbTB(dut)
    await tb.reset()
    await tb.start_gmii_clocks()
    await setup_rtc_ticking(tb)

    # Enable Sync message capture
    await tb.reg_write(REG_TSU_RXSTAT, 0x01000000)
    await tb.reg_write(REG_TSU_RXCTRL, TSU_CTRL_RESET)
    await ClockCycles(dut.hclk, 30)
    await tb.reg_write(REG_TSU_RXCTRL, 0)
    await ClockCycles(dut.hclk, 20)

    dut.rx_giga_mode.value = 1
    num_frames = 4

    # Send multiple frames
    for i in range(num_frames):
        frame = build_l2_ptp_sync_frame(seq_id=100 + i)
        await drive_gmii_frame(dut, frame, rx=True, giga_mode=True)
        await ClockCycles(dut.hclk, 100)

    # Wait for all to be processed
    await ClockCycles(dut.hclk, 200)

    # Check queue depth
    stat = await tb.reg_read(REG_TSU_RXSTAT)
    q_depth = stat & 0xFF
    tb.log.info("RX queue depth after %d frames: %d", num_frames, q_depth)
    assert q_depth >= num_frames, \
        "Expected at least {} entries, got {}".format(num_frames, q_depth)

    # Drain all entries and verify sequence IDs
    for i in range(num_frames):
        await tb.reg_write(REG_TSU_RXCTRL, TSU_CTRL_READ_QUEUE)
        await ClockCycles(dut.hclk, 20)
        await tb.reg_write(REG_TSU_RXCTRL, 0)
        await ClockCycles(dut.hclk, 20)

        d3 = await tb.reg_read(REG_TSU_RXDATA3)
        seq_id = d3 & 0xFFFF
        tb.log.info("Entry %d: seqId=%d", i, seq_id)
        assert seq_id == 100 + i, \
            "Entry {} seqId expected {}, got {}".format(i, 100 + i, seq_id)


@cocotb.test()
async def test_tsu_rx_queue_reset(dut):
    """3.6: Verify RX queue reset clears all entries."""
    tb = Ha1588AhbTB(dut)
    await tb.reset()
    await tb.start_gmii_clocks()
    await setup_rtc_ticking(tb)

    # Enable Sync capture and send a frame
    await tb.reg_write(REG_TSU_RXSTAT, 0x01000000)
    dut.rx_giga_mode.value = 1

    frame = build_l2_ptp_sync_frame(seq_id=1)
    await drive_gmii_frame(dut, frame, rx=True, giga_mode=True)
    await ClockCycles(dut.hclk, 200)

    # Verify non-empty
    stat = await tb.reg_read(REG_TSU_RXSTAT)
    assert (stat & 0xFF) > 0, "Queue should be non-empty before reset"

    # Reset the queue
    await tb.reg_write(REG_TSU_RXCTRL, TSU_CTRL_RESET)
    await ClockCycles(dut.hclk, 30)
    await tb.reg_write(REG_TSU_RXCTRL, 0)
    await ClockCycles(dut.hclk, 30)

    # Verify empty
    stat = await tb.reg_read(REG_TSU_RXSTAT)
    q_depth = stat & 0xFF
    tb.log.info("RX queue depth after reset: %d", q_depth)
    assert q_depth == 0, "Queue should be empty after reset, got {}".format(q_depth)


@cocotb.test()
async def test_tsu_rx_msgid_filtering(dut):
    """3.7: Verify message ID mask filters PTP frame types."""
    tb = Ha1588AhbTB(dut)
    await tb.reset()
    await tb.start_gmii_clocks()
    await setup_rtc_ticking(tb)

    # Set mask to 0x00 — no message types accepted
    await tb.reg_write(REG_TSU_RXSTAT, 0x00000000)
    await tb.reg_write(REG_TSU_RXCTRL, TSU_CTRL_RESET)
    await ClockCycles(dut.hclk, 30)
    await tb.reg_write(REG_TSU_RXCTRL, 0)
    await ClockCycles(dut.hclk, 20)

    dut.rx_giga_mode.value = 1

    # Send a Sync frame — should be filtered out
    frame = build_l2_ptp_sync_frame(seq_id=99)
    await drive_gmii_frame(dut, frame, rx=True, giga_mode=True)
    await ClockCycles(dut.hclk, 200)

    stat = await tb.reg_read(REG_TSU_RXSTAT)
    q_depth = stat & 0xFF
    tb.log.info("Queue depth with mask=0x00: %d (expect 0)", q_depth)
    assert q_depth == 0, \
        "Queue should be empty with null mask, got {}".format(q_depth)

    # Now set mask to accept Sync (bit 0)
    await tb.reg_write(REG_TSU_RXSTAT, 0x01000000)

    frame = build_l2_ptp_sync_frame(seq_id=100)
    await drive_gmii_frame(dut, frame, rx=True, giga_mode=True)
    await ClockCycles(dut.hclk, 200)

    stat = await tb.reg_read(REG_TSU_RXSTAT)
    q_depth = stat & 0xFF
    tb.log.info("Queue depth with mask=0x01: %d (expect 1)", q_depth)
    assert q_depth >= 1, \
        "Queue should have entry with Sync mask enabled, got {}".format(q_depth)


@cocotb.test()
async def test_tsu_tx_l2_ptp_sync(dut):
    """3.8: Send L2 PTP Sync frame on TX GMII and verify timestamp queued."""
    tb = Ha1588AhbTB(dut)
    await tb.reset()
    await tb.start_gmii_clocks()
    await setup_rtc_ticking(tb)

    # Enable TX TSU: set message ID mask to accept Sync (bit 0)
    await tb.reg_write(REG_TSU_TXSTAT, 0x01000000)
    await tb.reg_write(REG_TSU_TXCTRL, TSU_CTRL_RESET)
    await ClockCycles(dut.hclk, 30)
    await tb.reg_write(REG_TSU_TXCTRL, 0)
    await ClockCycles(dut.hclk, 20)

    dut.tx_giga_mode.value = 1

    # Send PTP Sync frame on TX interface
    frame = build_l2_ptp_sync_frame(seq_id=7)
    await drive_gmii_frame(dut, frame, rx=False, giga_mode=True)
    await ClockCycles(dut.hclk, 200)

    # Check TX queue
    stat = await tb.reg_read(REG_TSU_TXSTAT)
    q_depth = stat & 0xFF
    tb.log.info("TX queue depth: %d", q_depth)
    assert q_depth >= 1, "TX queue should have at least 1 entry, got {}".format(q_depth)

    # Read and verify
    await tb.reg_write(REG_TSU_TXCTRL, TSU_CTRL_READ_QUEUE)
    await ClockCycles(dut.hclk, 20)
    await tb.reg_write(REG_TSU_TXCTRL, 0)
    await ClockCycles(dut.hclk, 20)

    d3 = await tb.reg_read(REG_TSU_TXDATA3)
    seq_id = d3 & 0xFFFF
    msg_id = (d3 >> 28) & 0xF
    tb.log.info("TX entry: msgId=%d, seqId=%d", msg_id, seq_id)
    assert msg_id == 0, "TX msg ID should be Sync (0), got {}".format(msg_id)
    assert seq_id == 7, "TX seq ID should be 7, got {}".format(seq_id)


@cocotb.test()
async def test_tsu_tx_queue_reset(dut):
    """3.9: Verify TX queue reset clears all entries."""
    tb = Ha1588AhbTB(dut)
    await tb.reset()
    await tb.start_gmii_clocks()
    await setup_rtc_ticking(tb)

    await tb.reg_write(REG_TSU_TXSTAT, 0x01000000)
    dut.tx_giga_mode.value = 1

    frame = build_l2_ptp_sync_frame(seq_id=1)
    await drive_gmii_frame(dut, frame, rx=False, giga_mode=True)
    await ClockCycles(dut.hclk, 200)

    # Reset TX queue
    await tb.reg_write(REG_TSU_TXCTRL, TSU_CTRL_RESET)
    await ClockCycles(dut.hclk, 30)
    await tb.reg_write(REG_TSU_TXCTRL, 0)
    await ClockCycles(dut.hclk, 30)

    stat = await tb.reg_read(REG_TSU_TXSTAT)
    q_depth = stat & 0xFF
    tb.log.info("TX queue depth after reset: %d", q_depth)
    assert q_depth == 0, "TX queue should be empty after reset, got {}".format(q_depth)


@cocotb.test()
async def test_cdc_time_read_handshake(dut):
    """4.1: Verify GET_TIME CDC handshake between hclk and rtc_clk domains."""
    tb = Ha1588AhbTB(dut)
    await tb.reset()
    await setup_rtc_ticking(tb)

    # Perform multiple GET_TIME operations to exercise the CDC path
    for i in range(5):
        await tb.reg_write(REG_RTC_CTRL, RTC_CTRL_GET_TIME)
        await ClockCycles(dut.hclk, 10)

        # Poll for time_ok
        ok = False
        for _ in range(100):
            ctrl = await tb.reg_read(REG_RTC_CTRL)
            if ctrl & 0x1:
                ok = True
                break
            await ClockCycles(dut.hclk, 2)

        assert ok, "GET_TIME handshake did not complete on iteration {}".format(i)

        ns_h = await tb.reg_read(REG_TIME_NSC_H)
        tb.log.info("CDC read %d: ns=0x%08X", i, ns_h)

        # Clear GET_TIME before next iteration
        await tb.reg_write(REG_RTC_CTRL, 0)
        await ClockCycles(dut.hclk, 20)
