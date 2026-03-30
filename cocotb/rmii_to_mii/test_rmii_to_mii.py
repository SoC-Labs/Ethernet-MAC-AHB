"""
Cocotb tests for the rmii_to_mii adapter (Layer 4).

Tests the RMII (2-bit, 50 MHz) to MII (4-bit, 25 MHz) conversion.
The implementation uses proper RMII CRS_DV decoding, an 8-stage reset
synchroniser, and pipelined TX/RX paths.
"""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, FallingEdge, ClockCycles, Timer


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# The reset synchroniser is an 8-stage shift register; after RESETn
# deasserts it takes 9 ref_clk cycles for the internal rstn_sync to go
# high plus a couple extra for downstream logic to settle.
RESET_SYNC_CYCLES = 12


async def reset_dut(dut, cycles=5):
    """Assert reset for *cycles* ref_clk edges, then wait for the internal
    reset synchroniser to fully deassert."""
    dut.RESETn.value = 0
    dut.rmii_rxd.value = 0
    dut.rmii_crs_dv.value = 0
    dut.mtxd.value = 0
    dut.mtxen.value = 0
    dut.mtxerr.value = 0
    await ClockCycles(dut.rmii_ref_clk, cycles)
    dut.RESETn.value = 1
    await ClockCycles(dut.rmii_ref_clk, RESET_SYNC_CYCLES)


# ---------------------------------------------------------------------------
# Test 4.1: Clock division
# ---------------------------------------------------------------------------
@cocotb.test()
async def test_clock_division(dut):
    """Verify mtx_clk and mrx_clk toggle at half the 50 MHz ref_clk rate."""
    clock = Clock(dut.rmii_ref_clk, 20, units="ns")  # 50 MHz
    cocotb.start_soon(clock.start())

    await reset_dut(dut)

    # mtx_clk and mrx_clk are separate divide-by-2 registers that both
    # start at 0 and toggle every ref_clk edge, so they should toggle
    # on every single ref_clk rising edge.
    prev_mtx = int(dut.mtx_clk.value)
    prev_mrx = int(dut.mrx_clk.value)
    mtx_toggles = 0
    mrx_toggles = 0

    for _ in range(20):
        await RisingEdge(dut.rmii_ref_clk)
        curr_mtx = int(dut.mtx_clk.value)
        curr_mrx = int(dut.mrx_clk.value)
        if curr_mtx != prev_mtx:
            mtx_toggles += 1
        if curr_mrx != prev_mrx:
            mrx_toggles += 1
        prev_mtx = curr_mtx
        prev_mrx = curr_mrx

    dut._log.info(f"mtx_clk toggled {mtx_toggles}, "
                  f"mrx_clk toggled {mrx_toggles} in 20 ref_clk cycles")
    assert mtx_toggles == 20, \
        f"Expected 20 mtx_clk toggles (div-by-2), got {mtx_toggles}"
    assert mrx_toggles == 20, \
        f"Expected 20 mrx_clk toggles (div-by-2), got {mrx_toggles}"


# ---------------------------------------------------------------------------
# Test 4.2: TX nibble serialisation
# ---------------------------------------------------------------------------
@cocotb.test()
async def test_tx_nibble_serialisation(dut):
    """Drive 4-bit MII TX data and verify 2-bit RMII output sequence.

    The TX path latches the 4-bit MII data aligned to the internal
    mtx_clk, splits it into two di-bits, and outputs them through an
    additional pipeline register.  For nibble 0xB = 4'b1011 the RMII
    output should alternate between 2'b11 (low) and 2'b10 (high).
    """
    clock = Clock(dut.rmii_ref_clk, 20, units="ns")
    cocotb.start_soon(clock.start())

    await reset_dut(dut)

    # Drive MII TX continuously
    dut.mtxd.value = 0xB
    dut.mtxen.value = 1

    # Allow the TX pipeline to fill (generate stage + output buffer)
    await ClockCycles(dut.rmii_ref_clk, 10)

    # Collect several consecutive samples
    samples = []
    for _ in range(6):
        await RisingEdge(dut.rmii_ref_clk)
        samples.append(int(dut.rmii_txd.value))

    dut._log.info(f"RMII TX samples: {[f'{s:#04b}' for s in samples]}")

    # Both di-bits of 0xB must appear: low = 2'b11 = 3, high = 2'b10 = 2
    assert 0b11 in samples, \
        f"Expected low di-bit 0b11 in samples {samples}"
    assert 0b10 in samples, \
        f"Expected high di-bit 0b10 in samples {samples}"
    assert dut.rmii_tx_en.value == 1, "rmii_tx_en should be 1 during TX"


