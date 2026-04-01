"""
IEEE 1588 PTP co-simulation tests for ethmac_subsystem_apb.

Validates PTP timestamping by sending real PTP Ethernet frames through the
MAC data path and verifying that the ha1588 TSU captures correct timestamps.

Architecture:
    MiiSource -> MAC RX -> DMA -> cocotb firmware -> DMA -> MAC TX -> MiiSink
                  |                                          |
                  +--- ha1588 RX TSU (passive monitor) ------+
                  |                                          |
                  +--- ha1588 TX TSU (passive monitor) ------+

Uses:
  - cocotbext-eth: MiiSource/MiiSink for frame injection/capture
  - cocotbext-ahb: AHBLiteSlaveRAM for DMA memory
  - Manual APB driver for register access to both MAC and PTP

Run with:
  make MODULE=test_ptp_cosim
  make MODULE=test_ptp_cosim TESTCASE=test_ptp_echo_delay_measurement
"""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ClockCycles, Timer, with_timeout

# Import shared infrastructure from the subsystem test
from test_ethmac_subsystem_apb import (
    SubsystemTB, apb_write, apb_read, HAS_COCOTBEXT_ETH, GmiiFrame,
    # MAC constants
    ETH_MODER, ETH_INT_SOURCE, ETH_INT_MASK,
    ETH_IPGT, ETH_IPGR1, ETH_IPGR2,
    ETH_PACKETLEN, ETH_TX_BD_NUM,
    ETH_MAC_ADDR0, ETH_MAC_ADDR1, ETH_BD_BASE,
    MODER_RXEN, MODER_TXEN, MODER_PRO, MODER_FULLD,
    MODER_CRCEN, MODER_PAD,
    TX_BD_RD, TX_BD_IRQ, TX_BD_WR, TX_BD_PAD, TX_BD_CRC,
    RX_BD_E, RX_BD_IRQ, RX_BD_WR,
    INT_TXB, INT_RXB,
    # PTP constants
    PTP_RTC_CTRL, PTP_SCRATCH,
    PTP_TIME_SEC_H, PTP_TIME_SEC_L, PTP_TIME_NSC_H, PTP_TIME_NSC_L,
    PTP_PERIOD_H, PTP_PERIOD_L,
    PTP_TSU_RXCTRL, PTP_TSU_RXSTAT, PTP_TSU_RXDATA0,
    PTP_TSU_TXCTRL, PTP_TSU_TXSTAT, PTP_TSU_TXDATA0,
    RTC_CTRL_GET_TIME, RTC_CTRL_SET_PERIOD, RTC_CTRL_SET_TIME,
    HCLK_PERIOD_NS,
)

# TSU control bits
TSU_CTRL_READ_QUEUE = (1 << 0)
TSU_CTRL_RESET      = (1 << 1)

# DMA buffer addresses
TX_BUF_ADDR = 0x0000
RX_BUF_ADDR = 0x2000
NUM_TX_BDS  = 2

# MAC address used by the simulated device
SIM_MAC = b'\x02\x00\xDE\xAD\xBE\xEF'

# PTP multicast destination MAC
PTP_DST_MAC = b'\x01\x1B\x19\x00\x00\x00'
PTP_SRC_MAC = b'\x00\x1A\x2B\x3C\x4D\x5E'


# ---------------------------------------------------------------------------
# PTP Frame Builders (payload only — MiiSource adds preamble/SFD/CRC)
# ---------------------------------------------------------------------------

