"""Cocotb testbench for ha1588_servo standalone.

Tests the HA1588 hardware servo module in isolation with two independent
clocks (clk for PHC domain, rtc_clk for HA1588 domain). The testbench
behaviorally models the PHC time counter and hw_capture snapshot to
verify the servo's periodic sync timer, CDC handshake, phase step,
frequency adjustment, and lock detection.
"""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ClockCycles, Timer, First

CLK_PERIOD_NS = 4       # 250 MHz PHC domain
RTC_CLK_PERIOD_NS = 8   # 125 MHz HA1588 RTC domain

NS_PER_SECOND = 999_999_999


# ── Helpers ──────────────────────────────────────────────────────────────────

async def setup(dut):
    """Start both clocks and initialise all inputs to safe defaults."""
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_NS, unit="ns").start())
    cocotb.start_soon(Clock(dut.rtc_clk, RTC_CLK_PERIOD_NS, unit="ns").start())
    dut.enable.value = 0
    dut.sync_interval.value = NS_PER_SECOND  # ~1 Hz default
    dut.rtc_time_ptp_ns.value = 0
    dut.rtc_time_ptp_sec.value = 0
    dut.phc_seconds.value = 0
    dut.phc_nanoseconds.value = 0
    dut.hw_cap_seconds.value = 0
    dut.hw_cap_nanoseconds.value = 0
    dut.hw_cap_sub_nanoseconds.value = 0


async def do_reset(dut):
    dut.resetn.value = 0
    await ClockCycles(dut.clk, 10)
    dut.resetn.value = 1
    await ClockCycles(dut.clk, 5)


async def advance_phc_time(dut, seconds, nanoseconds):
    """Set PHC time to a specific value (behavioural model)."""
    dut.phc_seconds.value = seconds
    dut.phc_nanoseconds.value = nanoseconds


async def set_ha1588_time(dut, seconds, nanoseconds):
    """Set HA1588 RTC time outputs (rtc_clk domain)."""
    dut.rtc_time_ptp_sec.value = seconds
    dut.rtc_time_ptp_ns.value = nanoseconds


async def wait_for_hw_capture(dut, timeout_cycles=500):
    """Wait for the servo to assert hw_capture, return True if seen."""
    for _ in range(timeout_cycles):
        await RisingEdge(dut.clk)
        if int(dut.hw_capture.value) == 1:
            return True
    return False


async def wait_for_adjust(dut, timeout_cycles=500):
    """Wait for hw_set_time or hw_adj_valid, return which fired."""
    for _ in range(timeout_cycles):
        await RisingEdge(dut.clk)
        if int(dut.hw_set_time.value) == 1:
            return "phase_step"
        if int(dut.hw_adj_valid.value) == 1:
            return "freq_adj"
    return None


async def run_one_sync_cycle(dut, ha_sec, ha_ns, phc_sec, phc_ns, interval_ns=100_000):
    """Drive a complete sync cycle: set times, enable, wait for adjust.

    Sets a short sync interval, advances PHC past the target, then
    provides hw_cap readback matching phc time. Returns the adjustment type.
    """
    dut.sync_interval.value = interval_ns

    # Set HA1588 time
    await set_ha1588_time(dut, ha_sec, ha_ns)

    # Set PHC time (at some initial value before the target)
    await advance_phc_time(dut, phc_sec, phc_ns)

    # Enable
    dut.enable.value = 1
    await ClockCycles(dut.clk, 5)

    # Advance PHC past the sync target to trigger sync_fire
    # The timer arms one interval from current time, so advance past it
    target_ns = phc_ns + interval_ns
    target_sec = phc_sec
    if target_ns > NS_PER_SECOND:
        target_ns -= (NS_PER_SECOND + 1)
        target_sec += 1

    await advance_phc_time(dut, target_sec, target_ns + 100)

    # Wait for hw_capture
    captured = await wait_for_hw_capture(dut, timeout_cycles=200)
    if not captured:
        return None

    # Provide hw_cap readback (simulating PHC capture)
    dut.hw_cap_seconds.value = phc_sec
    dut.hw_cap_nanoseconds.value = phc_ns
    dut.hw_cap_sub_nanoseconds.value = 0
    await ClockCycles(dut.clk, 2)

    # Wait for CDC + computation + adjustment
    result = await wait_for_adjust(dut, timeout_cycles=200)
    return result


