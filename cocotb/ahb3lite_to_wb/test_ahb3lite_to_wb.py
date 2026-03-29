"""
Cocotb tests for the ahb3lite_to_wb bridge (Layer 1).

Tests the AHB3-Lite slave to WISHBONE slave bridge using:
  - cocotbext-ahb AHBLiteMaster to drive the AHB side
  - cocotbext-wishbone WishboneSlave to respond on the WB side
"""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ClockCycles, Timer
from cocotbext.ahb import AHBBus, AHBLiteMaster
from cocotbext.wishbone.monitor import WishboneSlave


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

async def reset_dut(dut, cycles=5):
    """Assert reset for a number of clock cycles."""
    dut.hresetn.value = 0
    await ClockCycles(dut.hclk, cycles)
    dut.hresetn.value = 1
    await ClockCycles(dut.hclk, 2)


def build_ahb_master(dut):
    """Create an AHBLiteMaster bound to the DUT's AHB signals."""
    bus = AHBBus.from_prefix(
        dut,
        prefix="",
        signals={
            "haddr":  "haddr",
            "hsize":  "hsize",
            "htrans": "htrans",
            "hwdata": "hwdata",
            "hrdata": "hrdata",
            "hwrite": "hwrite",
            "hready": "hreadyout",
            "hresp":  "hresp",
        },
        optional_signals={
            "hburst":    "hburst",
            "hprot":     "hprot",
            "hsel":      "hsel",
            "hready_in": "hready",
        },
    )
    return AHBLiteMaster(bus, dut.hclk, dut.hresetn, timeout=200)


def build_wb_slave(dut, datgen=None, ackgen=None, waitreplygen=None):
    """Create a WishboneSlave bound to the DUT's WB signals."""
    kwargs = {}
    if datgen is not None:
        kwargs["datgen"] = datgen
    if ackgen is not None:
        kwargs["ackgen"] = ackgen
    if waitreplygen is not None:
        kwargs["waitreplygen"] = waitreplygen
    return WishboneSlave(
        dut,
        "wb",
        dut.hclk,
        **kwargs,
    )


def data_generator(value):
    """Yield a fixed read-data value forever."""
    while True:
        yield value


def ack_generator(reply_type=1):
    """Yield a fixed reply type forever (1=ACK, 2=ERR, 3=RTY)."""
    while True:
        yield reply_type


def wait_generator(cycles=0):
    """Yield a fixed wait cycle count forever."""
    while True:
        yield cycles


# ---------------------------------------------------------------------------
# Test 1.1: Single word write
# ---------------------------------------------------------------------------
@cocotb.test()
async def test_single_word_write(dut):
    """AHB NONSEQ write should produce a valid WB write cycle."""
    clock = Clock(dut.hclk, 10, units="ns")
    cocotb.start_soon(clock.start())

    await reset_dut(dut)

    test_data = 0xDEADBEEF
    test_addr = 0x00000100

    wb_slave = build_wb_slave(dut, datgen=data_generator(0))
    ahb_master = build_ahb_master(dut)

    resp = await ahb_master.write(test_addr, test_data, verbose=True)
    dut._log.info(f"Write response: {resp}")

    # Check no error response
    assert resp[0]["resp"] == 0, f"Expected OKAY response, got {resp[0]['resp']}"


# ---------------------------------------------------------------------------
# Test 1.2: Single word read
# ---------------------------------------------------------------------------
@cocotb.test()
async def test_single_word_read(dut):
    """AHB NONSEQ read should return data from the WB slave."""
    clock = Clock(dut.hclk, 10, units="ns")
    cocotb.start_soon(clock.start())

    await reset_dut(dut)

    test_addr = 0x00000200
    expected_data = 0xCAFEBABE

    wb_slave = build_wb_slave(dut, datgen=data_generator(expected_data))
    ahb_master = build_ahb_master(dut)

    resp = await ahb_master.read(test_addr, verbose=True)
    dut._log.info(f"Read response: {resp}")

    read_data = int(resp[0]["data"], 16)
    assert read_data == expected_data, \
        f"Expected 0x{expected_data:08X}, got 0x{read_data:08X}"


# ---------------------------------------------------------------------------
# Test 1.3: Back-to-back transfers
# ---------------------------------------------------------------------------
@cocotb.test()
async def test_back_to_back_transfers(dut):
    """Consecutive NONSEQ transfers should all complete successfully."""
    clock = Clock(dut.hclk, 10, units="ns")
    cocotb.start_soon(clock.start())

    await reset_dut(dut)

    wb_slave = build_wb_slave(dut, datgen=data_generator(0x12345678))
    ahb_master = build_ahb_master(dut)

    # Perform multiple writes
    for i in range(4):
        addr = 0x1000 + (i * 4)
        data = 0xA0000000 | i
        resp = await ahb_master.write(addr, data)
        assert resp[0]["resp"] == 0, f"Write {i} failed with resp {resp[0]['resp']}"

    # Perform multiple reads
    for i in range(4):
        addr = 0x1000 + (i * 4)
        resp = await ahb_master.read(addr)
        assert resp[0]["resp"] == 0, f"Read {i} failed with resp {resp[0]['resp']}"