def build_ptp_frame_payload(msg_type=0x00, seq_id=1, src_mac=None):
    """Build a raw L2 PTP frame payload suitable for GmiiFrame.from_payload().

    Returns bytes starting from destination MAC (no preamble/SFD/FCS).
    msg_type: 0x00=Sync, 0x01=Delay_Req, 0x02=Pdelay_Req, 0x08=Follow_Up
    """
    dst = PTP_DST_MAC
    src = src_mac or PTP_SRC_MAC
    ethertype = b'\x88\xF7'

    # PTP header (34 bytes)
    ptp_hdr = bytearray(34)
    ptp_hdr[0] = msg_type & 0x0F          # transportSpecific=0, messageType
    ptp_hdr[1] = 0x02                      # versionPTP=2
    ptp_hdr[2] = 0x00                      # messageLength MSB
    ptp_hdr[3] = 0x2C                      # messageLength=44
    # domainNumber, reserved, flags, correctionField = 0
    # sourcePortIdentity (8 bytes clockIdentity + 2 bytes portNumber)
    ptp_hdr[20] = 0x00; ptp_hdr[21] = 0x1A
    ptp_hdr[22] = 0x2B; ptp_hdr[23] = 0xFF
    ptp_hdr[24] = 0xFE; ptp_hdr[25] = 0x3C
    ptp_hdr[26] = 0x4D; ptp_hdr[27] = 0x5E
    ptp_hdr[28] = 0x00; ptp_hdr[29] = 0x01  # portNumber
    # sequenceId
    ptp_hdr[30] = (seq_id >> 8) & 0xFF
    ptp_hdr[31] = seq_id & 0xFF
    # controlField + logMessageInterval = 0
    # originTimestamp (10 bytes) = 0

    frame = dst + src + ethertype + bytes(ptp_hdr)

    # Pad to minimum 60 bytes
    if len(frame) < 60:
        frame += b'\x00' * (60 - len(frame))

    return frame


def build_ptp_vlan_payload(seq_id=1, double_tag=False):
    """Build L2 PTP Sync frame with VLAN tag(s)."""
    dst = PTP_DST_MAC
    src = PTP_SRC_MAC

    frame = bytearray(dst + src)

    if double_tag:
        frame += b'\x88\xA8'       # Outer VLAN (802.1ad)
        frame += b'\x00\x64'       # VLAN ID 100
    frame += b'\x81\x00'           # VLAN (802.1Q)
    frame += b'\x00\x0A'           # VLAN ID 10
    frame += b'\x88\xF7'           # EtherType = PTP

    # Minimal PTP Sync header
    ptp_hdr = bytearray(34)
    ptp_hdr[0] = 0x00              # Sync
    ptp_hdr[1] = 0x02
    ptp_hdr[2] = 0x00; ptp_hdr[3] = 0x2C
    ptp_hdr[20:28] = b'\x00\x1A\x2B\xFF\xFE\x3C\x4D\x5E'
    ptp_hdr[28] = 0x00; ptp_hdr[29] = 0x01
    ptp_hdr[30] = (seq_id >> 8) & 0xFF
    ptp_hdr[31] = seq_id & 0xFF
    frame += ptp_hdr

    if len(frame) < 60:
        frame += b'\x00' * (60 - len(frame))

    return bytes(frame)


# ---------------------------------------------------------------------------
# Subsystem helpers
# ---------------------------------------------------------------------------

async def setup_rtc(dut):
    """Configure RTC with 8ns period and start ticking."""
    await apb_write(dut, PTP_PERIOD_H, 0x00000008)
    await apb_write(dut, PTP_PERIOD_L, 0x00000000)
    await apb_write(dut, PTP_RTC_CTRL, RTC_CTRL_SET_PERIOD)
    await ClockCycles(dut.pclk, 20)
    await apb_write(dut, PTP_RTC_CTRL, 0)
    await ClockCycles(dut.pclk, 50)


async def setup_tsu(dut, rx_mask=0x0F, tx_mask=0x0F):
    """Reset TSU queues and set message ID masks."""
    await apb_write(dut, PTP_TSU_RXSTAT, rx_mask << 24)
    await apb_write(dut, PTP_TSU_RXCTRL, TSU_CTRL_RESET)
    await ClockCycles(dut.pclk, 30)
    await apb_write(dut, PTP_TSU_RXCTRL, 0)

    await apb_write(dut, PTP_TSU_TXSTAT, tx_mask << 24)
    await apb_write(dut, PTP_TSU_TXCTRL, TSU_CTRL_RESET)
    await ClockCycles(dut.pclk, 30)
    await apb_write(dut, PTP_TSU_TXCTRL, 0)
    await ClockCycles(dut.pclk, 20)


