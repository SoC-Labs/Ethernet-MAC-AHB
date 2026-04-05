"""Cocotb testbench for ptp_event_detector.

Tests the lightweight MII PTP frame detector that monitors for
EtherType 0x88F7 and generates a single-cycle pulse.
"""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ClockCycles, FallingEdge

MII_CLK_PERIOD_NS = 40  # 25 MHz MII clock


# ── Helpers ──────────────────────────────────────────────────────────────────

async def setup(dut):
    cocotb.start_soon(Clock(dut.clk, MII_CLK_PERIOD_NS, units="ns").start())
    dut.mii_dv.value   = 0
    dut.mii_data.value  = 0


async def do_reset(dut):
    dut.resetn.value = 0
    await ClockCycles(dut.clk, 5)
    dut.resetn.value = 1
    await ClockCycles(dut.clk, 2)


async def send_nibble(dut, nibble):
    """Drive one MII nibble on a rising edge."""
    dut.mii_data.value = nibble & 0xF
    await RisingEdge(dut.clk)


async def send_mii_frame(dut, ethertype, payload_len=10):
    """Send a minimal Ethernet frame with a given EtherType over MII.

    Frame structure (nibble by nibble):
    - Preamble: 14 nibbles of 0x5
    - SFD: 1 nibble of 0xD
    - Dest MAC: 12 nibbles (6 bytes, all 0xFF for broadcast)
    - Src MAC: 12 nibbles (6 bytes, all 0x00)
    - EtherType: 4 nibbles (low nibble first per byte)
    - Payload: payload_len bytes (2*payload_len nibbles)
    """
    dut.mii_dv.value = 1

    # Preamble (7 bytes = 14 nibbles of 0x5)
    for _ in range(14):
        await send_nibble(dut, 0x5)

    # SFD
    await send_nibble(dut, 0xD)

    # Dest MAC: FF:FF:FF:FF:FF:FF (broadcast)
    for _ in range(6):
        await send_nibble(dut, 0xF)  # low nibble
        await send_nibble(dut, 0xF)  # high nibble

    # Src MAC: 00:00:00:00:00:00
    for _ in range(6):
        await send_nibble(dut, 0x0)  # low nibble
        await send_nibble(dut, 0x0)  # high nibble

    # EtherType (2 bytes, MII sends low nibble first per byte)
    et_hi = (ethertype >> 8) & 0xFF
    et_lo = ethertype & 0xFF
    await send_nibble(dut, et_hi & 0xF)         # byte 0 low nibble
    await send_nibble(dut, (et_hi >> 4) & 0xF)  # byte 0 high nibble
    await send_nibble(dut, et_lo & 0xF)          # byte 1 low nibble
    await send_nibble(dut, (et_lo >> 4) & 0xF)   # byte 1 high nibble

    # Payload
    for i in range(payload_len):
        await send_nibble(dut, (i & 0xF))
        await send_nibble(dut, ((i >> 4) & 0xF))

    # End frame
    dut.mii_dv.value = 0
    dut.mii_data.value = 0
    await ClockCycles(dut.clk, 2)


async def monitor_ptp_event(dut, cycle_count):
    """Monitor ptp_event output for cycle_count clocks, return True if it pulsed."""
    for _ in range(cycle_count):
        await RisingEdge(dut.clk)
        if int(dut.ptp_event.value) == 1:
            return True
    return False


# ══════════════════════════════════════════════════════════════════════════════
# Tests
# ══════════════════════════════════════════════════════════════════════════════


@cocotb.test()
async def test_det_01_reset_idle(dut):
    """DET-01: ptp_event is 0 after reset with no frame."""
    await setup(dut)
    await do_reset(dut)
    await ClockCycles(dut.clk, 10)
    assert int(dut.ptp_event.value) == 0


@cocotb.test()
async def test_det_02_ptp_frame_detected(dut):
    """DET-02: PTP frame (EtherType 0x88F7) generates ptp_event pulse."""
    await setup(dut)
    await do_reset(dut)

    # Start monitoring in background
    event_monitor = cocotb.start_soon(monitor_ptp_event(dut, 200))

    # Send PTP frame
    await send_mii_frame(dut, ethertype=0x88F7)

    # Check if event was detected
    detected = event_monitor.result()
    assert detected, "ptp_event should pulse for PTP EtherType 0x88F7"


@cocotb.test()
async def test_det_03_non_ptp_no_event(dut):
    """DET-03: Non-PTP frame does NOT generate ptp_event."""
    await setup(dut)
    await do_reset(dut)

    event_seen = False

    async def watch_event():
        nonlocal event_seen
        for _ in range(200):
            await RisingEdge(dut.clk)
            if int(dut.ptp_event.value) == 1:
                event_seen = True

    watcher = cocotb.start_soon(watch_event())

    # ARP frame (EtherType 0x0806)
    await send_mii_frame(dut, ethertype=0x0806)
    await ClockCycles(dut.clk, 10)

    assert not event_seen, "ptp_event should NOT pulse for ARP EtherType 0x0806"