# ---------------------------------------------------------------------------
# Test 4.3: RX nibble deserialisation
# ---------------------------------------------------------------------------
@cocotb.test()
async def test_rx_nibble_deserialisation(dut):
    """Drive a proper RMII receive frame and verify MII nibble assembly.

    The new RX path performs full CRS_DV decoding:
      1.  crs_dv=1 with rxd=00 is treated as carrier-sense / preamble.
      2.  When two consecutive non-zero di-bits are seen (rxd_rr!=0 and
          rxd_r!=0 while crs_dv=1) the parser enters data mode and
          assembles nibbles as {rxd_r, rxd_rr}.

    We drive: 6 cycles of preamble (rxd=00), then alternating 0b11/0b10
    data di-bits.  The expected assembled nibble is {0b10, 0b11} = 0xB.
    """
    clock = Clock(dut.rmii_ref_clk, 20, units="ns")
    cocotb.start_soon(clock.start())

    await reset_dut(dut)

    dut.mtxen.value = 0
    dut.mtxd.value = 0
    dut.mtxerr.value = 0

    # Drive preamble: crs_dv=1, rxd=00 (carrier sense only)
    dut.rmii_crs_dv.value = 1
    dut.rmii_rxd.value = 0b00
    await ClockCycles(dut.rmii_ref_clk, 6)

    # Drive data di-bits and simultaneously collect MII RX output
    collected_nibbles = []
    for i in range(40):
        dut.rmii_rxd.value = 0b11 if (i % 2 == 0) else 0b10
        await RisingEdge(dut.rmii_ref_clk)
        if int(dut.mrxdv.value) == 1:
            collected_nibbles.append(int(dut.mrxd.value))

    dut._log.info(f"Collected MII RX nibbles: "
                  f"{[f'0x{n:X}' for n in collected_nibbles]}")

    assert len(collected_nibbles) > 0, \
        "Expected at least one valid MII RX nibble"
    assert 0xB in collected_nibbles, \
        f"Expected assembled nibble 0xB in {collected_nibbles}"


# ---------------------------------------------------------------------------
# Test 4.4: TX enable propagation
# ---------------------------------------------------------------------------
@cocotb.test()
async def test_tx_enable_propagation(dut):
    """MII txen should propagate to RMII tx_en through the TX pipeline."""
    clock = Clock(dut.rmii_ref_clk, 20, units="ns")
    cocotb.start_soon(clock.start())

    await reset_dut(dut)

    # TX disabled
    dut.mtxen.value = 0
    dut.mtxd.value = 0
    await ClockCycles(dut.rmii_ref_clk, 6)
    assert dut.rmii_tx_en.value == 0, \
        "rmii_tx_en should be 0 when mtxen=0"

    # TX enabled — allow pipeline to fill
    dut.mtxen.value = 1
    dut.mtxd.value = 0xF
    await ClockCycles(dut.rmii_ref_clk, 6)
    assert dut.rmii_tx_en.value == 1, \
        "rmii_tx_en should be 1 when mtxen=1"

    # TX disabled again — allow pipeline to drain
    dut.mtxen.value = 0
    dut.mtxd.value = 0
    await ClockCycles(dut.rmii_ref_clk, 6)
    assert dut.rmii_tx_en.value == 0, \
        "rmii_tx_en should be 0 after mtxen deasserted"