async def read_tsu_entry(dut, rx=True):
    """Read one entry from a TSU queue. Returns dict or None if empty."""
    stat_addr = PTP_TSU_RXSTAT if rx else PTP_TSU_TXSTAT
    ctrl_addr = PTP_TSU_RXCTRL if rx else PTP_TSU_TXCTRL
    data0_addr = PTP_TSU_RXDATA0 if rx else PTP_TSU_TXDATA0

    stat = await apb_read(dut, stat_addr)
    if (stat & 0xFF) == 0:
        return None

    # Trigger queue read
    await apb_write(dut, ctrl_addr, TSU_CTRL_READ_QUEUE)
    await ClockCycles(dut.pclk, 20)
    await apb_write(dut, ctrl_addr, 0)
    await ClockCycles(dut.pclk, 20)

    # Read 4 data words
    d0 = await apb_read(dut, data0_addr + 0x00)
    d1 = await apb_read(dut, data0_addr + 0x04)
    d2 = await apb_read(dut, data0_addr + 0x08)
    d3 = await apb_read(dut, data0_addr + 0x0C)

    # Parse: d3 = {msg_id[31:28], cksum[27:16], seq_id[15:0]}
    return {
        "d0": d0, "d1": d1, "d2": d2, "d3": d3,
        "msg_id": (d3 >> 28) & 0xF,
        "seq_id": d3 & 0xFFFF,
        "cksum": (d3 >> 16) & 0xFFF,
    }


async def configure_mac_for_ptp(dut, tb, enable_tx=True, enable_rx=True):
    """Configure the MAC for PTP frame handling. Returns MODER value."""
    await apb_write(dut, ETH_MAC_ADDR0, 0xEFBEADDE)
    await apb_write(dut, ETH_MAC_ADDR1, 0x00000002)
    await apb_write(dut, ETH_IPGT, 0x00000015)
    await apb_write(dut, ETH_IPGR1, 0x0000000C)
    await apb_write(dut, ETH_IPGR2, 0x00000012)
    await apb_write(dut, ETH_PACKETLEN, (1518 << 16) | 64)
    await apb_write(dut, ETH_TX_BD_NUM, NUM_TX_BDS)
    await apb_write(dut, ETH_INT_MASK, INT_TXB | INT_RXB)

    # Setup RX BD
    rx_bd_index = NUM_TX_BDS
    rx_bd_addr = ETH_BD_BASE + (rx_bd_index * 8)
    await apb_write(dut, rx_bd_addr, RX_BD_E | RX_BD_IRQ | RX_BD_WR)
    await apb_write(dut, rx_bd_addr + 4, RX_BUF_ADDR)

    flags = MODER_PRO | MODER_PAD | MODER_CRCEN | MODER_FULLD
    if enable_tx:
        flags |= MODER_TXEN
    if enable_rx:
        flags |= MODER_RXEN
    moder = 0x0000A000 | flags
    await apb_write(dut, ETH_MODER, moder)
    await ClockCycles(dut.pclk, 200)
    return moder


def read_rx_frame(tb):
    """Read received frame from DMA memory with word-byte-unswap."""
    rx_data = tb.dma_read_mem(RX_BUF_ADDR, 4)
    if rx_data == bytes(4):
        return None

    rx_data = tb.dma_read_mem(RX_BUF_ADDR, 1518)
    frame_len = len(rx_data)
    while frame_len > 14 and rx_data[frame_len-4:frame_len] == b'\x00\x00\x00\x00':
        frame_len -= 4
    if frame_len < 14:
        return None

    frame = bytearray()
    for i in range(0, frame_len, 4):
        w = rx_data[i:i+4]
        if len(w) == 4:
            frame.extend([w[3], w[2], w[1], w[0]])
        else:
            frame.extend(w)
    return frame


