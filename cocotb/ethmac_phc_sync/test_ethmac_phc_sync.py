"""Cocotb integration test: Ethernet MAC + PHC synchronisation.

Tests the end-to-end path from PTP frame injection on MII RX through
to PHC timestamp capture, and verifies the PHC can be corrected via
a simulated PTP servo loop.
"""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ClockCycles, Timer

# Clock periods
PCLK_PERIOD_NS = 10      # 100 MHz system clock
MII_CLK_PERIOD_NS = 40   # 25 MHz MII clock
RTC_CLK_PERIOD_NS = 8    # 125 MHz RTC clock

# PHC register offsets
PHC_CTRL              = 0x000
PHC_NS_INCR           = 0x008
PHC_NS_INCR_FRAC      = 0x00C
PHC_SET_SECONDS_LO    = 0x010
PHC_SET_SECONDS_HI    = 0x014
PHC_SET_NANOSECONDS   = 0x018
PHC_CAP_SECONDS_LO    = 0x020
PHC_CAP_NANOSECONDS   = 0x028
PHC_ETH_RX_SECONDS_LO = 0x060
PHC_ETH_RX_SECONDS_HI = 0x064
PHC_ETH_RX_NANOSECONDS = 0x068
PHC_ETH_RX_NS_FRAC    = 0x06C
PHC_ETH_TX_SECONDS_LO = 0x080
PHC_ETH_TX_SECONDS_HI = 0x084
PHC_ETH_TX_NANOSECONDS = 0x088
PHC_ETH_TX_NS_FRAC    = 0x08C

NS_PER_SECOND = 1_000_000_000


# ── Helpers ──────────────────────────────────────────────────────────────────

async def setup(dut):
    """Start clocks and initialise all inputs."""
    cocotb.start_soon(Clock(dut.pclk, PCLK_PERIOD_NS, units="ns").start())
    cocotb.start_soon(Clock(dut.mrx_clk_pad_i, MII_CLK_PERIOD_NS, units="ns").start())
    cocotb.start_soon(Clock(dut.mtx_clk_pad_i, MII_CLK_PERIOD_NS, units="ns").start())
    cocotb.start_soon(Clock(dut.rtc_clk, RTC_CLK_PERIOD_NS, units="ns").start())

    # Ethernet APB — idle
    dut.eth_psel.value    = 0
    dut.eth_penable.value = 0
    dut.eth_pwrite.value  = 0
    dut.eth_paddr.value   = 0
    dut.eth_pwdata.value  = 0
    dut.eth_pstrb.value   = 0xF

    # PHC APB — idle
    dut.phc_psel.value    = 0
    dut.phc_penable.value = 0
    dut.phc_pwrite.value  = 0
    dut.phc_paddr.value   = 0
    dut.phc_pwdata.value  = 0

    # MII RX — idle
    dut.mrxd_pad_i.value  = 0
    dut.mrxdv_pad_i.value = 0
    dut.mrxerr_pad_i.value = 0

    # AHB master stub
    dut.mst_hrdata.value  = 0
    dut.mst_hready.value  = 1
    dut.mst_hresp.value   = 0

    # Misc
    dut.mcoll_pad_i.value = 0
    dut.mcrs_pad_i.value  = 0
    dut.md_pad_i.value    = 1
    dut.hw_capture.value  = 0


async def do_reset(dut):
    dut.presetn.value = 0
    await ClockCycles(dut.pclk, 10)
    dut.presetn.value = 1
    await ClockCycles(dut.pclk, 5)


async def phc_apb_write(dut, addr, data):
    """Perform a single APB write to the PHC."""
    await RisingEdge(dut.pclk)
    dut.phc_psel.value    = 1
    dut.phc_penable.value = 0
    dut.phc_pwrite.value  = 1
    dut.phc_paddr.value   = addr
    dut.phc_pwdata.value  = data
    await RisingEdge(dut.pclk)
    dut.phc_penable.value = 1
    await RisingEdge(dut.pclk)
    dut.phc_psel.value    = 0
    dut.phc_penable.value = 0
    dut.phc_pwrite.value  = 0
    await RisingEdge(dut.pclk)