@cocotb.test()
async def test_det_04_ipv4_no_event(dut):
    """DET-04: IPv4 frame does NOT generate ptp_event."""
    await setup(dut)
    await do_reset(dut)

    event_seen = False

    async def watch_event():
        nonlocal event_seen
        for _ in range(200):
            await RisingEdge(dut.clk)
            if int(dut.ptp_event.value) == 1:
                event_seen = True

    watcher = cocotb.start_soon(watch_event())

    # IPv4 frame (EtherType 0x0800)
    await send_mii_frame(dut, ethertype=0x0800)
    await ClockCycles(dut.clk, 10)

    assert not event_seen, "ptp_event should NOT pulse for IPv4 EtherType 0x0800"


@cocotb.test()
async def test_det_05_event_is_single_cycle(dut):
    """DET-05: ptp_event pulse is exactly one clock cycle wide."""
    await setup(dut)
    await do_reset(dut)

    pulse_count = 0

    async def count_pulses():
        nonlocal pulse_count
        for _ in range(200):
            await RisingEdge(dut.clk)
            if int(dut.ptp_event.value) == 1:
                pulse_count += 1

    counter = cocotb.start_soon(count_pulses())

    await send_mii_frame(dut, ethertype=0x88F7)
    await ClockCycles(dut.clk, 10)

    assert pulse_count == 1, f"Expected exactly 1 pulse cycle, got {pulse_count}"


@cocotb.test()
async def test_det_06_back_to_back_frames(dut):
    """DET-06: Detector correctly handles back-to-back PTP frames."""
    await setup(dut)
    await do_reset(dut)

    pulse_count = 0

    async def count_pulses():
        nonlocal pulse_count
        for _ in range(500):
            await RisingEdge(dut.clk)
            if int(dut.ptp_event.value) == 1:
                pulse_count += 1

    counter = cocotb.start_soon(count_pulses())

    # Send two PTP frames back-to-back
    await send_mii_frame(dut, ethertype=0x88F7, payload_len=5)
    await ClockCycles(dut.clk, 5)  # IFG
    await send_mii_frame(dut, ethertype=0x88F7, payload_len=5)
    await ClockCycles(dut.clk, 10)

    assert pulse_count == 2, f"Expected 2 pulses for 2 PTP frames, got {pulse_count}"


@cocotb.test()
async def test_det_07_mixed_frames(dut):
    """DET-07: Only PTP frames trigger events among mixed traffic."""
    await setup(dut)
    await do_reset(dut)

    pulse_count = 0

    async def count_pulses():
        nonlocal pulse_count
        for _ in range(800):
            await RisingEdge(dut.clk)
            if int(dut.ptp_event.value) == 1:
                pulse_count += 1

    counter = cocotb.start_soon(count_pulses())

    # Non-PTP, PTP, Non-PTP, PTP
    await send_mii_frame(dut, ethertype=0x0800, payload_len=5)
    await ClockCycles(dut.clk, 5)
    await send_mii_frame(dut, ethertype=0x88F7, payload_len=5)
    await ClockCycles(dut.clk, 5)
    await send_mii_frame(dut, ethertype=0x0806, payload_len=5)
    await ClockCycles(dut.clk, 5)
    await send_mii_frame(dut, ethertype=0x88F7, payload_len=5)
    await ClockCycles(dut.clk, 10)

    assert pulse_count == 2, f"Expected 2 PTP events among mixed traffic, got {pulse_count}"


@cocotb.test()
async def test_det_08_runt_frame_no_event(dut):
    """DET-08: Frame ending before EtherType does not trigger event."""
    await setup(dut)
    await do_reset(dut)

    event_seen = False

    async def watch_event():
        nonlocal event_seen
        for _ in range(100):
            await RisingEdge(dut.clk)
            if int(dut.ptp_event.value) == 1:
                event_seen = True

    watcher = cocotb.start_soon(watch_event())

    # Send partial frame (preamble + SFD + only 10 nibbles then drop dv)
    dut.mii_dv.value = 1
    for _ in range(14):
        await send_nibble(dut, 0x5)
    await send_nibble(dut, 0xD)
    for _ in range(10):
        await send_nibble(dut, 0x0)
    dut.mii_dv.value = 0
    await ClockCycles(dut.clk, 10)

    assert not event_seen, "Runt frame should not trigger ptp_event"