async def transmit_frame_via_mac(dut, tb, frame_bytes, moder):
    """Write frame to DMA, arm TX BD, transmit. Returns when TX BD clears."""
    rx_bd_index = NUM_TX_BDS

    # Disable MAC, arm TX BD, re-enable (TX scanner resets on TXEN 0->1)
    moder_off = moder & ~(MODER_TXEN | MODER_RXEN)
    await apb_write(dut, ETH_MODER, moder_off)
    await ClockCycles(dut.pclk, 10)

    tb.dma_write_mem(TX_BUF_ADDR, frame_bytes)

    tx_bd_addr = ETH_BD_BASE
    word0 = ((len(frame_bytes) & 0xFFFF) << 16) | TX_BD_RD | TX_BD_IRQ | TX_BD_WR | TX_BD_PAD | TX_BD_CRC
    await apb_write(dut, tx_bd_addr, word0)
    await apb_write(dut, tx_bd_addr + 4, TX_BUF_ADDR)

    # Re-arm RX BD too
    rx_bd_addr = ETH_BD_BASE + (rx_bd_index * 8)
    tb.dma_write_mem(RX_BUF_ADDR, bytes(1518))
    await apb_write(dut, rx_bd_addr, RX_BD_E | RX_BD_IRQ | RX_BD_WR)
    await apb_write(dut, rx_bd_addr + 4, RX_BUF_ADDR)

    await apb_write(dut, ETH_MODER, moder)
    await ClockCycles(dut.pclk, 200)

    # Wait for TX completion
    for _ in range(30000):
        await RisingEdge(dut.pclk)
        bd_status = await apb_read(dut, tx_bd_addr)
        if not (bd_status & TX_BD_RD):
            break

    # Clear interrupt
    await apb_write(dut, ETH_INT_SOURCE, INT_TXB)


# ===========================================================================
# Test 1: RX Timestamp Capture via MAC
# ===========================================================================

@cocotb.test()
async def test_ptp_rx_timestamp_via_mac(dut):
    """Inject PTP Sync via MiiSource, MAC receives it, ha1588 captures RX timestamp."""
    assert HAS_COCOTBEXT_ETH, "cocotbext-eth required"

    tb = SubsystemTB(dut)
    log = dut._log
    await tb.reset()

    await setup_rtc(dut)
    await setup_tsu(dut, rx_mask=0x01, tx_mask=0x01)
    moder = await configure_mac_for_ptp(dut, tb)

    # Inject PTP Sync frame
    payload = build_ptp_frame_payload(msg_type=0x00, seq_id=42)
    frame = GmiiFrame.from_payload(payload)
    await tb.mii_rx_source.send(frame)
    await Timer(30, "us")

    # Verify MAC received the frame
    rx_frame = read_rx_frame(tb)
    assert rx_frame is not None, "MAC did not receive the PTP frame"
    log.info("MAC RX: %d bytes, ethertype=0x%04X",
             len(rx_frame), int.from_bytes(rx_frame[12:14], 'big'))
    assert rx_frame[12:14] == b'\x88\xF7', "EtherType should be PTP (0x88F7)"

    # Verify ha1588 captured the RX timestamp
    entry = await read_tsu_entry(dut, rx=True)
    assert entry is not None, "RX TSU queue is empty — timestamp not captured"
    log.info("RX TSU: msg_id=%d, seq_id=%d, d0=0x%08X d1=0x%08X",
             entry["msg_id"], entry["seq_id"], entry["d0"], entry["d1"])
    assert entry["msg_id"] == 0, f"Expected Sync (0), got {entry['msg_id']}"
    assert entry["seq_id"] == 42, f"Expected seq_id=42, got {entry['seq_id']}"


# ===========================================================================
# Test 2: TX Timestamp Capture via MAC
# ===========================================================================

@cocotb.test()
async def test_ptp_tx_timestamp_via_mac(dut):
    """Transmit PTP Sync via MAC, ha1588 captures TX timestamp."""
    assert HAS_COCOTBEXT_ETH, "cocotbext-eth required"

    tb = SubsystemTB(dut)
    log = dut._log
    await tb.reset()

    await setup_rtc(dut)
    await setup_tsu(dut, rx_mask=0x01, tx_mask=0x01)
    moder = await configure_mac_for_ptp(dut, tb)

    # Transmit PTP Sync frame
    payload = build_ptp_frame_payload(msg_type=0x00, seq_id=55)
    await transmit_frame_via_mac(dut, tb, payload, moder)
    await Timer(20, "us")

    # Verify ha1588 captured the TX timestamp
    entry = await read_tsu_entry(dut, rx=False)
    assert entry is not None, "TX TSU queue is empty — timestamp not captured"
    log.info("TX TSU: msg_id=%d, seq_id=%d", entry["msg_id"], entry["seq_id"])
    assert entry["msg_id"] == 0
    assert entry["seq_id"] == 55


