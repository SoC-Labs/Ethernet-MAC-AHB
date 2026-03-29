"""
Cocotb tests for the wb_to_ahb3lite bridge.

Tests the rewritten WISHBONE B3 master to AHB3-Lite master bridge using:
  - cocotbext-wishbone WishboneMaster for classic single-beat WB cycles
  - Manual signal driving for WB B3 burst cycles (CTI/BTE)
  - cocotbext-ahb AHBLiteSlaveRAM to respond on the AHB side
"""

import random

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ClockCycles, Timer
from cocotbext.ahb import AHBBus, AHBLiteSlaveRAM
from cocotbext.wishbone.driver import WishboneMaster, WBOp


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------
CTI_CLASSIC = 0b000
CTI_INCR    = 0b010
CTI_EOB     = 0b111

BTE_LINEAR  = 0b00

HTRANS_IDLE   = 0b00
HTRANS_NONSEQ = 0b10
HTRANS_SEQ    = 0b11

HBURST_SINGLE = 0b000
HBURST_INCR4  = 0b011


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
async def reset_dut(dut, cycles=5):
    """Assert reset for a number of clock cycles."""
    dut.hresetn.value = 0
    # Drive WB idle during reset
    dut.wb_cyc.value = 0
    dut.wb_stb.value = 0
    dut.wb_we.value  = 0
    dut.wb_adr.value = 0
    dut.wb_datwr.value = 0
    dut.wb_sel.value = 0
    dut.wb_cti.value = CTI_CLASSIC
    dut.wb_bte.value = BTE_LINEAR
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


async def wb_burst_write(dut, base_addr, data_list):
    """Perform a WB B3 4-beat incrementing burst write by driving signals manually.

    Mimics the OpenCores ethmac DMA master behaviour:
      - CTI=010 for beats 0-2, CTI=111 for beat 3
      - BTE=00 (linear)
      - Address increments by 4 per beat
      - Expects one ACK per beat
    """
    assert len(data_list) == 4, "INCR4 burst requires exactly 4 data words"

    for i in range(4):
        addr = base_addr + i * 4
        cti = CTI_EOB if i == 3 else CTI_INCR

        dut.wb_cyc.value = 1
        dut.wb_stb.value = 1
        dut.wb_we.value  = 1
        dut.wb_adr.value = addr
        dut.wb_datwr.value = data_list[i]
        dut.wb_sel.value = 0xF
        dut.wb_cti.value = cti
        dut.wb_bte.value = BTE_LINEAR

        # Wait for ACK
        timeout = 50
        for _ in range(timeout):
            await RisingEdge(dut.hclk)
            if dut.wb_ack.value == 1:
                break
            if dut.wb_err.value == 1:
                raise RuntimeError(f"WB error during burst write beat {i}")
        else:
            raise TimeoutError(f"No ACK for burst write beat {i}")

    # Deassert bus after burst
    dut.wb_cyc.value = 0
    dut.wb_stb.value = 0
    dut.wb_we.value  = 0
    dut.wb_cti.value = CTI_CLASSIC
    await RisingEdge(dut.hclk)


async def wb_burst_read(dut, base_addr):
    """Perform a WB B3 4-beat incrementing burst read by driving signals manually.

    Returns a list of 4 data words read from consecutive addresses.
    """
    results = []

    for i in range(4):
        addr = base_addr + i * 4
        cti = CTI_EOB if i == 3 else CTI_INCR

        dut.wb_cyc.value = 1
        dut.wb_stb.value = 1
        dut.wb_we.value  = 0
        dut.wb_adr.value = addr
        dut.wb_datwr.value = 0
        dut.wb_sel.value = 0xF
        dut.wb_cti.value = cti
        dut.wb_bte.value = BTE_LINEAR

        # Wait for ACK
        timeout = 50
        for _ in range(timeout):
            await RisingEdge(dut.hclk)
            if dut.wb_ack.value == 1:
                results.append(int(dut.wb_datrd.value))
                break
            if dut.wb_err.value == 1:
                raise RuntimeError(f"WB error during burst read beat {i}")
        else:
            raise TimeoutError(f"No ACK for burst read beat {i}")

    # Deassert bus after burst
    dut.wb_cyc.value = 0
    dut.wb_stb.value = 0
    dut.wb_cti.value = CTI_CLASSIC
    await RisingEdge(dut.hclk)

    return results


async def wb_single_write(dut, addr, data):
    """Perform a single classic WB write by driving signals manually."""
    dut.wb_cyc.value = 1
    dut.wb_stb.value = 1
    dut.wb_we.value  = 1
    dut.wb_adr.value = addr
    dut.wb_datwr.value = data
    dut.wb_sel.value = 0xF
    dut.wb_cti.value = CTI_CLASSIC
    dut.wb_bte.value = BTE_LINEAR

    timeout = 50
    for _ in range(timeout):
        await RisingEdge(dut.hclk)
        if dut.wb_ack.value == 1:
            break
        if dut.wb_err.value == 1:
            raise RuntimeError("WB error during single write")
    else:
        raise TimeoutError("No ACK for single write")

    dut.wb_cyc.value = 0
    dut.wb_stb.value = 0
    dut.wb_we.value  = 0
    await RisingEdge(dut.hclk)


async def wb_single_read(dut, addr):
    """Perform a single classic WB read by driving signals manually."""
    dut.wb_cyc.value = 1
    dut.wb_stb.value = 1
    dut.wb_we.value  = 0
    dut.wb_adr.value = addr
    dut.wb_datwr.value = 0
    dut.wb_sel.value = 0xF
    dut.wb_cti.value = CTI_CLASSIC
    dut.wb_bte.value = BTE_LINEAR

    timeout = 50
    for _ in range(timeout):
        await RisingEdge(dut.hclk)
        if dut.wb_ack.value == 1:
            result = int(dut.wb_datrd.value)
            break
        if dut.wb_err.value == 1:
            raise RuntimeError("WB error during single read")
    else:
        raise TimeoutError("No ACK for single read")

    dut.wb_cyc.value = 0
    dut.wb_stb.value = 0
    await RisingEdge(dut.hclk)

    return result