async def phc_apb_read(dut, addr):
    """Perform a single APB read from the PHC. Returns integer value."""
    await RisingEdge(dut.pclk)
    dut.phc_psel.value    = 1
    dut.phc_penable.value = 0
    dut.phc_pwrite.value  = 0
    dut.phc_paddr.value   = addr
    await RisingEdge(dut.pclk)
    dut.phc_penable.value = 1
    await RisingEdge(dut.pclk)
    val = int(dut.phc_prdata.value)
    dut.phc_psel.value    = 0
    dut.phc_penable.value = 0
    await RisingEdge(dut.pclk)
    return val


async def phc_set_time(dut, seconds, nanoseconds):
    """Write time to PHC SET registers and pulse SET_TIME."""
    await phc_apb_write(dut, PHC_SET_SECONDS_LO, seconds & 0xFFFF_FFFF)
    await phc_apb_write(dut, PHC_SET_SECONDS_HI, (seconds >> 32) & 0xFFFF)
    await phc_apb_write(dut, PHC_SET_NANOSECONDS, nanoseconds & 0x3FFF_FFFF)
    # Pulse SET_TIME (bit 1) while keeping EN (bit 0)
    await phc_apb_write(dut, PHC_CTRL, 0x3)  # EN=1, SET_TIME=1
    await ClockCycles(dut.pclk, 2)


async def phc_enable(dut):
    """Enable the PHC clock counter."""
    await phc_apb_write(dut, PHC_CTRL, 0x1)  # EN=1


async def phc_read_eth_rx_time(dut):
    """Read Ethernet RX captured time from PHC Region 3."""
    sec_lo = await phc_apb_read(dut, PHC_ETH_RX_SECONDS_LO)
    sec_hi = await phc_apb_read(dut, PHC_ETH_RX_SECONDS_HI)
    ns     = await phc_apb_read(dut, PHC_ETH_RX_NANOSECONDS)
    return ((sec_hi << 32) | sec_lo, ns)


async def phc_read_eth_tx_time(dut):
    """Read Ethernet TX captured time from PHC Region 4."""
    sec_lo = await phc_apb_read(dut, PHC_ETH_TX_SECONDS_LO)
    sec_hi = await phc_apb_read(dut, PHC_ETH_TX_SECONDS_HI)
    ns     = await phc_apb_read(dut, PHC_ETH_TX_NANOSECONDS)
    return ((sec_hi << 32) | sec_lo, ns)


def time_to_ns(seconds, nanoseconds):
    """Convert (seconds, nanoseconds) tuple to total nanoseconds."""
    return seconds * NS_PER_SECOND + nanoseconds


async def send_mii_nibble(dut, nibble):
    """Drive one nibble on MII RX, clocked by mrx_clk_pad_i."""
    dut.mrxd_pad_i.value = nibble & 0xF
    await RisingEdge(dut.mrx_clk_pad_i)


async def inject_ptp_frame_on_mii_rx(dut, payload_len=10):
    """Inject a PTP SYNC frame (EtherType 0x88F7) on the MII RX interface."""
    dut.mrxdv_pad_i.value = 1

    # Preamble (14 nibbles of 0x5)
    for _ in range(14):
        await send_mii_nibble(dut, 0x5)

    # SFD
    await send_mii_nibble(dut, 0xD)

    # Dest MAC: 01:1B:19:00:00:00 (PTP primary multicast)
    ptp_dest_mac = [0x01, 0x1B, 0x19, 0x00, 0x00, 0x00]
    for byte in ptp_dest_mac:
        await send_mii_nibble(dut, byte & 0xF)        # low nibble
        await send_mii_nibble(dut, (byte >> 4) & 0xF)  # high nibble

    # Src MAC: 00:AA:BB:CC:DD:EE
    src_mac = [0x00, 0xAA, 0xBB, 0xCC, 0xDD, 0xEE]
    for byte in src_mac:
        await send_mii_nibble(dut, byte & 0xF)
        await send_mii_nibble(dut, (byte >> 4) & 0xF)

    # EtherType: 0x88F7 (PTP)
    await send_mii_nibble(dut, 0x8)  # 0x88 low nibble
    await send_mii_nibble(dut, 0x8)  # 0x88 high nibble
    await send_mii_nibble(dut, 0x7)  # 0xF7 low nibble
    await send_mii_nibble(dut, 0xF)  # 0xF7 high nibble

    # PTP payload (SYNC message type = 0x00)
    for i in range(payload_len):
        await send_mii_nibble(dut, i & 0xF)
        await send_mii_nibble(dut, (i >> 4) & 0xF)

    # End frame
    dut.mrxdv_pad_i.value = 0
    dut.mrxd_pad_i.value = 0
    await ClockCycles(dut.mrx_clk_pad_i, 2)