# ===========================================================================
# Test 3: PTP Echo with Delay Measurement
# ===========================================================================

@cocotb.test()
async def test_ptp_echo_delay_measurement(dut):
    """Full PTP delay measurement: Sync RX -> Delay_Req TX -> compare timestamps.

    This is the core IEEE 1588 co-simulation test. It exercises:
    1. RX path: PTP Sync arrives via MII, MAC DMA writes to memory,
       ha1588 captures RX timestamp (t2)
    2. TX path: cocotb firmware builds Delay_Req, writes to DMA,
       MAC transmits on MII, ha1588 captures TX timestamp (t3)
    3. Delay computation: t3 - t2 should be positive and represent the
       echo turnaround time through the MAC firmware
    """
    assert HAS_COCOTBEXT_ETH, "cocotbext-eth required"

    tb = SubsystemTB(dut)
    log = dut._log
    await tb.reset()

    # Configure RTC with known start time
    await setup_rtc(dut)
    await apb_write(dut, PTP_TIME_SEC_H, 0x0000)
    await apb_write(dut, PTP_TIME_SEC_L, 0x0000000A)  # 10 seconds
    await apb_write(dut, PTP_TIME_NSC_H, 0x00000000)
    await apb_write(dut, PTP_TIME_NSC_L, 0x00000000)
    await apb_write(dut, PTP_RTC_CTRL, RTC_CTRL_SET_TIME)
    await ClockCycles(dut.pclk, 20)
    await apb_write(dut, PTP_RTC_CTRL, 0)
    await ClockCycles(dut.pclk, 50)

    # Mask: accept Sync (0) on RX, Delay_Req (1) on TX
    await setup_tsu(dut, rx_mask=0x01, tx_mask=0x02)
    moder = await configure_mac_for_ptp(dut, tb)

    # Step 1: Inject PTP Sync frame (simulating a PTP Grandmaster)
    sync_payload = build_ptp_frame_payload(msg_type=0x00, seq_id=100)
    frame = GmiiFrame.from_payload(sync_payload)
    await tb.mii_rx_source.send(frame)
    await Timer(30, "us")

    # Step 2: Read RX timestamp (t2)
    rx_entry = await read_tsu_entry(dut, rx=True)
    assert rx_entry is not None, "RX TSU: no Sync timestamp captured"
    log.info("t2 (RX Sync): msg_id=%d, seq_id=%d, d0=0x%08X d1=0x%08X d2=0x%08X",
             rx_entry["msg_id"], rx_entry["seq_id"],
             rx_entry["d0"], rx_entry["d1"], rx_entry["d2"])

    # Step 3: Read received frame from MAC DMA
    rx_frame = read_rx_frame(tb)
    assert rx_frame is not None, "MAC did not receive the Sync frame"

    # Step 4: Build Delay_Req response (change msg_type and seq_id)
    delay_req = build_ptp_frame_payload(msg_type=0x01, seq_id=200,
                                         src_mac=SIM_MAC)

    # Step 5: Transmit Delay_Req via MAC
    await transmit_frame_via_mac(dut, tb, delay_req, moder)
    await Timer(20, "us")

    # Step 6: Read TX timestamp (t3)
    tx_entry = await read_tsu_entry(dut, rx=False)
    assert tx_entry is not None, "TX TSU: no Delay_Req timestamp captured"
    log.info("t3 (TX Delay_Req): msg_id=%d, seq_id=%d, d0=0x%08X d1=0x%08X d2=0x%08X",
             tx_entry["msg_id"], tx_entry["seq_id"],
             tx_entry["d0"], tx_entry["d1"], tx_entry["d2"])

    # Step 7: Verify protocol fields
    assert rx_entry["msg_id"] == 0, "RX should be Sync (0)"
    assert rx_entry["seq_id"] == 100, "RX seq_id mismatch"
    assert tx_entry["msg_id"] == 1, "TX should be Delay_Req (1)"
    assert tx_entry["seq_id"] == 200, "TX seq_id mismatch"

    # Step 8: Verify timestamp ordering (t3 > t2 since TX happened after RX)
    # Compare d1 (upper timestamp) then d2 (lower timestamp)
    rx_ts = (rx_entry["d1"] << 32) | rx_entry["d2"]
    tx_ts = (tx_entry["d1"] << 32) | tx_entry["d2"]
    log.info("RX timestamp: 0x%016X", rx_ts)
    log.info("TX timestamp: 0x%016X", tx_ts)
    assert tx_ts > rx_ts, \
        f"TX timestamp (0x{tx_ts:016X}) should be > RX timestamp (0x{rx_ts:016X})"

    log.info("PTP echo delay measurement: t3 - t2 = 0x%016X", tx_ts - rx_ts)
    log.info("=== PTP Echo Delay Measurement PASSED ===")


