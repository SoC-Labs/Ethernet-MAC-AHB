"""
Cocotb tests for the wb_to_ahb3lite bridge.

Tests the rewritten WISHBONE B3 master to AHB3-Lite master bridge using:
  - cocotbext-wishbone WishboneMaster for classic single-beat WB cycles
  - Manual signal driving for WB B3 burst cycles (CTI/BTE)
  - cocotbext-ahb AHBLiteSlaveRAM to respond on the AHB side
"""

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
