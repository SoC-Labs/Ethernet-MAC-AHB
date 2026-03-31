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


# ---------------------------------------------------------------------------
# Test 1.8: Back-to-back read address integrity (pipelining bug detector)
# ---------------------------------------------------------------------------

async def _wb_slave_memory(dut, mem, log):
    """Simple WB slave with address-keyed memory model.

    Runs as a cocotb coroutine, responding to WB transactions on the DUT's
    wb_* signals.  Stores writes and returns previously-stored data on reads.
    """
    dut.wb_datrd.value = 0
    dut.wb_ack.value = 0
    dut.wb_err.value = 0

    while True:
        await RisingEdge(dut.hclk)
        if dut.wb_cyc.value == 1 and dut.wb_stb.value == 1:
            addr = int(dut.wb_adr.value)
            if dut.wb_we.value == 1:
                data = int(dut.wb_datwr.value)
                mem[addr] = data
                log.debug("WB MEM WRITE: [0x%08X] = 0x%08X", addr, data)
            else:
                data = mem.get(addr, 0)
                dut.wb_datrd.value = data
                log.debug("WB MEM READ:  [0x%08X] → 0x%08X", addr, data)
            dut.wb_ack.value = 1
        else:
            dut.wb_ack.value = 0


@cocotb.test()
async def test_back_to_back_read_data_integrity(dut):
    """1.8: Write unique data to multiple addresses, then read back-to-back
    using the AHBLiteMaster sequential API.

    Each address must return the data originally written to *that* address,
    not a stale value from a different transaction.
    """
    clock = Clock(dut.hclk, 10, units="ns")
    cocotb.start_soon(clock.start())

    await reset_dut(dut)

    mem = {}
    wb_task = cocotb.start_soon(_wb_slave_memory(dut, mem, dut._log))
    ahb_master = build_ahb_master(dut)

    num_addrs = 8
    base_addr = 0x2000
    written = {}

    # Phase 1: Write unique data to each address
    for i in range(num_addrs):
        addr = base_addr + (i * 4)
        data = 0xBEEF0000 | (i * 0x111)
        resp = await ahb_master.write(addr, data, verbose=True)
        assert resp[0]["resp"] == 0, f"Write to 0x{addr:08X} failed"
        written[addr] = data

    dut._log.info("Wrote %d addresses: %s",
                  num_addrs,
                  {f"0x{a:08X}": f"0x{d:08X}" for a, d in written.items()})

    # Phase 2: Read them all back-to-back
    mismatches = []
    for i in range(num_addrs):
        addr = base_addr + (i * 4)
        resp = await ahb_master.read(addr, verbose=True)
        assert resp[0]["resp"] == 0, f"Read from 0x{addr:08X} failed"
        read_data = int(resp[0]["data"], 16)
        expected = written[addr]
        dut._log.info("Read [0x%08X]: got 0x%08X, expected 0x%08X %s",
                      addr, read_data, expected,
                      "✓" if read_data == expected else "✗ MISMATCH")
        if read_data != expected:
            mismatches.append((addr, expected, read_data))

    if mismatches:
        for addr, exp, got in mismatches:
            dut._log.error("MISMATCH at 0x%08X: expected 0x%08X, got 0x%08X",
                           addr, exp, got)
    assert len(mismatches) == 0, \
        f"{len(mismatches)} read(s) returned wrong data (stale pipeline values)"




@cocotb.test()
async def test_write_read_interleaved_integrity(dut):
    """1.9: Interleaved write-read pairs to different addresses.

    Each write is immediately followed by a read to the same address.
    Verifies the bridge correctly handles the address-phase/data-phase
    overlap when the direction changes between consecutive transfers.
    """
    clock = Clock(dut.hclk, 10, units="ns")
    cocotb.start_soon(clock.start())

    await reset_dut(dut)

    mem = {}
    wb_task = cocotb.start_soon(_wb_slave_memory(dut, mem, dut._log))
    ahb_master = build_ahb_master(dut)

    num_pairs = 6
    base_addr = 0x3000

    for i in range(num_pairs):
        addr = base_addr + (i * 4)
        data = 0xA5A50000 | i

        # Write
        resp = await ahb_master.write(addr, data)
        assert resp[0]["resp"] == 0

        # Immediate readback
        resp = await ahb_master.read(addr)
        assert resp[0]["resp"] == 0
        read_data = int(resp[0]["data"], 16)
        assert read_data == data, \
            f"Addr 0x{addr:08X}: wrote 0x{data:08X}, read 0x{read_data:08X}"

    dut._log.info("All %d write-read pairs matched", num_pairs)
