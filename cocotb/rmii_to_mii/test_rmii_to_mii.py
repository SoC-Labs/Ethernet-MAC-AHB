"""
Cocotb tests for the rmii_to_mii adapter (Layer 4).

Tests the RMII (2-bit, 50 MHz) to MII (4-bit, 25 MHz) conversion by
directly driving and sampling signals.
"""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, FallingEdge, ClockCycles, Timer


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

async def reset_dut(dut, cycles=5):
    """Assert reset for a number of clock cycles."""
    dut.RESETn.value = 0
    dut.rmii_rxd.value = 0
    dut.rmii_crs_dv.value = 0
    dut.mtxd.value = 0
    dut.mtxen.value = 0
    dut.mtxerr.value = 0
    await ClockCycles(dut.rmii_ref_clk, cycles)
    dut.RESETn.value = 1
    await ClockCycles(dut.rmii_ref_clk, 2)


# ---------------------------------------------------------------------------
# Test 4.1: Clock division
# ---------------------------------------------------------------------------
@cocotb.test()
async def test_clock_division(dut):
    """Verify mtx_clk/mrx_clk toggle at half the 50 MHz ref_clk rate."""
    clock = Clock(dut.rmii_ref_clk, 20, units="ns")  # 50 MHz
    cocotb.start_soon(clock.start())

    await reset_dut(dut)

    # Sample mtx_clk over several ref_clk cycles
    prev_mtx = int(dut.mtx_clk.value)
    toggles = 0

    for _ in range(20):
        await RisingEdge(dut.rmii_ref_clk)
        curr_mtx = int(dut.mtx_clk.value)
        if curr_mtx != prev_mtx:
            toggles += 1
        prev_mtx = curr_mtx

    # mtx_clk should toggle every ref_clk cycle (20 ref edges -> 20 toggles)
    dut._log.info(f"mtx_clk toggled {toggles} times in 20 ref_clk cycles")
    assert toggles == 20, \
        f"Expected 20 toggles (div-by-2), got {toggles}"

    # Verify mrx_clk matches mtx_clk
    assert dut.mtx_clk.value == dut.mrx_clk.value, \
        "mtx_clk and mrx_clk should be identical"


# ---------------------------------------------------------------------------
# Test 4.2: TX nibble serialisation
# ---------------------------------------------------------------------------
@cocotb.test()
async def test_tx_nibble_serialisation(dut):
    """Drive 4-bit MII TX data, verify 2-bit RMII output sequence."""
    clock = Clock(dut.rmii_ref_clk, 20, units="ns")  # 50 MHz
    cocotb.start_soon(clock.start())

    await reset_dut(dut)

    # Drive MII TX: nibble 0xB (1011) continuously
    dut.mtxd.value = 0xB
    dut.mtxen.value = 1

    # Let it run for several full cycles to establish steady state
    await ClockCycles(dut.rmii_ref_clk, 8)

    # Now sample two consecutive RMII ref_clk cycles to get both phases.
    # The adapter alternates: phase0 sends low nibble, phase1 sends high nibble.
    # We collect two samples and identify which is low/high.
    await RisingEdge(dut.rmii_ref_clk)
    sample_a = int(dut.rmii_txd.value)
    tx_en_a = int(dut.rmii_tx_en.value)

    await RisingEdge(dut.rmii_ref_clk)
    sample_b = int(dut.rmii_txd.value)
    tx_en_b = int(dut.rmii_tx_en.value)

    dut._log.info(f"RMII TX samples: a={sample_a:#04b}, b={sample_b:#04b}")
    dut._log.info(f"RMII TX_EN: a={tx_en_a}, b={tx_en_b}")

    # Verify TX enable is propagated on both phases
    assert tx_en_a == 1, "rmii_tx_en should be 1 during transmission"
    assert tx_en_b == 1, "rmii_tx_en should be 1 during transmission"

    # One sample should be the low nibble (0b11) and the other the high (0b10)
    # 0xB = 4'b1011 -> low=2'b11=3, high=2'b10=2
    samples = {sample_a, sample_b}
    assert samples == {0b11, 0b10}, \
        f"Expected RMII samples {{0b11, 0b10}}, got {{{sample_a:#04b}, {sample_b:#04b}}}"


# ---------------------------------------------------------------------------
# Test 4.3: RX nibble deserialisation
# ---------------------------------------------------------------------------
@cocotb.test()
async def test_rx_nibble_deserialisation(dut):
    """Drive 2-bit RMII RX data, verify 4-bit MII output."""
    clock = Clock(dut.rmii_ref_clk, 20, units="ns")  # 50 MHz
    cocotb.start_soon(clock.start())

    await reset_dut(dut)

    # Ensure MII TX is idle
    dut.mtxd.value = 0
    dut.mtxen.value = 0
    dut.mtxerr.value = 0

    # The adapter collects two 2-bit samples per MII nibble.
    # Internal rx_phase alternates 0,1,0,1... after reset.
    # Phase 0: captures rx_data_low = rmii_rxd
    # Phase 1: combines mrxd = {rmii_rxd, rx_data_low}
    #
    # To send nibble 0x7 = 4'b0111 = {high=01, low=11}:
    # We need low=0b11 on phase 0 and high=0b01 on phase 1.
    #
    # Drive a steady pattern for several cycles so we capture
    # at least one correct assembly regardless of initial phase.

    # Alternate between low and high dibits for multiple cycles
    for _ in range(4):
        dut.rmii_rxd.value = 0b11  # low dibit
        dut.rmii_crs_dv.value = 1
        await RisingEdge(dut.rmii_ref_clk)

        dut.rmii_rxd.value = 0b01  # high dibit
        dut.rmii_crs_dv.value = 1
        await RisingEdge(dut.rmii_ref_clk)

    # Allow final output to register
    await RisingEdge(dut.rmii_ref_clk)

    mrxd_val = int(dut.mrxd.value)
    mrxdv_val = int(dut.mrxdv.value)
    dut._log.info(f"MII RX: mrxd=0x{mrxd_val:X}, mrxdv={mrxdv_val}")

    # The combined nibble should be {high, low} = {01, 11} = 0111 = 0x7
    # OR if phase was off by one: {11, 01} = 1101 = 0xD
    # Check both valid assemblies — both confirm the adapter works,
    # just with a different phase alignment
    assert mrxd_val in (0x7, 0xD), \
        f"Expected mrxd=0x7 or 0xD (phase-dependent), got 0x{mrxd_val:X}"
    assert mrxdv_val == 1, "Expected mrxdv=1 during reception"