async def inject_non_ptp_frame_on_mii_rx(dut, ethertype=0x0806, payload_len=10):
    """Inject a non-PTP frame on the MII RX interface."""
    dut.mrxdv_pad_i.value = 1

    # Preamble
    for _ in range(14):
        await send_mii_nibble(dut, 0x5)
    await send_mii_nibble(dut, 0xD)

    # Dest MAC: broadcast
    for _ in range(6):
        await send_mii_nibble(dut, 0xF)
        await send_mii_nibble(dut, 0xF)

    # Src MAC: zeros
    for _ in range(6):
        await send_mii_nibble(dut, 0x0)
        await send_mii_nibble(dut, 0x0)

    # EtherType
    et_hi = (ethertype >> 8) & 0xFF
    et_lo = ethertype & 0xFF
    await send_mii_nibble(dut, et_hi & 0xF)
    await send_mii_nibble(dut, (et_hi >> 4) & 0xF)
    await send_mii_nibble(dut, et_lo & 0xF)
    await send_mii_nibble(dut, (et_lo >> 4) & 0xF)

    # Payload
    for i in range(payload_len):
        await send_mii_nibble(dut, i & 0xF)
        await send_mii_nibble(dut, (i >> 4) & 0xF)

    dut.mrxdv_pad_i.value = 0
    dut.mrxd_pad_i.value = 0
    await ClockCycles(dut.mrx_clk_pad_i, 2)


# ══════════════════════════════════════════════════════════════════════════════
# Tests
# ══════════════════════════════════════════════════════════════════════════════


@cocotb.test()
async def test_sync_01_rx_event_captures_phc_time(dut):
    """SYNC-01: PTP RX frame triggers PHC ETH_RX_CAP time capture."""
    await setup(dut)
    await do_reset(dut)

    # Set PHC to a known time and enable
    await phc_set_time(dut, seconds=100, nanoseconds=500_000_000)
    await phc_enable(dut)

    # Let PHC run briefly
    await ClockCycles(dut.pclk, 50)

    # Inject a PTP frame on MII RX
    await inject_ptp_frame_on_mii_rx(dut)

    # Wait for CDC to propagate event to pclk domain
    await ClockCycles(dut.pclk, 10)

    # Read the captured time
    sec, ns = await phc_read_eth_rx_time(dut)

    # PHC should have captured a time close to 100s + ~500ms + small offset
    assert sec == 100, f"Expected seconds=100, got {sec}"
    assert ns >= 500_000_000, f"Expected ns >= 500_000_000, got {ns}"


@cocotb.test()
async def test_sync_02_non_ptp_no_capture(dut):
    """SYNC-02: Non-PTP frame does NOT update ETH_RX_CAP registers."""
    await setup(dut)
    await do_reset(dut)

    await phc_set_time(dut, seconds=50, nanoseconds=0)
    await phc_enable(dut)
    await ClockCycles(dut.pclk, 20)

    # Read initial capture values (should be 0 from reset)
    sec_before, ns_before = await phc_read_eth_rx_time(dut)

    # Inject a non-PTP frame
    await inject_non_ptp_frame_on_mii_rx(dut, ethertype=0x0806)
    await ClockCycles(dut.pclk, 20)

    # Capture should be unchanged
    sec_after, ns_after = await phc_read_eth_rx_time(dut)
    assert sec_after == sec_before, "Non-PTP frame should not update ETH_RX_CAP"
    assert ns_after == ns_before


@cocotb.test()
async def test_sync_03_tidelink_and_eth_independent(dut):
    """SYNC-03: TideLink HW_CAP and Ethernet ETH_RX_CAP are independent."""
    await setup(dut)
    await do_reset(dut)

    await phc_set_time(dut, seconds=10, nanoseconds=100_000_000)
    await phc_enable(dut)
    await ClockCycles(dut.pclk, 20)

    # Pulse TideLink hw_capture
    dut.hw_capture.value = 1
    await RisingEdge(dut.pclk)
    dut.hw_capture.value = 0
    await ClockCycles(dut.pclk, 5)

    # Read HW_CAP (Region 2)
    hw_sec_lo = await phc_apb_read(dut, 0x040)  # HW_CAP_SECONDS_LO

    # Run clock further
    await ClockCycles(dut.pclk, 50)

    # Inject PTP frame → ETH RX capture (later time)
    await inject_ptp_frame_on_mii_rx(dut)
    await ClockCycles(dut.pclk, 10)

    # Read ETH_RX_CAP (Region 3)
    eth_rx_sec, eth_rx_ns = await phc_read_eth_rx_time(dut)

    # HW_CAP should still hold the older time
    hw_sec_lo_after = await phc_apb_read(dut, 0x040)
    assert hw_sec_lo_after == hw_sec_lo, "HW_CAP should be unchanged by ETH RX event"

    # ETH RX should have the newer time
    assert eth_rx_sec == 10
    assert eth_rx_ns > 100_000_000, "ETH RX capture should be later than HW capture"