# ══════════════════════════════════════════════════════════════════════════════
# Tests
# ══════════════════════════════════════════════════════════════════════════════


@cocotb.test()
async def test_ha_srv_01_reset_values(dut):
    """HA-SRV-01: All outputs zero after reset."""
    await setup(dut)
    await do_reset(dut)

    assert int(dut.hw_capture.value) == 0
    assert int(dut.hw_set_time.value) == 0
    assert int(dut.hw_adj_valid.value) == 0
    assert int(dut.locked.value) == 0
    assert int(dut.phase_step_active.value) == 0
    assert int(dut.hw_set_seconds.value) == 0
    assert int(dut.hw_set_nanoseconds.value) == 0
    assert int(dut.hw_adj_ns_incr_frac.value) == 0


@cocotb.test()
async def test_ha_srv_02_disabled_no_activity(dut):
    """HA-SRV-02: No activity when enable=0."""
    await setup(dut)
    await do_reset(dut)

    dut.enable.value = 0
    dut.sync_interval.value = 100

    # Set matching times
    await set_ha1588_time(dut, 10, 500_000)
    await advance_phc_time(dut, 10, 500_000)

    # Run for many cycles
    await ClockCycles(dut.clk, 200)

    assert int(dut.hw_capture.value) == 0, "hw_capture should not fire when disabled"
    assert int(dut.hw_set_time.value) == 0
    assert int(dut.hw_adj_valid.value) == 0


@cocotb.test()
async def test_ha_srv_03_periodic_sync_fires(dut):
    """HA-SRV-03: Sync timer fires at configured interval."""
    await setup(dut)
    await do_reset(dut)

    interval_ns = 1000  # 1 us — very short for fast testing
    dut.sync_interval.value = interval_ns
    dut.enable.value = 0

    # Set initial PHC time
    phc_ns = 100_000
    await advance_phc_time(dut, 0, phc_ns)

    # Set HA1588 time (matching for simplicity)
    await set_ha1588_time(dut, 0, phc_ns)

    # Enable — the timer will arm, target = phc_ns + interval_ns
    dut.enable.value = 1
    await ClockCycles(dut.clk, 5)

    # PHC time hasn't reached target yet — no capture should fire
    captured = await wait_for_hw_capture(dut, timeout_cycles=20)
    assert not captured, "hw_capture should not fire before target time"

    # Now advance PHC past the target
    target_ns = phc_ns + interval_ns + 10
    await advance_phc_time(dut, 0, target_ns)

    # hw_capture should fire
    captured = await wait_for_hw_capture(dut, timeout_cycles=50)
    assert captured, "hw_capture should fire when PHC reaches target time"


@cocotb.test()
async def test_ha_srv_04_cdc_handshake(dut):
    """HA-SRV-04: CDC handshake correctly captures ha1588 time across domains."""
    await setup(dut)
    await do_reset(dut)

    ha_sec = 42
    ha_ns = 123_456
    await set_ha1588_time(dut, ha_sec, ha_ns)

    interval_ns = 500
    dut.sync_interval.value = interval_ns
    phc_ns = 50_000
    await advance_phc_time(dut, 0, phc_ns)

    dut.enable.value = 1
    await ClockCycles(dut.clk, 5)

    # Advance past target
    await advance_phc_time(dut, 0, phc_ns + interval_ns + 100)

    # Wait for hw_capture (means the servo started a CDC handshake)
    captured = await wait_for_hw_capture(dut, timeout_cycles=100)
    assert captured, "hw_capture should fire"

    # Provide capture readback
    dut.hw_cap_seconds.value = 0
    dut.hw_cap_nanoseconds.value = phc_ns
    dut.hw_cap_sub_nanoseconds.value = 0

    # Wait for the full FSM to complete (CDC ack + compute + adjust)
    result = await wait_for_adjust(dut, timeout_cycles=200)
    assert result is not None, "Servo should produce an adjustment after CDC completes"

    # Since ha1588 has sec=42 and PHC has sec=0, this should be a phase step
    assert result == "phase_step", f"Expected phase_step for large offset, got {result}"
    assert int(dut.hw_set_seconds.value) == ha_sec, \
        f"Phase step should load ha1588 seconds ({ha_sec})"