# ===========================================================================
# Test 4: Multiple PTP Message Types
# ===========================================================================

@cocotb.test()
async def test_ptp_multi_message_types(dut):
    """Send Sync and Delay_Req, verify both captured with correct msg_id."""
    assert HAS_COCOTBEXT_ETH, "cocotbext-eth required"

    tb = SubsystemTB(dut)
    log = dut._log
    await tb.reset()

    await setup_rtc(dut)
    await setup_tsu(dut, rx_mask=0x03, tx_mask=0x03)  # Accept Sync + Delay_Req
    moder = await configure_mac_for_ptp(dut, tb)

    # Send Sync (msg_type=0)
    sync = GmiiFrame.from_payload(build_ptp_frame_payload(0x00, seq_id=1))
    await tb.mii_rx_source.send(sync)
    await Timer(30, "us")

    # Re-arm RX BD for second frame
    rx_bd_addr = ETH_BD_BASE + (NUM_TX_BDS * 8)
    tb.dma_write_mem(RX_BUF_ADDR, bytes(1518))
    await apb_write(dut, rx_bd_addr, RX_BD_E | RX_BD_IRQ | RX_BD_WR)
    await apb_write(dut, rx_bd_addr + 4, RX_BUF_ADDR)

    # Send Delay_Req (msg_type=1)
    dreq = GmiiFrame.from_payload(build_ptp_frame_payload(0x01, seq_id=2))
    await tb.mii_rx_source.send(dreq)
    await Timer(30, "us")

    # Read both entries
    e1 = await read_tsu_entry(dut, rx=True)
    e2 = await read_tsu_entry(dut, rx=True)

    assert e1 is not None, "First TSU entry missing"
    assert e2 is not None, "Second TSU entry missing"

    log.info("Entry 1: msg_id=%d, seq_id=%d", e1["msg_id"], e1["seq_id"])
    log.info("Entry 2: msg_id=%d, seq_id=%d", e2["msg_id"], e2["seq_id"])

    assert e1["msg_id"] == 0 and e1["seq_id"] == 1, "First should be Sync seq=1"
    assert e2["msg_id"] == 1 and e2["seq_id"] == 2, "Second should be Delay_Req seq=2"


# ===========================================================================
# Test 5: VLAN-tagged PTP Timestamp
# ===========================================================================

@cocotb.test()
async def test_ptp_vlan_tagged_timestamp(dut):
    """Inject VLAN-tagged PTP Sync, verify ha1588 captures through tags."""
    assert HAS_COCOTBEXT_ETH, "cocotbext-eth required"

    tb = SubsystemTB(dut)
    log = dut._log
    await tb.reset()

    await setup_rtc(dut)
    await setup_tsu(dut, rx_mask=0x01, tx_mask=0x01)
    moder = await configure_mac_for_ptp(dut, tb)

    # Single VLAN-tagged PTP Sync
    payload = build_ptp_vlan_payload(seq_id=77, double_tag=False)
    frame = GmiiFrame.from_payload(payload)
    await tb.mii_rx_source.send(frame)
    await Timer(30, "us")

    entry = await read_tsu_entry(dut, rx=True)
    assert entry is not None, "VLAN PTP frame not timestamped"
    log.info("VLAN TSU: msg_id=%d, seq_id=%d", entry["msg_id"], entry["seq_id"])
    assert entry["msg_id"] == 0
    assert entry["seq_id"] == 77