# ===========================================================================
# Test 2.1: Single word write
# ===========================================================================
@cocotb.test()
async def test_single_word_write(dut):
    """WB classic write should produce a valid AHB write."""
    clock = Clock(dut.hclk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset_dut(dut)

    ahb_slave = build_ahb_slave(dut)

    test_addr = 0x00000100
    test_data = 0xDEADBEEF

    await wb_single_write(dut, test_addr, test_data)

    # Verify data in AHB slave memory
    mem_data = int.from_bytes(
        ahb_slave.memory.read(test_addr, 4), byteorder="little"
    )
    assert mem_data == test_data, \
        f"Expected 0x{test_data:08X} at 0x{test_addr:08X}, got 0x{mem_data:08X}"


# ===========================================================================
# Test 2.2: Single word read
# ===========================================================================
@cocotb.test()
async def test_single_word_read(dut):
    """WB classic read should return data from the AHB slave."""
    clock = Clock(dut.hclk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset_dut(dut)

    ahb_slave = build_ahb_slave(dut)

    test_addr = 0x00000200
    test_data = 0xCAFEBABE

    # Pre-load data into AHB slave memory
    ahb_slave.memory.write(
        test_addr, test_data.to_bytes(4, byteorder="little")
    )

    read_data = await wb_single_read(dut, test_addr)
    dut._log.info(f"Read back: 0x{read_data:08X}")
    assert read_data == test_data, \
        f"Expected 0x{test_data:08X}, got 0x{read_data:08X}"


# ===========================================================================
# Test 2.3: Write then read-back
# ===========================================================================
@cocotb.test()
async def test_write_then_readback(dut):
    """Write data via WB, read back from same address."""
    clock = Clock(dut.hclk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset_dut(dut)

    ahb_slave = build_ahb_slave(dut)

    test_addr = 0x00000300
    test_data = 0x12345678

    await wb_single_write(dut, test_addr, test_data)
    read_data = await wb_single_read(dut, test_addr)

    assert read_data == test_data, \
        f"Expected 0x{test_data:08X}, got 0x{read_data:08X}"


# ===========================================================================
# Test 2.4: Back-to-back single transfers
# ===========================================================================
@cocotb.test()
async def test_back_to_back_singles(dut):
    """Consecutive WB classic cycles should all complete successfully."""
    clock = Clock(dut.hclk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset_dut(dut)

    ahb_slave = build_ahb_slave(dut)

    # Write multiple words
    for i in range(4):
        addr = 0x0000 + (i * 4)
        data = 0xA0000000 | i
        await wb_single_write(dut, addr, data)

    # Read them back
    for i in range(4):
        addr = 0x0000 + (i * 4)
        expected = 0xA0000000 | i
        read_data = await wb_single_read(dut, addr)
        assert read_data == expected, \
            f"Addr 0x{addr:08X}: expected 0x{expected:08X}, got 0x{read_data:08X}"


# ===========================================================================
# Test 2.5: Multiple addresses (stride pattern)
# ===========================================================================
@cocotb.test()
async def test_multiple_addresses(dut):
    """Write/read to different addresses with stride pattern."""
    clock = Clock(dut.hclk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset_dut(dut)

    ahb_slave = build_ahb_slave(dut)

    addresses = [0x000, 0x100, 0x200, 0x300, 0x400, 0x500]
    test_values = [0x11111111 * (i + 1) for i in range(len(addresses))]

    # Write all
    for addr, data in zip(addresses, test_values):
        await wb_single_write(dut, addr, data)

    # Read all back
    for addr, expected in zip(addresses, test_values):
        read_data = await wb_single_read(dut, addr)
        assert read_data == expected, \
            f"Addr 0x{addr:03X}: expected 0x{expected:08X}, got 0x{read_data:08X}"


# ===========================================================================
# Test 2.6: Burst write (INCR4)
# ===========================================================================
@cocotb.test()
async def test_burst_write(dut):
    """WB B3 4-beat burst write should write 4 consecutive words to AHB."""
    clock = Clock(dut.hclk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset_dut(dut)

    ahb_slave = build_ahb_slave(dut)

    base_addr = 0x00000100
    burst_data = [0xAAAA0000, 0xBBBB1111, 0xCCCC2222, 0xDDDD3333]

    await wb_burst_write(dut, base_addr, burst_data)

    # Verify all 4 words in AHB slave memory
    for i, expected in enumerate(burst_data):
        addr = base_addr + i * 4
        mem_data = int.from_bytes(
            ahb_slave.memory.read(addr, 4), byteorder="little"
        )
        assert mem_data == expected, \
            f"Beat {i} @ 0x{addr:08X}: expected 0x{expected:08X}, got 0x{mem_data:08X}"


# ===========================================================================
# Test 2.7: Burst read (INCR4)
# ===========================================================================
@cocotb.test()
async def test_burst_read(dut):
    """WB B3 4-beat burst read should read 4 consecutive words from AHB."""
    clock = Clock(dut.hclk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset_dut(dut)

    ahb_slave = build_ahb_slave(dut)

    base_addr = 0x00000200
    expected_data = [0x10203040, 0x50607080, 0x90A0B0C0, 0xD0E0F000]

    # Pre-load data into AHB slave memory
    for i, data in enumerate(expected_data):
        addr = base_addr + i * 4
        ahb_slave.memory.write(addr, data.to_bytes(4, byteorder="little"))

    results = await wb_burst_read(dut, base_addr)

    for i, (got, expected) in enumerate(zip(results, expected_data)):
        assert got == expected, \
            f"Beat {i}: expected 0x{expected:08X}, got 0x{got:08X}"


# ===========================================================================
# Test 2.8: Burst write then single read-back
# ===========================================================================
@cocotb.test()
async def test_burst_write_single_readback(dut):
    """Burst write 4 words, then single-read each back."""
    clock = Clock(dut.hclk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset_dut(dut)

    ahb_slave = build_ahb_slave(dut)

    base_addr = 0x00000300
    burst_data = [0x11111111, 0x22222222, 0x33333333, 0x44444444]

    await wb_burst_write(dut, base_addr, burst_data)

    # Read back each word individually
    for i, expected in enumerate(burst_data):
        addr = base_addr + i * 4
        read_data = await wb_single_read(dut, addr)
        assert read_data == expected, \
            f"Addr 0x{addr:08X}: expected 0x{expected:08X}, got 0x{read_data:08X}"


# ===========================================================================
# Test 2.12: Consecutive bursts
# ===========================================================================
@cocotb.test()
async def test_consecutive_bursts(dut):
    """Two back-to-back 4-beat burst writes should both complete correctly."""
    clock = Clock(dut.hclk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset_dut(dut)

    ahb_slave = build_ahb_slave(dut)

    # First burst
    base1 = 0x00000100
    data1 = [0xAA000000, 0xAA000001, 0xAA000002, 0xAA000003]
    await wb_burst_write(dut, base1, data1)

    # Second burst immediately after
    base2 = 0x00000200
    data2 = [0xBB000000, 0xBB000001, 0xBB000002, 0xBB000003]
    await wb_burst_write(dut, base2, data2)

    # Verify both bursts
    for i, expected in enumerate(data1):
        addr = base1 + i * 4
        mem_data = int.from_bytes(
            ahb_slave.memory.read(addr, 4), byteorder="little"
        )
        assert mem_data == expected, \
            f"Burst 1 beat {i}: expected 0x{expected:08X}, got 0x{mem_data:08X}"

    for i, expected in enumerate(data2):
        addr = base2 + i * 4
        mem_data = int.from_bytes(
            ahb_slave.memory.read(addr, 4), byteorder="little"
        )
        assert mem_data == expected, \
            f"Burst 2 beat {i}: expected 0x{expected:08X}, got 0x{mem_data:08X}"


# ===========================================================================
# Test 2.13: AHB slave wait states (single)
# ===========================================================================
@cocotb.test()
async def test_ahb_wait_states_single(dut):
    """AHB slave backpressure should delay WB ack but transfer still succeeds."""
    clock = Clock(dut.hclk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset_dut(dut)

    ahb_slave = build_ahb_slave(dut)

    test_addr = 0x00000100
    test_data = 0x55AA55AA

    # Write and read should succeed despite any slave-side latency
    await wb_single_write(dut, test_addr, test_data)
    read_data = await wb_single_read(dut, test_addr)
    assert read_data == test_data, \
        f"Expected 0x{test_data:08X}, got 0x{read_data:08X}"


# ===========================================================================
# Test 2.14: Burst with wait states
# ===========================================================================
@cocotb.test()
async def test_burst_with_wait_states(dut):
    """INCR4 burst where AHB slave may insert wait states."""
    clock = Clock(dut.hclk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset_dut(dut)

    ahb_slave = build_ahb_slave(dut)

    base_addr = 0x00000400
    burst_data = [0x10000001, 0x20000002, 0x30000003, 0x40000004]

    await wb_burst_write(dut, base_addr, burst_data)

    # Verify
    for i, expected in enumerate(burst_data):
        addr = base_addr + i * 4
        mem_data = int.from_bytes(
            ahb_slave.memory.read(addr, 4), byteorder="little"
        )
        assert mem_data == expected, \
            f"Beat {i}: expected 0x{expected:08X}, got 0x{mem_data:08X}"


# ===========================================================================
# Test 2.15: HPROT driven
# ===========================================================================
@cocotb.test()
async def test_hprot_driven(dut):
    """Verify HPROT = 0b0011 (privileged data, non-cacheable)."""
    clock = Clock(dut.hclk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset_dut(dut)

    ahb_slave = build_ahb_slave(dut)

    hprot_val = int(dut.hprot.value)
    assert hprot_val == 0b0011, \
        f"Expected HPROT=0b0011, got 0b{hprot_val:04b}"


# ===========================================================================
# Test 2.16: HSIZE driven
# ===========================================================================
@cocotb.test()
async def test_hsize_driven(dut):
    """Verify HSIZE = 0b010 (32-bit word) during a transfer."""
    clock = Clock(dut.hclk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset_dut(dut)

    ahb_slave = build_ahb_slave(dut)

    hsize_val = int(dut.hsize.value)
    assert hsize_val == 0b010, \
        f"Expected HSIZE=0b010, got 0b{hsize_val:03b}"


# ===========================================================================
# Test 2.19: Reset clears state
# ===========================================================================
@cocotb.test()
async def test_reset_clears_state(dut):
    """After reset, bridge should be in idle with no WB ack/err."""
    clock = Clock(dut.hclk, 10, units="ns")
    cocotb.start_soon(clock.start())

    await reset_dut(dut)

    # With no WB activity, verify idle state
    assert dut.wb_ack.value == 0, "WB ack should be 0 after reset"
    assert dut.wb_err.value == 0, "WB err should be 0 after reset"
    assert int(dut.htrans.value) == HTRANS_IDLE, \
        f"HTRANS should be IDLE after reset, got {int(dut.htrans.value)}"


# ===========================================================================
# Test 2.20: Idle bus state
# ===========================================================================
@cocotb.test()
async def test_idle_bus_state(dut):
    """No WB activity should result in AHB bus idle with no spurious activity."""
    clock = Clock(dut.hclk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset_dut(dut)

    ahb_slave = build_ahb_slave(dut)

    # Wait several cycles with no WB activity
    for _ in range(10):
        await RisingEdge(dut.hclk)
        assert int(dut.htrans.value) == HTRANS_IDLE, \
            "HTRANS should remain IDLE with no WB activity"
        assert dut.wb_ack.value == 0, "No spurious WB ack"
        assert dut.wb_err.value == 0, "No spurious WB err"


# ===========================================================================
# Test 2.21: Transfer after reset
# ===========================================================================
@cocotb.test()
async def test_transfer_after_reset(dut):
    """Reset then perform single write+read to verify bridge recovers."""
    clock = Clock(dut.hclk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset_dut(dut)

    ahb_slave = build_ahb_slave(dut)

    test_addr = 0x00000500
    test_data = 0xFEEDFACE

    await wb_single_write(dut, test_addr, test_data)
    read_data = await wb_single_read(dut, test_addr)
    assert read_data == test_data, \
        f"Expected 0x{test_data:08X}, got 0x{read_data:08X}"

    # Reset mid-session
    await reset_dut(dut)

    # Should still work after second reset
    ahb_slave2 = build_ahb_slave(dut)
    test_data2 = 0xBAADF00D
    await wb_single_write(dut, test_addr, test_data2)
    read_data2 = await wb_single_read(dut, test_addr)
    assert read_data2 == test_data2, \
        f"After re-reset: expected 0x{test_data2:08X}, got 0x{read_data2:08X}"


# ===========================================================================
# Test: Burst then single (mixed traffic)
# ===========================================================================
@cocotb.test()
async def test_burst_then_single(dut):
    """A burst followed by a single transfer should both succeed."""
    clock = Clock(dut.hclk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset_dut(dut)

    ahb_slave = build_ahb_slave(dut)

    # Burst write
    base_addr = 0x00000100
    burst_data = [0xAAAA0000, 0xBBBB1111, 0xCCCC2222, 0xDDDD3333]
    await wb_burst_write(dut, base_addr, burst_data)

    # Single write to different address
    single_addr = 0x00000200
    single_data = 0xEEEE4444
    await wb_single_write(dut, single_addr, single_data)

    # Verify burst data
    for i, expected in enumerate(burst_data):
        addr = base_addr + i * 4
        mem_data = int.from_bytes(
            ahb_slave.memory.read(addr, 4), byteorder="little"
        )
        assert mem_data == expected, \
            f"Burst beat {i}: expected 0x{expected:08X}, got 0x{mem_data:08X}"

    # Verify single data
    mem_data = int.from_bytes(
        ahb_slave.memory.read(single_addr, 4), byteorder="little"
    )
    assert mem_data == single_data, \
        f"Single: expected 0x{single_data:08X}, got 0x{mem_data:08X}"


# ===========================================================================
# Test: Single then burst (mixed traffic)
# ===========================================================================
@cocotb.test()
async def test_single_then_burst(dut):
    """A single transfer followed by a burst should both succeed."""
    clock = Clock(dut.hclk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset_dut(dut)

    ahb_slave = build_ahb_slave(dut)

    # Single write
    single_addr = 0x00000050
    single_data = 0x12345678
    await wb_single_write(dut, single_addr, single_data)

    # Burst write
    base_addr = 0x00000100
    burst_data = [0x11000000, 0x22000000, 0x33000000, 0x44000000]
    await wb_burst_write(dut, base_addr, burst_data)

    # Verify single
    read_data = await wb_single_read(dut, single_addr)
    assert read_data == single_data, \
        f"Single: expected 0x{single_data:08X}, got 0x{read_data:08X}"

    # Verify burst via single reads
    for i, expected in enumerate(burst_data):
        addr = base_addr + i * 4
        read_data = await wb_single_read(dut, addr)
        assert read_data == expected, \
            f"Burst beat {i}: expected 0x{expected:08X}, got 0x{read_data:08X}"


# ===========================================================================
# Test: Burst read after burst write
# ===========================================================================
@cocotb.test()
async def test_burst_write_burst_read(dut):
    """Burst write 4 words then burst read them back."""
    clock = Clock(dut.hclk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset_dut(dut)

    ahb_slave = build_ahb_slave(dut)

    base_addr = 0x00000600
    burst_data = [0xFACE0001, 0xFACE0002, 0xFACE0003, 0xFACE0004]

    await wb_burst_write(dut, base_addr, burst_data)
    results = await wb_burst_read(dut, base_addr)

    for i, (got, expected) in enumerate(zip(results, burst_data)):
        assert got == expected, \
            f"Beat {i}: expected 0x{expected:08X}, got 0x{got:08X}"


# ===========================================================================
# AHB Protocol Monitor (passive checker)
# ===========================================================================
class AHBProtocolMonitor:
    """Passive AHB protocol checker that runs alongside tests.

    Checks protocol rules on every clock cycle:
    - HTRANS sequencing (SEQ only after NONSEQ/SEQ)
    - HBURST stable during burst
    - INCR4 address increment is +4
    - No simultaneous ACK and ERR on WB side
    """

    def __init__(self, dut, log):
        self.dut = dut
        self.log = log
        self.errors = []
        self.prev_htrans = HTRANS_IDLE
        self.prev_haddr = 0
        self.burst_hburst = None
        self.burst_hwrite = None
        self.in_burst = False
        self.burst_beat_count = 0

    async def run(self):
        """Run the monitor continuously until the test ends."""
        while True:
            await RisingEdge(self.dut.hclk)

            if self.dut.hresetn.value == 0:
                self.prev_htrans = HTRANS_IDLE
                self.in_burst = False
                self.burst_beat_count = 0
                continue

            htrans = int(self.dut.htrans.value)
            hburst = int(self.dut.hburst.value)
            haddr  = int(self.dut.haddr.value)
            hwrite = int(self.dut.hwrite.value)
            hready = int(self.dut.hready.value)
            wb_ack = int(self.dut.wb_ack.value)
            wb_err = int(self.dut.wb_err.value)

            # Check: no simultaneous ACK and ERR
            if wb_ack and wb_err:
                self._fail("WB ACK and ERR asserted simultaneously")

            # Check: SEQ only follows NONSEQ or SEQ
            if htrans == HTRANS_SEQ:
                if self.prev_htrans not in (HTRANS_NONSEQ, HTRANS_SEQ):
                    self._fail(f"HTRANS=SEQ after prev={self.prev_htrans}")

            # Track burst state
            if hready:
                if htrans == HTRANS_NONSEQ:
                    self.burst_hburst = hburst
                    self.burst_hwrite = hwrite
                    self.in_burst = (hburst != HBURST_SINGLE)
                    self.burst_beat_count = 1
                    self.prev_haddr = haddr
                elif htrans == HTRANS_SEQ and self.in_burst:
                    self.burst_beat_count += 1
                    # Check: HBURST stable during burst
                    if hburst != self.burst_hburst:
                        self._fail(f"HBURST changed mid-burst: "
                                   f"expected {self.burst_hburst}, got {hburst}")
                    # Check: HWRITE stable during burst
                    if hwrite != self.burst_hwrite:
                        self._fail(f"HWRITE changed mid-burst")
                    # Check: INCR4 address increment
                    if self.burst_hburst == HBURST_INCR4:
                        expected_addr = (self.prev_haddr + 4) & 0xFFFFFFFF
                        if haddr != expected_addr:
                            self._fail(f"INCR4 addr: expected 0x{expected_addr:08X}, "
                                       f"got 0x{haddr:08X}")
                    self.prev_haddr = haddr
                elif htrans == HTRANS_IDLE:
                    if self.in_burst and self.burst_hburst == HBURST_INCR4:
                        if self.burst_beat_count != 4:
                            self._fail(f"INCR4 burst ended after "
                                       f"{self.burst_beat_count} beats (expected 4)")
                    self.in_burst = False
                    self.burst_beat_count = 0

                self.prev_htrans = htrans

    def _fail(self, msg):
        self.log.error(f"AHB PROTOCOL VIOLATION: {msg}")
        self.errors.append(msg)

    def check(self):
        """Assert no protocol violations were detected."""
        assert len(self.errors) == 0, \
            f"AHB protocol monitor detected {len(self.errors)} violations:\n" + \
            "\n".join(f"  - {e}" for e in self.errors)


# ===========================================================================
# Test: Constrained random single transfers
# ===========================================================================
@cocotb.test()
async def test_random_singles(dut):
    """Constrained random mix of single writes and reads."""
    clock = Clock(dut.hclk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset_dut(dut)

    ahb_slave = build_ahb_slave(dut)
    monitor = AHBProtocolMonitor(dut, dut._log)
    cocotb.start_soon(monitor.run())

    rng = random.Random(42)  # Fixed seed for reproducibility
    written = {}

    NUM_OPS = 50

    for _ in range(NUM_OPS):
        # Random word-aligned address within slave memory
        addr = rng.randrange(0, 4096, 4)
        data = rng.randint(0, 0xFFFFFFFF)

        # Randomly write or read
        if rng.random() < 0.6 or addr not in written:
            # Write
            await wb_single_write(dut, addr, data)
            written[addr] = data
        else:
            # Read back previously written address
            read_data = await wb_single_read(dut, addr)
            expected = written[addr]
            assert read_data == expected, \
                f"Random read @ 0x{addr:03X}: expected 0x{expected:08X}, got 0x{read_data:08X}"

    # Verify all written data
    for addr, expected in written.items():
        read_data = await wb_single_read(dut, addr)
        assert read_data == expected, \
            f"Final verify @ 0x{addr:03X}: expected 0x{expected:08X}, got 0x{read_data:08X}"

    monitor.check()
    dut._log.info(f"Random singles: {NUM_OPS} operations, {len(written)} unique addresses verified")


# ===========================================================================
# Test: Constrained random burst transfers
# ===========================================================================
@cocotb.test()
async def test_random_bursts(dut):
    """Constrained random mix of burst writes and reads."""
    clock = Clock(dut.hclk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset_dut(dut)

    ahb_slave = build_ahb_slave(dut)
    monitor = AHBProtocolMonitor(dut, dut._log)
    cocotb.start_soon(monitor.run())

    rng = random.Random(123)
    memory_model = {}  # Track individual word addresses to handle overlaps

    NUM_BURSTS = 20
    burst_bases = []

    for _ in range(NUM_BURSTS):
        # Random word-aligned base address (leaving room for 4 words)
        base = rng.randrange(0, 4096 - 16, 4)
        data = [rng.randint(0, 0xFFFFFFFF) for _ in range(4)]

        await wb_burst_write(dut, base, data)
        burst_bases.append(base)
        for i, d in enumerate(data):
            memory_model[base + i * 4] = d

    # Read back all bursts using individual word tracking
    for base in burst_bases:
        results = await wb_burst_read(dut, base)
        for i, got in enumerate(results):
            addr = base + i * 4
            expected = memory_model[addr]
            assert got == expected, \
                f"Burst @ 0x{base:03X} beat {i}: expected 0x{expected:08X}, got 0x{got:08X}"

    monitor.check()
    dut._log.info(f"Random bursts: {NUM_BURSTS} bursts written and verified")


# ===========================================================================
# Test: Constrained random mixed traffic (singles + bursts)
# ===========================================================================
@cocotb.test()
async def test_random_mixed_traffic(dut):
    """Constrained random interleaving of single and burst transfers."""
    clock = Clock(dut.hclk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset_dut(dut)

    ahb_slave = build_ahb_slave(dut)
    monitor = AHBProtocolMonitor(dut, dut._log)
    cocotb.start_soon(monitor.run())

    rng = random.Random(999)
    memory_model = {}  # addr -> data

    NUM_OPS = 40

    for op_num in range(NUM_OPS):
        is_burst = rng.random() < 0.4
        is_write = rng.random() < 0.6

        if is_burst:
            base = rng.randrange(0, 4096 - 16, 4)
            if is_write:
                data = [rng.randint(0, 0xFFFFFFFF) for _ in range(4)]
                await wb_burst_write(dut, base, data)
                for i, d in enumerate(data):
                    memory_model[base + i * 4] = d
            else:
                # Only read if we've written to these addresses
                if all((base + i * 4) in memory_model for i in range(4)):
                    results = await wb_burst_read(dut, base)
                    for i, got in enumerate(results):
                        addr = base + i * 4
                        expected = memory_model[addr]
                        assert got == expected, \
                            f"Op {op_num} burst read @ 0x{addr:03X}: " \
                            f"expected 0x{expected:08X}, got 0x{got:08X}"
        else:
            addr = rng.randrange(0, 4096, 4)
            if is_write:
                data = rng.randint(0, 0xFFFFFFFF)
                await wb_single_write(dut, addr, data)
                memory_model[addr] = data
            else:
                if addr in memory_model:
                    got = await wb_single_read(dut, addr)
                    expected = memory_model[addr]
                    assert got == expected, \
                        f"Op {op_num} single read @ 0x{addr:03X}: " \
                        f"expected 0x{expected:08X}, got 0x{got:08X}"

    monitor.check()
    dut._log.info(f"Random mixed: {NUM_OPS} operations, "
                  f"{len(memory_model)} addresses in model")


# ===========================================================================
# Coverage-targeted tests below.
#
# These tests drive AHB response signals (hready, hresp) manually instead
# of using AHBLiteSlaveRAM, to exercise error paths and wait-state logic
# that the slave RAM never triggers.
# ===========================================================================

async def reset_dut_manual_ahb(dut, cycles=5):
    """Reset with manual AHB signal control (no AHBLiteSlaveRAM)."""
    dut.hresetn.value = 0
    dut.wb_cyc.value = 0
    dut.wb_stb.value = 0
    dut.wb_we.value  = 0
    dut.wb_adr.value = 0
    dut.wb_datwr.value = 0
    dut.wb_sel.value = 0
    dut.wb_cti.value = CTI_CLASSIC
    dut.wb_bte.value = BTE_LINEAR
    # Drive AHB slave responses manually
    dut.hready.value = 1
    dut.hresp.value  = 0
    dut.hrdata.value = 0
    await ClockCycles(dut.hclk, cycles)
    dut.hresetn.value = 1
    await ClockCycles(dut.hclk, 2)


# ===========================================================================
# Test: AHB error response on single write (covers SINGLE_DATA error path)
# ===========================================================================
@cocotb.test()
async def test_ahb_error_single_write(dut):
    """HRESP=1 during single write data phase should produce WB err."""
    clock = Clock(dut.hclk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset_dut_manual_ahb(dut)

    # Start a single write
    dut.wb_cyc.value = 1
    dut.wb_stb.value = 1
    dut.wb_we.value  = 1
    dut.wb_adr.value = 0x100
    dut.wb_datwr.value = 0xDEADBEEF
    dut.wb_sel.value = 0xF
    dut.wb_cti.value = CTI_CLASSIC
    dut.hready.value = 1
    dut.hresp.value  = 0

    # Wait for bridge to enter data phase (S_ADDR -> S_SINGLE_DATA)
    # S_IDLE->S_ADDR on first edge, S_ADDR->S_SINGLE_DATA when HREADY=1
    await RisingEdge(dut.hclk)  # IDLE -> ADDR
    await RisingEdge(dut.hclk)  # ADDR -> SINGLE_DATA (HREADY=1)

    # Now inject AHB two-cycle error: cycle 1: HRESP=1, HREADY=0
    dut.hresp.value  = 1
    dut.hready.value = 0
    await RisingEdge(dut.hclk)

    # Cycle 2: HRESP=1, HREADY=1 -> error completes
    dut.hresp.value  = 1
    dut.hready.value = 1
    await RisingEdge(dut.hclk)

    # Check WB error was asserted
    assert dut.wb_err.value == 1, "Expected wb_err=1 on AHB error response"
    assert dut.wb_ack.value == 0, "Expected wb_ack=0 during error"

    # Deassert and return to idle
    dut.wb_cyc.value = 0
    dut.wb_stb.value = 0
    dut.hresp.value  = 0
    await RisingEdge(dut.hclk)

    # Verify bridge returns to idle
    assert int(dut.htrans.value) == HTRANS_IDLE, "Bridge should return to IDLE after error"


# ===========================================================================
# Test: AHB error response on single read
# ===========================================================================
@cocotb.test()
async def test_ahb_error_single_read(dut):
    """HRESP=1 during single read data phase should produce WB err."""
    clock = Clock(dut.hclk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset_dut_manual_ahb(dut)

    dut.wb_cyc.value = 1
    dut.wb_stb.value = 1
    dut.wb_we.value  = 0
    dut.wb_adr.value = 0x200
    dut.wb_sel.value = 0xF
    dut.wb_cti.value = CTI_CLASSIC
    dut.hready.value = 1
    dut.hresp.value  = 0

    await RisingEdge(dut.hclk)  # IDLE -> ADDR
    await RisingEdge(dut.hclk)  # ADDR -> SINGLE_DATA

    # Two-cycle error
    dut.hresp.value  = 1
    dut.hready.value = 0
    await RisingEdge(dut.hclk)
    dut.hready.value = 1
    await RisingEdge(dut.hclk)

    assert dut.wb_err.value == 1, "Expected wb_err=1"
    assert dut.wb_ack.value == 0, "Expected wb_ack=0"

    dut.wb_cyc.value = 0
    dut.wb_stb.value = 0
    dut.hresp.value  = 0
    await RisingEdge(dut.hclk)


# ===========================================================================
# Test: AHB error mid-burst (covers BURST_PIPE error path)
# ===========================================================================
@cocotb.test()
async def test_ahb_error_mid_burst(dut):
    """HRESP=1 during burst should abort burst and produce WB err."""
    clock = Clock(dut.hclk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset_dut_manual_ahb(dut)

    # Start a burst write
    dut.wb_cyc.value = 1
    dut.wb_stb.value = 1
    dut.wb_we.value  = 1
    dut.wb_adr.value = 0x100
    dut.wb_datwr.value = 0x11111111
    dut.wb_sel.value = 0xF
    dut.wb_cti.value = CTI_INCR
    dut.hready.value = 1
    dut.hresp.value  = 0

    await RisingEdge(dut.hclk)  # IDLE -> ADDR
    await RisingEdge(dut.hclk)  # ADDR -> BURST_PIPE (beat_count=1)

    # Let first beat ACK normally
    await RisingEdge(dut.hclk)  # BURST_PIPE: ACK beat 0, beat_count->2
    assert dut.wb_ack.value == 1, "Expected ACK for beat 0"

    # Advance WB to next beat
    dut.wb_adr.value = 0x104
    dut.wb_datwr.value = 0x22222222

    # Now inject error on second beat's data phase
    dut.hresp.value  = 1
    dut.hready.value = 0
    await RisingEdge(dut.hclk)  # First cycle of error

    dut.hready.value = 1
    await RisingEdge(dut.hclk)  # Second cycle: error completes

    assert dut.wb_err.value == 1, "Expected wb_err=1 on burst error"
    assert dut.wb_ack.value == 0, "Expected wb_ack=0 during error"

    # Bridge should abort to idle
    dut.wb_cyc.value = 0
    dut.wb_stb.value = 0
    dut.hresp.value  = 0
    dut.wb_cti.value = CTI_CLASSIC
    await RisingEdge(dut.hclk)

    assert int(dut.htrans.value) == HTRANS_IDLE, "Bridge should return to IDLE after burst error"


# ===========================================================================
# Test: AHB error on last burst beat (covers BURST_LAST error path)
# ===========================================================================
@cocotb.test()
async def test_ahb_error_burst_last(dut):
    """HRESP=1 during final burst data phase should produce WB err."""
    clock = Clock(dut.hclk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset_dut_manual_ahb(dut)

    # Drive burst -- let beats 0,1,2 succeed, error on beat 3
    dut.wb_cyc.value = 1
    dut.wb_stb.value = 1
    dut.wb_we.value  = 1
    dut.wb_sel.value = 0xF
    dut.wb_cti.value = CTI_INCR
    dut.hready.value = 1
    dut.hresp.value  = 0

    beat_addrs = [0x300, 0x304, 0x308, 0x30C]
    beat_data  = [0xAA, 0xBB, 0xCC, 0xDD]

    dut.wb_adr.value = beat_addrs[0]
    dut.wb_datwr.value = beat_data[0]

    await RisingEdge(dut.hclk)  # IDLE -> ADDR
    await RisingEdge(dut.hclk)  # ADDR -> BURST_PIPE

    # Beats 0, 1, 2: ACK normally
    for i in range(3):
        await RisingEdge(dut.hclk)
        assert dut.wb_ack.value == 1, f"Expected ACK for beat {i}"
        if i < 2:
            dut.wb_adr.value = beat_addrs[i + 1]
            dut.wb_datwr.value = beat_data[i + 1]
            dut.wb_cti.value = CTI_INCR
        else:
            dut.wb_adr.value = beat_addrs[3]
            dut.wb_datwr.value = beat_data[3]
            dut.wb_cti.value = CTI_EOB

    # Now in BURST_LAST -- inject error
    dut.hresp.value  = 1
    dut.hready.value = 0
    await RisingEdge(dut.hclk)

    dut.hready.value = 1
    await RisingEdge(dut.hclk)

    assert dut.wb_err.value == 1, "Expected wb_err=1 on final burst beat error"

    dut.wb_cyc.value = 0
    dut.wb_stb.value = 0
    dut.hresp.value  = 0
    dut.wb_cti.value = CTI_CLASSIC
    await RisingEdge(dut.hclk)


# ===========================================================================
# Test: AHB wait states in address phase (covers S_ADDR HREADY=0)
# ===========================================================================
@cocotb.test()
async def test_ahb_wait_state_addr_phase(dut):
    """HREADY=0 in address phase should hold NONSEQ until accepted."""
    clock = Clock(dut.hclk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset_dut_manual_ahb(dut)

    dut.wb_cyc.value = 1
    dut.wb_stb.value = 1
    dut.wb_we.value  = 1
    dut.wb_adr.value = 0x400
    dut.wb_datwr.value = 0xFEEDFACE
    dut.wb_sel.value = 0xF
    dut.wb_cti.value = CTI_CLASSIC
    dut.hready.value = 1
    dut.hresp.value  = 0

    await RisingEdge(dut.hclk)  # IDLE -> ADDR

    # Insert 3 wait states in the address phase
    dut.hready.value = 0
    for _ in range(3):
        await RisingEdge(dut.hclk)
        assert int(dut.htrans.value) == HTRANS_NONSEQ, \
            "Bridge should maintain NONSEQ during addr wait states"

    # Accept the address
    dut.hready.value = 1
    await RisingEdge(dut.hclk)  # ADDR -> SINGLE_DATA

    # Data phase -- complete normally
    await RisingEdge(dut.hclk)
    assert dut.wb_ack.value == 1, "Expected wb_ack after wait states"

    dut.wb_cyc.value = 0
    dut.wb_stb.value = 0
    await RisingEdge(dut.hclk)


# ===========================================================================
# Test: AHB wait states in data phase (covers SINGLE_DATA HREADY=0)
# ===========================================================================
@cocotb.test()
async def test_ahb_wait_state_data_phase(dut):
    """HREADY=0 in data phase should delay WB ack."""
    clock = Clock(dut.hclk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset_dut_manual_ahb(dut)

    dut.wb_cyc.value = 1
    dut.wb_stb.value = 1
    dut.wb_we.value  = 0
    dut.wb_adr.value = 0x500
    dut.wb_sel.value = 0xF
    dut.wb_cti.value = CTI_CLASSIC
    dut.hready.value = 1
    dut.hresp.value  = 0
    dut.hrdata.value = 0xCAFEBABE

    await RisingEdge(dut.hclk)  # IDLE -> ADDR
    await RisingEdge(dut.hclk)  # ADDR -> SINGLE_DATA

    # Insert 2 wait states in data phase
    dut.hready.value = 0
    for _ in range(2):
        await RisingEdge(dut.hclk)
        assert dut.wb_ack.value == 0, "No ACK during wait states"

    # Complete data phase
    dut.hready.value = 1
    await RisingEdge(dut.hclk)
    assert dut.wb_ack.value == 1, "Expected wb_ack after data wait states"
    assert int(dut.wb_datrd.value) == 0xCAFEBABE, "Read data mismatch"

    dut.wb_cyc.value = 0
    dut.wb_stb.value = 0
    await RisingEdge(dut.hclk)


# ===========================================================================
# Test: AHB wait states during burst (covers BURST_PIPE HREADY=0)
# ===========================================================================
@cocotb.test()
async def test_ahb_wait_state_burst_pipe(dut):
    """HREADY=0 during burst pipe phase should delay ACK but burst continues."""
    clock = Clock(dut.hclk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset_dut_manual_ahb(dut)

    dut.wb_cyc.value = 1
    dut.wb_stb.value = 1
    dut.wb_we.value  = 1
    dut.wb_sel.value = 0xF
    dut.wb_cti.value = CTI_INCR
    dut.hready.value = 1
    dut.hresp.value  = 0
    dut.wb_adr.value = 0x600
    dut.wb_datwr.value = 0x11111111

    await RisingEdge(dut.hclk)  # IDLE -> ADDR
    await RisingEdge(dut.hclk)  # ADDR -> BURST_PIPE

    # Beat 0: insert wait state before ACK
    dut.hready.value = 0
    await RisingEdge(dut.hclk)
    assert dut.wb_ack.value == 0, "No ACK during burst wait state"
    assert int(dut.htrans.value) == HTRANS_SEQ, "Should maintain SEQ during wait"

    dut.hready.value = 1
    await RisingEdge(dut.hclk)
    assert dut.wb_ack.value == 1, "ACK for beat 0 after wait state"

    # Beats 1, 2: normal
    dut.wb_adr.value = 0x604
    dut.wb_datwr.value = 0x22222222
    await RisingEdge(dut.hclk)
    assert dut.wb_ack.value == 1, "ACK for beat 1"

    dut.wb_adr.value = 0x608
    dut.wb_datwr.value = 0x33333333
    dut.wb_cti.value = CTI_INCR
    await RisingEdge(dut.hclk)
    assert dut.wb_ack.value == 1, "ACK for beat 2"

    # Beat 3: final
    dut.wb_adr.value = 0x60C
    dut.wb_datwr.value = 0x44444444
    dut.wb_cti.value = CTI_EOB
    await RisingEdge(dut.hclk)  # BURST_LAST
    assert dut.wb_ack.value == 1, "ACK for beat 3"

    dut.wb_cyc.value = 0
    dut.wb_stb.value = 0
    dut.wb_cti.value = CTI_CLASSIC
    await RisingEdge(dut.hclk)


# ===========================================================================
# Test: WB request without HREADY (covers IDLE with wb_request && !mHREADY)
# ===========================================================================
@cocotb.test()
async def test_wb_request_hready_low(dut):
    """WB request when HREADY=0 should not start transfer."""
    clock = Clock(dut.hclk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset_dut_manual_ahb(dut)

    # Hold HREADY low
    dut.hready.value = 0

    dut.wb_cyc.value = 1
    dut.wb_stb.value = 1
    dut.wb_we.value  = 1
    dut.wb_adr.value = 0x700
    dut.wb_datwr.value = 0xAAAAAAAA
    dut.wb_sel.value = 0xF
    dut.wb_cti.value = CTI_CLASSIC

    # Wait a few cycles -- bridge should stay in IDLE
    for _ in range(3):
        await RisingEdge(dut.hclk)
        assert int(dut.htrans.value) == HTRANS_IDLE, \
            "Bridge should not start transfer when HREADY=0"
        assert dut.wb_ack.value == 0, "No ACK when bus is busy"

    # Release HREADY -- now transfer should proceed
    dut.hready.value = 1
    await RisingEdge(dut.hclk)  # IDLE -> ADDR
    await RisingEdge(dut.hclk)  # ADDR -> SINGLE_DATA
    await RisingEdge(dut.hclk)  # SINGLE_DATA: ACK
    assert dut.wb_ack.value == 1, "Expected ACK after HREADY released"

    dut.wb_cyc.value = 0
    dut.wb_stb.value = 0
    await RisingEdge(dut.hclk)


# ===========================================================================
# Test: Toggle mHREADY 0->1 and 1->0 (coverage toggle target)
# ===========================================================================
@cocotb.test()
async def test_hready_toggle(dut):
    """Exercise HREADY toggling to improve toggle coverage."""
    clock = Clock(dut.hclk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset_dut_manual_ahb(dut)

    # Toggle HREADY multiple times
    for _ in range(5):
        dut.hready.value = 0
        await RisingEdge(dut.hclk)
        dut.hready.value = 1
        await RisingEdge(dut.hclk)

    # Do a transfer to verify bridge still works
    dut.wb_cyc.value = 1
    dut.wb_stb.value = 1
    dut.wb_we.value  = 1
    dut.wb_adr.value = 0x800
    dut.wb_datwr.value = 0x55555555
    dut.wb_sel.value = 0xF
    dut.wb_cti.value = CTI_CLASSIC

    await RisingEdge(dut.hclk)
    await RisingEdge(dut.hclk)
    await RisingEdge(dut.hclk)
    assert dut.wb_ack.value == 1

    dut.wb_cyc.value = 0
    dut.wb_stb.value = 0
    await RisingEdge(dut.hclk)


# ===========================================================================
# Test: Use upper address bits to improve toggle coverage
# ===========================================================================
@cocotb.test()
async def test_upper_address_toggle(dut):
    """Exercise upper address bits for toggle coverage."""
    clock = Clock(dut.hclk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset_dut_manual_ahb(dut)

    # Use addresses with upper bits set
    addresses = [0x00001000, 0xFFFFF000, 0xAAAAA000, 0x55555000]

    for addr in addresses:
        dut.wb_cyc.value = 1
        dut.wb_stb.value = 1
        dut.wb_we.value  = 1
        dut.wb_adr.value = addr
        dut.wb_datwr.value = addr
        dut.wb_sel.value = 0xF
        dut.wb_cti.value = CTI_CLASSIC
        dut.hready.value = 1

        await RisingEdge(dut.hclk)  # IDLE -> ADDR
        await RisingEdge(dut.hclk)  # ADDR -> SINGLE_DATA
        await RisingEdge(dut.hclk)  # ACK
        assert dut.wb_ack.value == 1

        dut.wb_cyc.value = 0
        dut.wb_stb.value = 0
        await RisingEdge(dut.hclk)