# ---------------------------------------------------------------------------
# Test 4.5: CRS_DV to CRS decode
# ---------------------------------------------------------------------------
@cocotb.test()
async def test_crs_dv_decode(dut):
    """RMII crs_dv=1 with rxd=00 should assert carrier sense (mcrs).

    Per the RMII specification, crs_dv=1 with rxd=00 indicates carrier
    sense (preamble) without valid data.  The parser decodes this and
    drives the MII mcrs signal after pipeline latency.
    """
    clock = Clock(dut.rmii_ref_clk, 20, units="ns")
    cocotb.start_soon(clock.start())

    await reset_dut(dut)

    dut.mtxen.value = 0

    # CRS_DV deasserted — mcrs should be low
    dut.rmii_crs_dv.value = 0
    dut.rmii_rxd.value = 0
    await ClockCycles(dut.rmii_ref_clk, 8)
    assert dut.mcrs.value == 0, "mcrs should be 0 when crs_dv=0"

    # CRS_DV asserted with rxd=00 → carrier sense (preamble)
    dut.rmii_crs_dv.value = 1
    dut.rmii_rxd.value = 0b00
    await ClockCycles(dut.rmii_ref_clk, 8)
    assert dut.mcrs.value == 1, \
        "mcrs should be 1 for carrier sense (crs_dv=1, rxd=00)"

    # CRS_DV deasserted — mcrs should return low
    dut.rmii_crs_dv.value = 0
    dut.rmii_rxd.value = 0
    await ClockCycles(dut.rmii_ref_clk, 8)
    assert dut.mcrs.value == 0, \
        "mcrs should be 0 after crs_dv deasserted"


# ---------------------------------------------------------------------------
# Test 4.6: Collision detection
# ---------------------------------------------------------------------------
@cocotb.test()
async def test_collision_detection(dut):
    """Collision is flagged when both TX is active and carrier sense is
    detected on the RX side.  mcoll = rx_crs & rmii_txen_i (internal)."""
    clock = Clock(dut.rmii_ref_clk, 20, units="ns")
    cocotb.start_soon(clock.start())

    await reset_dut(dut)

    # TX active, RX idle → no collision
    dut.mtxen.value = 1
    dut.mtxd.value = 0x5
    dut.rmii_crs_dv.value = 0
    dut.rmii_rxd.value = 0
    await ClockCycles(dut.rmii_ref_clk, 8)
    assert dut.mcoll.value == 0, \
        "mcoll should be 0 when only TX active"

    # TX active + carrier sense (crs_dv=1, rxd=00) → collision
    dut.rmii_crs_dv.value = 1
    dut.rmii_rxd.value = 0b00
    await ClockCycles(dut.rmii_ref_clk, 8)
    assert dut.mcoll.value == 1, \
        "mcoll should be 1 when TX and carrier sense both active"

    # TX idle, carrier sense still present → no collision
    dut.mtxen.value = 0
    dut.mtxd.value = 0
    await ClockCycles(dut.rmii_ref_clk, 8)
    assert dut.mcoll.value == 0, \
        "mcoll should be 0 when only carrier sense active"


# ---------------------------------------------------------------------------
# Test 4.7: Reset behaviour
# ---------------------------------------------------------------------------
@cocotb.test()
async def test_reset_behaviour(dut):
    """All outputs should clear when RESETn is asserted.

    The internal reset synchroniser propagates asynchronously on assert
    (all stages clear immediately), so outputs go low within a few
    ref_clk cycles of RESETn going low.
    """
    clock = Clock(dut.rmii_ref_clk, 20, units="ns")
    cocotb.start_soon(clock.start())

    # Bring out of reset and drive activity
    await reset_dut(dut)
    dut.mtxen.value = 1
    dut.mtxd.value = 0xF
    dut.rmii_crs_dv.value = 1
    dut.rmii_rxd.value = 0x3
    await ClockCycles(dut.rmii_ref_clk, 10)

    # Assert reset
    dut.RESETn.value = 0
    await ClockCycles(dut.rmii_ref_clk, 5)

    # Verify all outputs are 0
    assert dut.rmii_txd.value == 0, "rmii_txd should be 0 in reset"
    assert dut.rmii_tx_en.value == 0, "rmii_tx_en should be 0 in reset"
    assert dut.mrxd.value == 0, "mrxd should be 0 in reset"
    assert dut.mrxdv.value == 0, "mrxdv should be 0 in reset"
    assert dut.mrxerr.value == 0, "mrxerr should be 0 in reset"
    assert dut.mcrs.value == 0, "mcrs should be 0 in reset"
    assert dut.mcoll.value == 0, "mcoll should be 0 in reset"