# ---------------------------------------------------------------------------
# Test 1.4: Idle transfer (no WB activity)
# ---------------------------------------------------------------------------
@cocotb.test()
async def test_idle_no_wb_activity(dut):
    """HTRANS=IDLE should not generate any WB cycle."""
    clock = Clock(dut.hclk, 10, units="ns")
    cocotb.start_soon(clock.start())

    await reset_dut(dut)

    wb_slave = build_wb_slave(dut, datgen=data_generator(0))

    # Drive AHB signals to IDLE state
    dut.hsel.value = 1
    dut.htrans.value = 0  # IDLE
    dut.haddr.value = 0
    dut.hsize.value = 2   # WORD
    dut.hwrite.value = 0
    dut.hwdata.value = 0
    dut.hready.value = 1

    await ClockCycles(dut.hclk, 5)

    # WB cyc and stb should remain low during IDLE
    assert dut.wb_cyc.value == 0, "WB cyc should be 0 during AHB IDLE"
    assert dut.wb_stb.value == 0, "WB stb should be 0 during AHB IDLE"


# ---------------------------------------------------------------------------
# Test 1.5: WB slave wait states
# ---------------------------------------------------------------------------
@cocotb.test()
async def test_wb_slave_wait_states(dut):
    """WB slave delaying ACK should cause HREADYOUT to deassert.

    Note: This test verifies the transfer completes despite wait states.
    The WishboneSlave waitreplygen delays ACK, which should cause the
    bridge to hold HREADYOUT low until the WB slave responds.
    """
    clock = Clock(dut.hclk, 10, units="ns")
    cocotb.start_soon(clock.start())

    await reset_dut(dut)

    # WB slave delays ACK by 2 cycles
    wb_slave = build_wb_slave(
        dut,
        datgen=data_generator(0x55AA55AA),
        waitreplygen=wait_generator(2),
    )
    ahb_master = build_ahb_master(dut)

    # The transfer should still complete (not timeout)
    resp = await ahb_master.read(0x00000300, verbose=True)
    dut._log.info(f"Wait state read response: {resp}")

    # Verify no error response — the transfer completed despite wait states
    assert resp[0]["resp"] == 0, \
        f"Expected OKAY response despite wait states, got {resp[0]['resp']}"


# ---------------------------------------------------------------------------
# Test 1.6: WB slave error response
# ---------------------------------------------------------------------------
@cocotb.test()
async def test_wb_slave_error(dut):
    """WB err_o should cause HRESP=ERROR."""
    clock = Clock(dut.hclk, 10, units="ns")
    cocotb.start_soon(clock.start())

    await reset_dut(dut)

    # WB slave responds with ERR
    wb_slave = build_wb_slave(
        dut,
        datgen=data_generator(0),
        ackgen=ack_generator(2),  # 2 = ERR
    )
    ahb_master = build_ahb_master(dut)

    resp = await ahb_master.read(0x00000400, verbose=True)
    dut._log.info(f"Error read response: {resp}")

    # The bridge should propagate the error
    assert resp[0]["resp"] == 1, \
        f"Expected ERROR response (1), got {resp[0]['resp']}"


# ---------------------------------------------------------------------------
# Test 1.7: Reset behaviour
# ---------------------------------------------------------------------------
@cocotb.test()
async def test_reset_behaviour(dut):
    """After reset, all WB outputs should be deasserted."""
    clock = Clock(dut.hclk, 10, units="ns")
    cocotb.start_soon(clock.start())

    # Assert reset
    dut.hresetn.value = 0
    await ClockCycles(dut.hclk, 5)

    # Check WB outputs are 0 during reset
    assert dut.wb_cyc.value == 0, "WB cyc should be 0 in reset"
    assert dut.wb_stb.value == 0, "WB stb should be 0 in reset"
    assert dut.wb_we.value == 0, "WB we should be 0 in reset"

    # Release reset
    dut.hresetn.value = 1
    await ClockCycles(dut.hclk, 2)

    # Should still be idle
    assert dut.wb_cyc.value == 0, "WB cyc should be 0 after reset release"
    assert dut.wb_stb.value == 0, "WB stb should be 0 after reset release"