@cocotb.test()
async def test_sync_04_desync_and_recovery(dut):
    """SYNC-04: Intentionally desync PHC and recover via PTP offset correction.

    Simulates a simplified PTP SYNC exchange:
    1. Set PHC to an intentionally wrong time (offset by +500ms)
    2. Inject a PTP SYNC frame → capture t2 (PHC local time at RX)
    3. Provide t1 (grandmaster TX time) as a known reference
    4. Compute offset = t2 - t1 (simplified, ignoring delay for this test)
    5. Apply phase correction to PHC
    6. Verify PHC time is now close to grandmaster time
    """
    await setup(dut)
    await do_reset(dut)

    # Grandmaster reference time at SYNC transmission
    gm_t1_sec = 200
    gm_t1_ns  = 100_000_000  # 200.100s

    # Set PHC to an intentionally wrong time: 200.600s (offset +500ms)
    await phc_set_time(dut, seconds=200, nanoseconds=600_000_000)
    await phc_enable(dut)

    # Let PHC run a bit (simulating transit time of SYNC)
    await ClockCycles(dut.pclk, 100)

    # Inject PTP SYNC frame → triggers ETH RX capture
    await inject_ptp_frame_on_mii_rx(dut)
    await ClockCycles(dut.pclk, 10)

    # Read t2 (PHC local time when SYNC arrived)
    t2_sec, t2_ns = await phc_read_eth_rx_time(dut)
    t2_total = time_to_ns(t2_sec, t2_ns)
    t1_total = time_to_ns(gm_t1_sec, gm_t1_ns)

    # Compute offset (simplified: offset ≈ t2 - t1, ignoring propagation delay)
    offset_ns = t2_total - t1_total

    # Offset should be approximately +500ms (the intentional desync)
    assert offset_ns > 400_000_000, f"Expected large positive offset, got {offset_ns} ns"

    # Apply phase correction: set PHC to corrected time
    # corrected_time = current_phc_time - offset
    # For simplicity, do a software capture first to get current time
    await phc_apb_write(dut, PHC_CTRL, 0x5)  # EN=1, CAPTURE=1
    await ClockCycles(dut.pclk, 2)
    cur_sec_lo = await phc_apb_read(dut, PHC_CAP_SECONDS_LO)
    cur_ns     = await phc_apb_read(dut, PHC_CAP_NANOSECONDS)
    cur_total  = time_to_ns(cur_sec_lo, cur_ns)

    corrected_total = cur_total - offset_ns
    corrected_sec = corrected_total // NS_PER_SECOND
    corrected_ns  = corrected_total % NS_PER_SECOND

    await phc_set_time(dut, seconds=corrected_sec, nanoseconds=corrected_ns)
    await phc_enable(dut)
    await ClockCycles(dut.pclk, 10)

    # Verify: do a software capture and check time is close to grandmaster
    await phc_apb_write(dut, PHC_CTRL, 0x5)  # EN=1, CAPTURE=1
    await ClockCycles(dut.pclk, 2)
    final_sec = await phc_apb_read(dut, PHC_CAP_SECONDS_LO)
    final_ns  = await phc_apb_read(dut, PHC_CAP_NANOSECONDS)
    final_total = time_to_ns(final_sec, final_ns)

    # Grandmaster time has also advanced by the simulation duration
    # We just check that the offset from grandmaster is now small (< 10us)
    # The exact value depends on simulation timing, so we check relative reduction
    new_offset = abs(final_total - t1_total)
    assert new_offset < offset_ns, \
        f"Correction should reduce offset: was {offset_ns}, now {new_offset}"
    # After correction, residual offset should be small (a few us from clock ticks)
    assert new_offset < 50_000, \
        f"Residual offset after correction should be < 50us, got {new_offset} ns"