# ---------------------------------------------------------------------------
# Test 4.4: TX enable propagation
# ---------------------------------------------------------------------------
@cocotb.test()
async def test_tx_enable_propagation(dut):
    """MII txen should map to RMII tx_en over both phases."""
    clock = Clock(dut.rmii_ref_clk, 20, units="ns")
    cocotb.start_soon(clock.start())

    await reset_dut(dut)

    # TX disabled
    dut.mtxen.value = 0
    dut.mtxd.value = 0
    await ClockCycles(dut.rmii_ref_clk, 4)
    assert dut.rmii_tx_en.value == 0, "rmii_tx_en should be 0 when mtxen=0"

    # TX enabled
    dut.mtxen.value = 1
    dut.mtxd.value = 0xF
    await ClockCycles(dut.rmii_ref_clk, 4)
    assert dut.rmii_tx_en.value == 1, "rmii_tx_en should be 1 when mtxen=1"


# ---------------------------------------------------------------------------
# Test 4.5: CRS_DV to CRS/RxDV decode
# ---------------------------------------------------------------------------
@cocotb.test()
async def test_crs_dv_decode(dut):
    """RMII crs_dv should map to MII mcrs and mrxdv."""
    clock = Clock(dut.rmii_ref_clk, 20, units="ns")
    cocotb.start_soon(clock.start())

    await reset_dut(dut)

    # CRS_DV deasserted
    dut.rmii_crs_dv.value = 0
    dut.rmii_rxd.value = 0
    dut.mtxen.value = 0
    await ClockCycles(dut.rmii_ref_clk, 4)
    assert dut.mcrs.value == 0, "mcrs should be 0 when crs_dv=0"

    # CRS_DV asserted
    dut.rmii_crs_dv.value = 1
    await ClockCycles(dut.rmii_ref_clk, 4)
    assert dut.mcrs.value == 1, "mcrs should be 1 when crs_dv=1"


# ---------------------------------------------------------------------------
# Test 4.6: Collision detection
# ---------------------------------------------------------------------------
@cocotb.test()
async def test_collision_detection(dut):
    """Simultaneous TX and RX should assert mcoll."""
    clock = Clock(dut.rmii_ref_clk, 20, units="ns")
    cocotb.start_soon(clock.start())

    await reset_dut(dut)

    # No collision: TX active, RX idle
    dut.mtxen.value = 1
    dut.mtxd.value = 0x5
    dut.rmii_crs_dv.value = 0
    await ClockCycles(dut.rmii_ref_clk, 4)
    assert dut.mcoll.value == 0, "mcoll should be 0 when only TX active"

    # Collision: both TX and RX active
    dut.rmii_crs_dv.value = 1
    dut.rmii_rxd.value = 0x3
    await ClockCycles(dut.rmii_ref_clk, 4)
    assert dut.mcoll.value == 1, "mcoll should be 1 when TX and RX both active"

    # No collision: TX idle, RX active
    dut.mtxen.value = 0
    await ClockCycles(dut.rmii_ref_clk, 4)
    assert dut.mcoll.value == 0, "mcoll should be 0 when only RX active"


# ---------------------------------------------------------------------------
# Test 4.7: Reset behaviour
# ---------------------------------------------------------------------------
@cocotb.test()
async def test_reset_behaviour(dut):
    """All outputs should clear on reset."""
    clock = Clock(dut.rmii_ref_clk, 20, units="ns")
    cocotb.start_soon(clock.start())

    # First bring out of reset and drive some activity
    await reset_dut(dut)
    dut.mtxen.value = 1
    dut.mtxd.value = 0xF
    dut.rmii_crs_dv.value = 1
    dut.rmii_rxd.value = 0x3
    await ClockCycles(dut.rmii_ref_clk, 6)

    # Assert reset
    dut.RESETn.value = 0
    await ClockCycles(dut.rmii_ref_clk, 3)

    # Verify all outputs are 0
    assert dut.rmii_txd.value == 0, "rmii_txd should be 0 in reset"
    assert dut.rmii_tx_en.value == 0, "rmii_tx_en should be 0 in reset"
    assert dut.mrxd.value == 0, "mrxd should be 0 in reset"
    assert dut.mrxdv.value == 0, "mrxdv should be 0 in reset"
    assert dut.mrxerr.value == 0, "mrxerr should be 0 in reset"
    assert dut.mcrs.value == 0, "mcrs should be 0 in reset"
    assert dut.mcoll.value == 0, "mcoll should be 0 in reset"
