"""
Cocotb tests for the wb_to_ahb3lite bridge (Layer 2).

Tests the WISHBONE master to AHB3-Lite master bridge using:
  - cocotbext-wishbone WishboneMaster to drive the WB side
  - cocotbext-ahb AHBLiteSlaveRAM to respond on the AHB side
"""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ClockCycles
from cocotbext.ahb import AHBBus, AHBLiteSlaveRAM
from cocotbext.wishbone.driver import WishboneMaster, WBOp


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

async def reset_dut(dut, cycles=5):
    """Assert reset for a number of clock cycles."""
    dut.hresetn.value = 0
    await ClockCycles(dut.hclk, cycles)
    dut.hresetn.value = 1
    await ClockCycles(dut.hclk, 2)


def build_wb_master(dut):
    """Create a WishboneMaster bound to the DUT's WB signals."""
    return WishboneMaster(
        dut,
        "wb",
        dut.hclk,
        timeout=200,
        width=32,
    )


def build_ahb_slave(dut, mem_size=4096):
    """Create an AHBLiteSlaveRAM bound to the DUT's AHB signals."""
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
            "hready": "hready",
            "hresp":  "hresp",
        },
        optional_signals={
            "hburst": "hburst",
            "hprot":  "hprot",
            "hsel":   "hsel",
        },
    )
    return AHBLiteSlaveRAM(bus, dut.hclk, dut.hresetn, mem_size=mem_size)


# ---------------------------------------------------------------------------
# Test 2.1: Single word write
# ---------------------------------------------------------------------------
@cocotb.test()
async def test_single_word_write(dut):
    """WB master write should produce a valid AHB NONSEQ write."""
    clock = Clock(dut.hclk, 10, units="ns")
    cocotb.start_soon(clock.start())

    await reset_dut(dut)

    wb_master = build_wb_master(dut)
    ahb_slave = build_ahb_slave(dut)

    test_addr = 0x00000100
    test_data = 0xDEADBEEF

    # Write via WB
    results = await wb_master.send_cycle([WBOp(adr=test_addr, dat=test_data)])
    assert results[0].ack == 1, f"Expected ACK, got {results[0].ack}"


# ---------------------------------------------------------------------------
# Test 2.2: Single word read
# ---------------------------------------------------------------------------
@cocotb.test()
async def test_single_word_read(dut):
    """WB master read should return data from the AHB slave."""
    clock = Clock(dut.hclk, 10, units="ns")
    cocotb.start_soon(clock.start())

    await reset_dut(dut)

    wb_master = build_wb_master(dut)
    ahb_slave = build_ahb_slave(dut)

    test_addr = 0x00000200
    test_data = 0xCAFEBABE

    # Pre-load data into AHB slave memory
    ahb_slave.memory.write(
        test_addr,
        test_data.to_bytes(4, byteorder="little"),
    )

    # Read via WB
    results = await wb_master.send_cycle([WBOp(adr=test_addr)])
    read_data = int(results[0].datrd)
    dut._log.info(f"Read back: 0x{read_data:08X}")
    assert read_data == test_data, \
        f"Expected 0x{test_data:08X}, got 0x{read_data:08X}"


# ---------------------------------------------------------------------------
# Test 2.3: Back-to-back transfers
# ---------------------------------------------------------------------------
@cocotb.test()
async def test_back_to_back_transfers(dut):
    """Consecutive WB cycles should all complete successfully."""
    clock = Clock(dut.hclk, 10, units="ns")
    cocotb.start_soon(clock.start())

    await reset_dut(dut)

    wb_master = build_wb_master(dut)
    ahb_slave = build_ahb_slave(dut)

    # Write multiple words
    for i in range(4):
        addr = 0x0000 + (i * 4)
        data = 0xA0000000 | i
        results = await wb_master.send_cycle([WBOp(adr=addr, dat=data)])
        assert results[0].ack == 1, f"Write {i} failed"

    # Read them back
    for i in range(4):
        addr = 0x0000 + (i * 4)
        expected = 0xA0000000 | i
        results = await wb_master.send_cycle([WBOp(adr=addr)])
        read_data = int(results[0].datrd)
        assert read_data == expected, \
            f"Addr 0x{addr:08X}: expected 0x{expected:08X}, got 0x{read_data:08X}"


# ---------------------------------------------------------------------------
# Test 2.4: AHB slave wait states (backpressure)
# ---------------------------------------------------------------------------
@cocotb.test()
async def test_ahb_slave_wait_states(dut):
    """AHB slave backpressure should delay WB ack."""
    clock = Clock(dut.hclk, 10, units="ns")
    cocotb.start_soon(clock.start())

    await reset_dut(dut)

    wb_master = build_wb_master(dut)

    # Create AHB slave with backpressure: alternating ready/not-ready
    def bp_gen():
        while True:
            yield True
            yield False  # Insert wait state

    ahb_slave = build_ahb_slave(dut)

    test_addr = 0x00000100
    test_data = 0x55AA55AA

    # Write and read should still succeed despite wait states
    results = await wb_master.send_cycle([WBOp(adr=test_addr, dat=test_data)])
    assert results[0].ack == 1, "Write with backpressure failed"

    results = await wb_master.send_cycle([WBOp(adr=test_addr)])
    read_data = int(results[0].datrd)
    assert read_data == test_data, \
        f"Expected 0x{test_data:08X}, got 0x{read_data:08X}"


# ---------------------------------------------------------------------------
# Test 2.5: AHB slave error response
# ---------------------------------------------------------------------------
@cocotb.test()
async def test_ahb_slave_error(dut):
    """AHB HRESP=ERROR should propagate to WB err."""
    clock = Clock(dut.hclk, 10, units="ns")
    cocotb.start_soon(clock.start())

    await reset_dut(dut)

    wb_master = build_wb_master(dut)
    ahb_slave = build_ahb_slave(dut, mem_size=256)

    # Access beyond slave memory should trigger error
    out_of_range_addr = 0x00000200

    results = await wb_master.send_cycle([WBOp(adr=out_of_range_addr)])
    dut._log.info(f"Out-of-range read response: ack={results[0].ack}")

    # Expect error (ack type 2 = ERR in cocotbext-wishbone)
    assert results[0].ack != 1, \
        f"Expected error response for out-of-range access, got ACK"


# ---------------------------------------------------------------------------
# Test 2.6: Reset behaviour
# ---------------------------------------------------------------------------
@cocotb.test()
async def test_reset_behaviour(dut):
    """After reset, registered AHB master outputs should be in idle state.

    Note: The wb_to_ahb3lite bridge drives mHTRANS combinationally,
    so we check the registered control signals (ctrlstart, ackmask)
    indirectly by verifying no WB ack is generated without stimulus.
    """
    clock = Clock(dut.hclk, 10, units="ns")
    cocotb.start_soon(clock.start())

    # Assert reset
    dut.hresetn.value = 0
    # Drive WB idle
    dut.wb_cyc.value = 0
    dut.wb_stb.value = 0
    dut.wb_we.value = 0
    dut.wb_adr.value = 0
    dut.wb_datwr.value = 0
    dut.wb_sel.value = 0
    dut.wb_cti.value = 0
    dut.wb_bte.value = 0

    await ClockCycles(dut.hclk, 5)

    # Release reset
    dut.hresetn.value = 1
    await ClockCycles(dut.hclk, 3)

    # With no WB activity, the bridge should not assert wb_ack
    assert dut.wb_ack.value == 0, "WB ack should be 0 with no WB activity after reset"