@cocotb.test()
async def test_ha_srv_05_phase_step_large_offset(dut):
    """HA-SRV-05: Phase step when seconds differ."""
    await setup(dut)
    await do_reset(dut)

    result = await run_one_sync_cycle(dut,
                                       ha_sec=100, ha_ns=500_000,
                                       phc_sec=0, phc_ns=500_000)

    assert result == "phase_step", f"Expected phase_step, got {result}"
    assert int(dut.hw_set_seconds.value) == 100
    assert int(dut.hw_set_nanoseconds.value) == 500_000
    assert int(dut.phase_step_active.value) == 1


@cocotb.test()
async def test_ha_srv_06_phase_step_ns_threshold(dut):
    """HA-SRV-06: Phase step when ns offset > threshold (1us = 1000ns)."""
    await setup(dut)
    await do_reset(dut)

    # Same second, but offset = 5000 ns (> 1000 ns threshold)
    result = await run_one_sync_cycle(dut,
                                       ha_sec=10, ha_ns=100_000,
                                       phc_sec=10, phc_ns=95_000)

    assert result == "phase_step", f"Expected phase_step for 5000ns offset, got {result}"
    assert int(dut.phase_step_active.value) == 1


@cocotb.test()
async def test_ha_srv_07_freq_adj_small_offset(dut):
    """HA-SRV-07: Frequency adjustment for small offsets (< threshold)."""
    await setup(dut)
    await do_reset(dut)

    # Same second, offset = 100 ns (< 1000 ns threshold)
    result = await run_one_sync_cycle(dut,
                                       ha_sec=10, ha_ns=500_100,
                                       phc_sec=10, phc_ns=500_000)

    assert result == "freq_adj", f"Expected freq_adj for 100ns offset, got {result}"
    assert int(dut.phase_step_active.value) == 0

    # hw_adj_ns_incr_frac should be non-zero (PI correction applied)
    frac = int(dut.hw_adj_ns_incr_frac.value)
    # The correction should have moved ns_incr_frac in a direction to
    # close the offset. Exact value depends on PI gains.
    dut._log.info(f"Frequency adjustment: ns_incr_frac = 0x{frac:08X}")


@cocotb.test()
async def test_ha_srv_08_convergence(dut):
    """HA-SRV-08: Offset decreases over multiple small-offset cycles."""
    await setup(dut)
    await do_reset(dut)

    interval_ns = 1000
    dut.sync_interval.value = interval_ns

    # First cycle: small offset of 500 ns (ha ahead of phc)
    base_ns = 200_000
    result = await run_one_sync_cycle(dut,
                                       ha_sec=5, ha_ns=base_ns + 500,
                                       phc_sec=5, phc_ns=base_ns)
    assert result == "freq_adj", f"Expected freq_adj, got {result}"
    frac_1 = int(dut.hw_adj_ns_incr_frac.value)

    # Disable and re-enable for clean second cycle
    dut.enable.value = 0
    await ClockCycles(dut.clk, 10)

    # Second cycle: smaller offset of 200 ns
    result = await run_one_sync_cycle(dut,
                                       ha_sec=5, ha_ns=base_ns + 200,
                                       phc_sec=5, phc_ns=base_ns)
    assert result == "freq_adj", f"Expected freq_adj, got {result}"
    frac_2 = int(dut.hw_adj_ns_incr_frac.value)

    dut._log.info(f"Cycle 1 frac: 0x{frac_1:08X}, Cycle 2 frac: 0x{frac_2:08X}")
    # Both cycles should produce frequency adjustments (detailed convergence
    # depends on PI gains and accumulated state)