# ===========================================================================
# Test 6: Timestamp Monotonicity
# ===========================================================================

@cocotb.test()
async def test_ptp_timestamp_monotonicity(dut):
    """Send multiple PTP frames, verify timestamps are strictly increasing."""
    assert HAS_COCOTBEXT_ETH, "cocotbext-eth required"

    tb = SubsystemTB(dut)
    log = dut._log
    await tb.reset()

    await setup_rtc(dut)
    await setup_tsu(dut, rx_mask=0x01, tx_mask=0x01)
    moder = await configure_mac_for_ptp(dut, tb)

    num_frames = 4
    rx_bd_addr = ETH_BD_BASE + (NUM_TX_BDS * 8)

    for i in range(num_frames):
        payload = build_ptp_frame_payload(msg_type=0x00, seq_id=10 + i)
        frame = GmiiFrame.from_payload(payload)
        await tb.mii_rx_source.send(frame)
        await Timer(30, "us")

        # Re-arm RX BD for next frame
        tb.dma_write_mem(RX_BUF_ADDR, bytes(1518))
        await apb_write(dut, rx_bd_addr, RX_BD_E | RX_BD_IRQ | RX_BD_WR)
        await apb_write(dut, rx_bd_addr + 4, RX_BUF_ADDR)

    # Read all entries and verify monotonicity
    prev_ts = 0
    for i in range(num_frames):
        entry = await read_tsu_entry(dut, rx=True)
        assert entry is not None, f"TSU entry {i} missing"
        ts = (entry["d1"] << 32) | entry["d2"]
        log.info("Frame %d: seq_id=%d, ts=0x%016X", i, entry["seq_id"], ts)
        assert entry["seq_id"] == 10 + i
        assert ts > prev_ts, f"Timestamp {i} not monotonically increasing"
        prev_ts = ts


# ===========================================================================
# Test 7: 1-PPS During Frame Traffic
# ===========================================================================

@cocotb.test()
async def test_ptp_1pps_during_traffic(dut):
    """Verify 1-PPS fires during active PTP frame traffic."""
    assert HAS_COCOTBEXT_ETH, "cocotbext-eth required"

    tb = SubsystemTB(dut)
    log = dut._log
    await tb.reset()

    await setup_rtc(dut)

    # Load time near 1-second boundary
    await apb_write(dut, PTP_TIME_SEC_L, 0x00000000)
    await apb_write(dut, PTP_TIME_NSC_H, 0x3B9AC600)  # ~999,999,488 ns
    await apb_write(dut, PTP_TIME_NSC_L, 0x00000000)
    await apb_write(dut, PTP_RTC_CTRL, RTC_CTRL_SET_TIME)
    await ClockCycles(dut.pclk, 20)
    await apb_write(dut, PTP_RTC_CTRL, 0)

    await setup_tsu(dut, rx_mask=0x01, tx_mask=0x01)
    moder = await configure_mac_for_ptp(dut, tb)

    # Inject a PTP frame while waiting for 1-PPS
    payload = build_ptp_frame_payload(msg_type=0x00, seq_id=888)
    frame = GmiiFrame.from_payload(payload)
    await tb.mii_rx_source.send(frame)

    # Watch for 1-PPS
    pps_seen = False
    for _ in range(20000):
        await RisingEdge(dut.pclk)
        if int(dut.rtc_time_one_pps.value) == 1:
            pps_seen = True
            break

    assert pps_seen, "1-PPS not observed during traffic"

    # Also verify the PTP frame was timestamped
    await Timer(10, "us")
    entry = await read_tsu_entry(dut, rx=True)
    assert entry is not None, "PTP frame not timestamped during 1-PPS"
    log.info("1-PPS verified + PTP timestamp captured (seq=%d)", entry["seq_id"])