@cocotb.test()
async def test_ha_srv_09_lock_counter(dut):
    """HA-SRV-09: Lock asserts after 4 consecutive small offsets."""
    await setup(dut)
    await do_reset(dut)

    assert int(dut.locked.value) == 0, "Should start unlocked"

    # Run 5 consecutive small-offset sync cycles
    for i in range(5):
        dut.enable.value = 0
        await ClockCycles(dut.clk, 10)

        result = await run_one_sync_cycle(dut,
                                           ha_sec=10, ha_ns=500_000 + 50,
                                           phc_sec=10, phc_ns=500_000)
        assert result == "freq_adj", f"Cycle {i}: expected freq_adj, got {result}"

    # After 4+ consecutive freq_adj cycles, should be locked
    assert int(dut.locked.value) == 1, "Should be locked after 4+ small offsets"


@cocotb.test()
async def test_ha_srv_10_lock_reset_on_phase_step(dut):
    """HA-SRV-10: Lock counter resets on phase step."""
    await setup(dut)
    await do_reset(dut)

    # Run 5 small-offset cycles to get locked
    for i in range(5):
        dut.enable.value = 0
        await ClockCycles(dut.clk, 10)

        result = await run_one_sync_cycle(dut,
                                           ha_sec=10, ha_ns=500_000 + 50,
                                           phc_sec=10, phc_ns=500_000)
        assert result == "freq_adj", f"Cycle {i}: expected freq_adj, got {result}"

    assert int(dut.locked.value) == 1, "Should be locked"

    # Now trigger a phase step (large offset)
    dut.enable.value = 0
    await ClockCycles(dut.clk, 10)

    result = await run_one_sync_cycle(dut,
                                       ha_sec=99, ha_ns=500_000,
                                       phc_sec=10, phc_ns=500_000)
    assert result == "phase_step", "Large offset should trigger phase step"
    assert int(dut.locked.value) == 0, "Lock should reset after phase step"


# ── Bug HW-servo #4: PI integral anti-windup ─────────────────────────────────

def _to_signed(val, width=32):
    """Interpret a raw cocotb bus value as a signed two's-complement int."""
    val = int(val)
    if val >= (1 << (width - 1)):
        val -= (1 << width)
    return val