# ===========================================================================
# Test 8: Full Loopback Sequence with Timestamps
# ===========================================================================

@cocotb.test()
async def test_ptp_full_loopback_sequence(dut):
    """Full end-to-end: Sync RX -> timestamp -> echo Delay_Req TX -> timestamp.
    Then second Sync -> verify all timestamps ordered and seq_ids correct.
    """
    assert HAS_COCOTBEXT_ETH, "cocotbext-eth required"

    tb = SubsystemTB(dut)
    log = dut._log
    await tb.reset()

    await setup_rtc(dut)
    await setup_tsu(dut, rx_mask=0x03, tx_mask=0x03)
    moder = await configure_mac_for_ptp(dut, tb)

    rx_bd_addr = ETH_BD_BASE + (NUM_TX_BDS * 8)

    # --- Round 1: Sync RX -> Delay_Req TX ---
    sync1 = GmiiFrame.from_payload(build_ptp_frame_payload(0x00, seq_id=1))
    await tb.mii_rx_source.send(sync1)
    await Timer(30, "us")

    rx1 = await read_tsu_entry(dut, rx=True)
    assert rx1 is not None and rx1["seq_id"] == 1
    log.info("Round 1 RX: Sync seq=1, msg_id=%d", rx1["msg_id"])

    # Echo as Delay_Req
    dreq1 = build_ptp_frame_payload(0x01, seq_id=101, src_mac=SIM_MAC)
    await transmit_frame_via_mac(dut, tb, dreq1, moder)
    await Timer(20, "us")

    tx1 = await read_tsu_entry(dut, rx=False)
    assert tx1 is not None and tx1["seq_id"] == 101
    log.info("Round 1 TX: Delay_Req seq=101, msg_id=%d", tx1["msg_id"])

    # --- Round 2: Second Sync RX -> second Delay_Req TX ---
    sync2 = GmiiFrame.from_payload(build_ptp_frame_payload(0x00, seq_id=2))
    await tb.mii_rx_source.send(sync2)
    await Timer(30, "us")

    rx2 = await read_tsu_entry(dut, rx=True)
    assert rx2 is not None and rx2["seq_id"] == 2
    log.info("Round 2 RX: Sync seq=2, msg_id=%d", rx2["msg_id"])

    dreq2 = build_ptp_frame_payload(0x01, seq_id=102, src_mac=SIM_MAC)
    await transmit_frame_via_mac(dut, tb, dreq2, moder)
    await Timer(20, "us")

    tx2 = await read_tsu_entry(dut, rx=False)
    assert tx2 is not None and tx2["seq_id"] == 102
    log.info("Round 2 TX: Delay_Req seq=102, msg_id=%d", tx2["msg_id"])

    # --- Verify timestamp ordering across all 4 events ---
    rx1_ts = (rx1["d1"] << 32) | rx1["d2"]
    tx1_ts = (tx1["d1"] << 32) | tx1["d2"]
    rx2_ts = (rx2["d1"] << 32) | rx2["d2"]
    tx2_ts = (tx2["d1"] << 32) | tx2["d2"]

    log.info("Timestamp ordering:")
    log.info("  t1 (RX Sync 1):      0x%016X", rx1_ts)
    log.info("  t2 (TX Delay_Req 1): 0x%016X", tx1_ts)
    log.info("  t3 (RX Sync 2):      0x%016X", rx2_ts)
    log.info("  t4 (TX Delay_Req 2): 0x%016X", tx2_ts)

    assert tx1_ts > rx1_ts, "t2 should be after t1"
    assert rx2_ts > tx1_ts, "t3 should be after t2"
    assert tx2_ts > rx2_ts, "t4 should be after t3"

    log.info("=== Full PTP Loopback Sequence PASSED ===")
    log.info("  Round 1 delay: 0x%016X", tx1_ts - rx1_ts)
    log.info("  Round 2 delay: 0x%016X", tx2_ts - rx2_ts)