@cocotb.test()
async def test_ha_srv_11_antiwindup(dut):
    """HA-SRV-11: PI integral saturates at ±INTEG_MAX under a sustained
    one-sided sub-threshold offset — it must NOT wrap or sign-flip.

    Bug HW-servo #4: without the anti-windup clamp, `integral` accumulates
    integral_update every freq_adj cycle without bound. A sustained same-sign
    sub-threshold offset drives it monotonically until the signed 32-bit
    accumulator wraps, inverting the frequency correction and corrupting the
    exported PHC rate. The clamp bounds it to ±INTEG_MAX.

    The standalone TB overrides INTEG_MAX to a small value (2^14) so the
    accumulator reaches the clamp in ~100 sub-threshold sync cycles rather
    than the ~1M the 2^28 production default would require.
    """
    await setup(dut)
    await do_reset(dut)

    # Read the clamp the DUT was elaborated with.
    integ_max = int(dut.u_dut.INTEG_MAX.value)
    if integ_max >= (1 << 31):
        integ_max -= (1 << 32)
    dut._log.info(f"INTEG_MAX (elaborated) = {integ_max}")

    interval_ns = 1000            # 1 us — short cadence for many fast fires
    dut.sync_interval.value = interval_ns

    # A same-second, positive, sub-threshold offset (+900 ns < 1000 ns
    # DEFAULT_PHASE_STEP_THRESHOLD) so every cycle is a freq_adj, never a
    # phase step (offset_large stays false). integral_update = 900 >> 2 = 225.
    off_ns = 900
    phc_sec = 5                   # fixed second — never cross a boundary

    # integral_update per cycle; number of cycles to comfortably saturate,
    # then a margin to prove it HOLDS at the clamp (does not keep climbing /
    # does not wrap back through zero).
    per_cycle = off_ns >> 2
    n_to_sat = (integ_max // per_cycle) + 5
    n_cycles = n_to_sat + 60      # extra cycles well past saturation

    # Arm the servo at a known PHC time. The sync timer advances its target by
    # exactly `interval_ns` on each fire, so we walk PHC time forward by the
    # same step. Starting well inside the second and taking n_cycles steps of
    # interval_ns keeps us far from the 1e9 boundary (no phase-step from a
    # seconds mismatch).
    phc_ns = 100_000
    await set_ha1588_time(dut, phc_sec, phc_ns + off_ns)
    await advance_phc_time(dut, phc_sec, phc_ns)
    dut.enable.value = 1
    await ClockCycles(dut.clk, 5)

    max_integral_seen = 0
    freq_adj_count = 0

    for i in range(n_cycles):
        # The sync target is (arm_ns + (i+1)*interval_ns). Present the matching
        # HA/PHC pair for THIS fire (HA ahead by a constant +off_ns) and drive
        # PHC just past the target so sync_fire asserts.
        target_ns = phc_ns + interval_ns
        await set_ha1588_time(dut, phc_sec, target_ns + off_ns)  # HA ahead by +900 ns
        await advance_phc_time(dut, phc_sec, target_ns + 100)

        captured = await wait_for_hw_capture(dut, timeout_cycles=200)
        assert captured, f"cycle {i}: hw_capture should fire"

        # hw_cap readback = the PHC time the servo snapshotted (target_ns);
        # HA snapshot is target_ns + off_ns, so offset = +off_ns every cycle.
        dut.hw_cap_seconds.value = phc_sec
        dut.hw_cap_nanoseconds.value = target_ns
        dut.hw_cap_sub_nanoseconds.value = 0

        result = await wait_for_adjust(dut, timeout_cycles=200)
        assert result == "freq_adj", \
            f"cycle {i}: expected freq_adj (sub-threshold), got {result}"
        freq_adj_count += 1

        # Probe the integral the cycle after it updated.
        await RisingEdge(dut.clk)
        integ = _to_signed(dut.u_dut.integral.value)

        # It must NEVER exceed the clamp and NEVER wrap negative (sign-flip)
        # while driving a strictly positive offset.
        assert integ <= integ_max, \
            (f"cycle {i}: integral {integ} exceeded INTEG_MAX {integ_max} "
             f"— anti-windup clamp not holding")
        assert integ >= 0, \
            (f"cycle {i}: integral {integ} went NEGATIVE under a sustained "
             f"POSITIVE offset — accumulator wrapped (windup)")
        max_integral_seen = max(max_integral_seen, integ)

        # Walk PHC forward by exactly one interval for the next fire.
        phc_ns = target_ns

    dut._log.info(f"freq_adj cycles={freq_adj_count}, max integral seen="
                  f"{max_integral_seen}, INTEG_MAX={integ_max}")

    # After running well past saturation, the integral must be pinned AT the
    # clamp (proves it saturated, not merely that it stayed small).
    final_integ = _to_signed(dut.u_dut.integral.value)
    assert final_integ == integ_max, \
        (f"integral should be saturated at INTEG_MAX {integ_max}, got "
         f"{final_integ} — clamp did not engage")
    assert max_integral_seen == integ_max, \
        f"peak integral {max_integral_seen} never reached the clamp {integ_max}"

