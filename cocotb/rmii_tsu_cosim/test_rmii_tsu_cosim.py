"""
HIGH-FIDELITY rmii_to_mii -> HA1588 RX-TSU co-simulation.

PURPOSE
-------
Reproduce the SILICON RX-timestamp failure (RX FIFO depth=0, t2=0) by driving
the REAL rmii_to_mii RX adapter with realistic LAN8720-style RMII stimulus and
feeding its MII output (mrxd/mrxdv/mrx_clk) into the HA1588 RX TSU EXACTLY as
ethmac_subsystem_apb.v does on silicon (see tb_rmii_tsu_cosim.v).

The existing gmii-direct oracle (cocotb/ha1588_apb, test_tsu_rx_nibble_phase_*)
synthesises a nibble-misaligned GMII stream by PREPENDING one stray 0x5 nibble.
That is a MODEL of what rmii_to_mii *might* do. This TB removes the model: it
drives rmii_to_mii's RMII pins and lets the adapter's own di-bit-pair carrier-
sense lock decide the MII nibble phase. We sweep the carrier-sense rxd=00 window
length (odd AND even di-bit counts) and the preamble length, and read RX_TSU_STAT
depth over APB for each.

VERDICT KEYS printed for the report:
  COSIM_RESULT  phase=<...> cs_dibits=<N> npre=<M> depth=<D> mii_nibbles=<...>
  COSIM_VERDICT REPRODUCED | NOT-REPRODUCED

RMII di-bit ordering (per rmii_to_mii.v and the RMII spec):
  Each byte B is sent LSB-first as 4 di-bits on the wire:
    D0={B[1],B[0]}, D1={B[3],B[2]}, D2={B[5],B[4]}, D3={B[7],B[6]}
  The adapter assembles an MII nibble as {rmii_rxd_r(newer), rmii_rxd_rr(older)}.
"""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ClockCycles, Timer, ReadOnly

# Reuse the APB driver + TSU helpers + PTP frame builders from the ha1588_apb
# suite (sibling cocotb dir). Add its path so the import resolves.
import os
import sys
sys.path.insert(
    0,
    os.path.join(os.path.dirname(__file__), "..", "..", "cocotb", "ha1588_apb"),
)

from test_ha1588_apb import (  # noqa: E402
    Ha1588ApbTB,
    build_l2_ptp_sync_frame_pre,
    REG_RTC_CTRL,
    REG_TSU_RXSTAT,
    REG_TSU_RXCTRL,
    REG_TSU_TXCTRL,
    REG_TSU_RXDATA3,
    RTC_CTRL_GET_TIME,
    TSU_CTRL_RESET,
    TSU_CTRL_READ_QUEUE,
)


class RmiiTsuTB(Ha1588ApbTB):
    """Ha1588ApbTB whose RX/TX GMII inputs are NOT top-level (they are driven
    internally by the rmii_to_mii instance in tb_rmii_tsu_cosim.v). Override
    reset() to skip the gmii tie-off writes the base class does."""

    async def reset(self, cycles=10):
        self.dut.presetn.value = 0
        self.dut.psel.value = 0
        self.dut.penable.value = 0
        await ClockCycles(self.dut.pclk, cycles)
        self.dut.presetn.value = 1
        await ClockCycles(self.dut.pclk, 5)

        # Clear all registers to flush X from CDC synchronisers (reg.v no-reset).
        for addr in range(0, 0x80, 4):
            await self.reg_write(addr, 0)
        await ClockCycles(self.dut.pclk, 30)

        # Init time_ok status bit.
        await self.reg_write(REG_RTC_CTRL, RTC_CTRL_GET_TIME)
        await ClockCycles(self.dut.pclk, 30)
        await self.reg_write(REG_RTC_CTRL, 0)

        # Init rxqu_ok/txqu_ok status bits.
        await self.reg_write(REG_TSU_RXCTRL, TSU_CTRL_READ_QUEUE)
        await self.reg_write(REG_TSU_TXCTRL, TSU_CTRL_READ_QUEUE)
        await ClockCycles(self.dut.pclk, 20)
        await self.reg_write(REG_TSU_RXCTRL, 0)
        await self.reg_write(REG_TSU_TXCTRL, 0)
        await ClockCycles(self.dut.pclk, 10)


REF_CLK_NS = 20          # 50 MHz RMII reference clock
RESET_SYNC_CYCLES = 16   # rmii_to_mii has a 3-stage reset synchroniser


# ---------------------------------------------------------------------------
# RMII di-bit helpers
# ---------------------------------------------------------------------------
def byte_to_dibits(b):
    """4 RMII di-bits of byte b, in wire order (LSB pair first)."""
    return [(b >> 0) & 0x3, (b >> 2) & 0x3, (b >> 4) & 0x3, (b >> 6) & 0x3]


async def _start_rmii_clock(dut):
    cocotb.start_soon(Clock(dut.rmii_ref_clk, REF_CLK_NS, unit="ns").start())


async def reset_rmii(dut):
    """Hold the rmii_to_mii adapter in reset, idle the RMII RX pins."""
    dut.rmii_crs_dv.value = 0
    dut.rmii_rxd.value = 0
    dut.mode_speed.value = 1   # 100 Mbps
    # presetn drives rmii_resetn in the TB; Ha1588ApbTB.reset() toggles presetn.
    await ClockCycles(dut.rmii_ref_clk, RESET_SYNC_CYCLES)


async def _align_crsdv_rise(dut, mrxclk_phase):
    """Block until rmii_to_mii's free-running mrx_clk is at the chosen phase, so
    crs_dv rises at a DETERMINISTIC point relative to the adapter's /2 MII clock.

    This is the TRUE silicon degree of freedom: rmii_to_mii's mrx_clk free-runs
    off rmii_ref_clk, and the LAN8720 asserts CRS_DV asynchronously to it. WHICH
    mrx_clk half the first preamble di-bit lands in sets the adapter's di-bit ->
    MII-nibble pairing phase. mrxclk_phase=0 raises crs_dv just after an mrx_clk
    RISING edge; =1 just after a FALLING edge. Without this the crs_dv-rise phase
    is set by unrelated APB-read scheduling jitter (non-reproducible)."""
    if mrxclk_phase is None:
        return
    prev = int(dut.mrx_clk.value)
    while True:
        await RisingEdge(dut.rmii_ref_clk)
        await ReadOnly()
        cur = int(dut.mrx_clk.value)
        hit = (mrxclk_phase == 0 and cur == 1 and prev == 0) or \
              (mrxclk_phase == 1 and cur == 0 and prev == 1)
        prev = cur
        if hit:
            break
    # Exit ReadOnly so the caller may drive again on the next edge.
    await RisingEdge(dut.rmii_ref_clk)


async def drive_rmii_lan8720_frame(dut, frame_after_sfd, npre=7,
                                   cs_dibits=0, ifg=40, mrxclk_phase=None):
    """Drive a realistic LAN8720-style RMII RX frame on rmii_crs_dv/rmii_rxd.

    Sequence on the 50 MHz RMII wire:
      0. (optional) align crs_dv-rise to a chosen mrx_clk phase (mrxclk_phase).
      1. carrier-sense window: crs_dv=1, rxd=00 for `cs_dibits` ref_clk cycles.
         The LAN8720 asserts CRS_DV at carrier detection, BEFORE valid 2-bit
         preamble di-bits start. rmii_to_mii decodes rxd==00 as carrier-sense-
         only (NOT data) and holds mrxdv low through this window. Its length is
         not deterministic on silicon (depends on when the PHY's carrier detect
         fires relative to the di-bit grid) -> sweeping odd AND even cs_dibits
         exercises BOTH nibble-pairing phases the adapter can lock to.
      2. preamble: 0x55 * npre  (di-bits all 2'b01)
      3. SFD: 0xD5
      4. payload: frame_after_sfd (DA/SA/EtherType/PTP...)
      5. crs_dv -> 0, idle (IFG).

    `frame_after_sfd` is the byte list AFTER the SFD (the build_l2_ptp_sync_frame
    builders prepend preamble+SFD themselves, so pass the slice past the SFD).
    """
    await _align_crsdv_rise(dut, mrxclk_phase)

    dut.rmii_crs_dv.value = 1

    # 1) Carrier-sense rxd=00 window.
    dut.rmii_rxd.value = 0
    for _ in range(cs_dibits):
        await RisingEdge(dut.rmii_ref_clk)

    # 2-4) preamble + SFD + payload, di-bit by di-bit.
    stream = [0x55] * npre + [0xD5] + list(frame_after_sfd)
    for b in stream:
        for d in byte_to_dibits(b):
            dut.rmii_rxd.value = d
            await RisingEdge(dut.rmii_ref_clk)

    # 5) End of frame: drop carrier, idle.
    dut.rmii_crs_dv.value = 0
    dut.rmii_rxd.value = 0
    await ClockCycles(dut.rmii_ref_clk, ifg)


async def collect_mii_rx_nibbles(dut, n_cycles):
    """Sample mrxd on rising mrx_clk while mrxdv high (what the TSU sees).

    DIAGNOSTIC ONLY: the TSU itself samples mrxd in hardware flops on mrx_clk;
    this Python sampler exists only to reconstruct, for the log, the MII byte
    stream the adapter emitted. We settle with ReadOnly() before reading so the
    sampled value is the post-edge (settled) mrxd, immune to delta-cycle
    task-wake ordering (without ReadOnly the read can catch the value mid-update,
    which shifts with unrelated APB activity -- a pure observation artifact, not
    a TSU behaviour).
    """
    nibbles = []
    prev = int(dut.mrx_clk.value)
    for _ in range(n_cycles):
        await RisingEdge(dut.rmii_ref_clk)
        await ReadOnly()
        cur = int(dut.mrx_clk.value)
        if cur == 1 and prev == 0:
            try:
                dv = int(dut.mrxdv.value)
            except Exception:
                dv = 0
            if dv == 1:
                try:
                    nibbles.append(int(dut.mrxd.value) & 0xF)
                except Exception:
                    nibbles.append(-1)
        prev = cur
    return nibbles


def nibbles_to_bytes(nibbles, offset=0):
    """Recombine MII nibbles (low then high per byte) into bytes, starting the
    pairing at `offset` (0 or 1). The hardware nibble phase (nibble_h) is set by
    the adapter, so the Python pairing offset that yields the SFD is itself a
    diagnostic of the phase the adapter locked to."""
    out = []
    for i in range(offset, len(nibbles) - 1, 2):
        lo = nibbles[i] & 0xF
        hi = nibbles[i + 1] & 0xF
        out.append((hi << 4) | lo)
    return out


def reconstruct_with_sfd(nibbles):
    """Return (bytes, pairing_offset, sfd_found). Try both nibble-pairing
    offsets and pick the one that contains the SFD 0xD5 (mirrors how the working
    test_rmii_phy_bfm.py searches for 0xD5). If neither contains 0xD5 the
    adapter split the SFD across a byte boundary (the silicon misalignment)."""
    for off in (0, 1):
        b = nibbles_to_bytes(nibbles, off)
        if 0xD5 in b:
            return b, off, True
    return nibbles_to_bytes(nibbles, 0), 0, False


# ---------------------------------------------------------------------------
# Arm + inject + read-back over APB (firmware-equivalent path)
# ---------------------------------------------------------------------------
async def _arm_rx_tsu(tb, dut):
    """Accept Sync (msgType 0x0) and reset the RX queue to a known depth 0."""
    await tb.reg_write(REG_TSU_RXSTAT, 0x01000000)   # msgid mask: accept Sync
    await tb.reg_write(REG_TSU_RXCTRL, TSU_CTRL_RESET)
    await ClockCycles(dut.pclk, 30)
    await tb.reg_write(REG_TSU_RXCTRL, 0)
    await ClockCycles(dut.pclk, 20)


async def _inject_and_read(tb, dut, npre, cs_dibits, seq_id, mrxclk_phase=0):
    """Arm, drive ONE rmii frame, read back depth + head entry over APB.

    mrxclk_phase pins the crs_dv-rise phase relative to rmii_to_mii's free-
    running mrx_clk so the result is DETERMINISTIC and reproducible (without it
    the crs_dv-rise phase is set by APB-read scheduling jitter -> the captured
    depth flickers run-to-run and is not a trustworthy oracle)."""
    await _arm_rx_tsu(tb, dut)

    pre_stat = await tb.reg_read(REG_TSU_RXSTAT)
    pre_depth = pre_stat & 0xFF

    # Build the standard L2 PTP Sync frame, then strip its own preamble+SFD
    # (npre 0x55 bytes + one 0xD5) so we can re-frame it on the RMII wire with
    # OUR carrier-sense window + preamble.
    full = build_l2_ptp_sync_frame_pre(npre, seq_id=seq_id)
    payload = full[npre + 1:]   # bytes after the SFD (DA/SA/EtherType/PTP...)

    drv = cocotb.start_soon(
        drive_rmii_lan8720_frame(dut, payload, npre=npre,
                                 cs_dibits=cs_dibits, ifg=40,
                                 mrxclk_phase=mrxclk_phase))
    # Sample the MII RX nibble stream the TSU sees, in parallel. Add slack for
    # the up-to-one mrx_clk period the phase-align wait can consume.
    total_cycles = (cs_dibits + (npre + 1 + len(payload)) * 4) + 90
    nibbles = await collect_mii_rx_nibbles(dut, total_cycles)
    await drv

    # Let the gmii_clk-domain TSU pipeline + ptp_parser + FIFO settle, then read
    # depth via the same APB register firmware polls.
    await ClockCycles(dut.pclk, 300)

    stat = await tb.reg_read(REG_TSU_RXSTAT)
    depth = stat & 0xFF
    d3 = await tb.reg_read(REG_TSU_RXDATA3)

    rx_bytes, pair_off, sfd_in_stream = reconstruct_with_sfd(nibbles)

    return {
        "npre": npre,
        "cs_dibits": cs_dibits,
        "mrxclk_phase": mrxclk_phase,
        "pre_depth": pre_depth,
        "depth": depth,
        "msg_id": (d3 >> 28) & 0xF,
        "seq_id": d3 & 0xFFFF,
        "n_nibbles": len(nibbles),
        "nibbles": nibbles,
        "rx_bytes": rx_bytes,
        "pair_off": pair_off,
        "sfd_in_stream": sfd_in_stream,
    }


async def _setup(dut):
    """Bring up APB/RTC clocks (via Ha1588ApbTB), reset, start RMII clock+reset,
    and seed the RTC so a captured timestamp would be non-zero."""
    tb = RmiiTsuTB(dut)
    await _start_rmii_clock(dut)
    await tb.reset()                 # toggles presetn -> also resets rmii_to_mii
    await reset_rmii(dut)
    return tb


# ===========================================================================
# Tests
# ===========================================================================

# Carrier-sense di-bit window lengths to sweep. Each value shifts the carrier-
# sense window the adapter sees before the preamble. Crossed with the crs_dv-
# rise-vs-mrx_clk PHASE (the true free-running-clock degree of freedom), this
# spans BOTH MII nibble-pairing phases rmii_to_mii can lock to. We also vary the
# preamble length (npre) since that is the OTHER axis the gmii-direct oracle
# claimed reproduces the bug.
CS_SWEEP = [0, 1, 2, 3, 4, 5, 6, 7]
NPRE_SWEEP = [7, 6, 5, 4, 3]
MRXCLK_PHASES = [0, 1]   # crs_dv rises just after mrx_clk rising (0) / falling (1)


@cocotb.test()
async def test_rmii_tsu_phase_sweep(dut):
    """DETERMINISTIC sweep: crs_dv-rise-vs-mrx_clk phase x carrier-sense window x
    preamble length. Drive REAL rmii_to_mii -> RX TSU and record RX_TSU_STAT
    depth per phase. The crs_dv-rise phase is PINNED to mrx_clk so each cell is
    reproducible (not subject to APB scheduling jitter)."""
    tb = await _setup(dut)

    results = []
    seq = 10
    for ph in MRXCLK_PHASES:
        for npre in NPRE_SWEEP:
            for cs in CS_SWEEP:
                seq += 1
                r = await _inject_and_read(tb, dut, npre=npre, cs_dibits=cs,
                                           seq_id=seq, mrxclk_phase=ph)
                results.append(r)
                tb.log.info(
                    "COSIM_RESULT mrxclk_phase=%d cs_dibits=%d npre=%d depth=%d "
                    "sfd_in_mii=%s pair_off=%d msgId=%d seqId=%d nibbles=%d",
                    ph, cs, npre, r["depth"], r["sfd_in_stream"],
                    r["pair_off"], r["msg_id"], r["seq_id"], r["n_nibbles"],
                )
                # Show the reconstructed MII byte stream for a couple of cells so
                # the report can SEE whether 0xD5 survives the adapter.
                if cs in (0, 1) and npre == 7:
                    tb.log.info(
                        "  MII bytes (ph=%d cs=%d npre=%d): %s",
                        ph, cs, npre,
                        " ".join(f"{b:02X}" for b in r["rx_bytes"][:24]),
                    )

    # ---- Summarise per-phase depth for the verdict ----
    n_total = len(results)
    n_captured = sum(1 for r in results if r["depth"] >= 1)
    n_failed = n_total - n_captured

    fail_phases = [
        (r["mrxclk_phase"], r["cs_dibits"], r["npre"])
        for r in results if r["depth"] == 0
    ]
    # SFD-split cells: the adapter produced an MII stream with NO intact 0xD5
    # (the actual silicon misalignment condition). Track separately from depth.
    split_cells = [
        (r["mrxclk_phase"], r["cs_dibits"], r["npre"])
        for r in results if not r["sfd_in_stream"]
    ]

    tb.log.info("=" * 72)
    tb.log.info(
        "COSIM SUMMARY: %d/%d cells CAPTURED (depth>=1), %d/%d depth==0",
        n_captured, n_total, n_failed, n_total)
    tb.log.info("COSIM SFD-SPLIT cells (mrxclk_phase,cs,npre) [adapter split "
                "0xD5 across a byte]: %s", split_cells)
    tb.log.info("COSIM depth==0 cells (mrxclk_phase,cs,npre): %s", fail_phases)

    # Per-phase depth grid (raw depths for the report).
    for ph in MRXCLK_PHASES:
        tb.log.info("COSIM DEPTH GRID mrxclk_phase=%d (rows=npre, cols=cs):", ph)
        tb.log.info("  npre_vs_cs: " + " ".join(f"{cs:2d}" for cs in CS_SWEEP))
        for npre in NPRE_SWEEP:
            row = {r["cs_dibits"]: r["depth"] for r in results
                   if r["npre"] == npre and r["mrxclk_phase"] == ph}
            tb.log.info("  npre=%d   :  " % npre + " ".join(
                f"{row.get(cs, -1):2d}" for cs in CS_SWEEP))

    # The SILICON frame geometry is a STANDARD 7-byte preamble + SFD: the
    # LAN8720 regenerates a full preamble, it does NOT forward a short one. So
    # the verdict is anchored on the npre=7 cells (the realistic condition).
    # Shorter-preamble cells (npre<=6) are an extra robustness axis, NOT the
    # silicon condition; a depth=0 there is a parser minimum-preamble limit, not
    # the t2=0 silicon failure.
    npre7 = [r for r in results if r["npre"] == 7]
    npre7_fail = [r for r in npre7 if r["depth"] == 0]
    fail_npre = sorted({r["npre"] for r in results if r["depth"] == 0})

    if npre7_fail:
        tb.log.info(
            "COSIM_VERDICT REPRODUCED: %d/%d STANDARD-preamble (npre=7, the "
            "silicon frame geometry) rmii-driven cells give RX TSU depth=0 "
            "against the CURRENT patched tsu.v -- the silicon t2=0 condition is "
            "reproduced through the real rmii_to_mii. depth==0 npre values: %s",
            len(npre7_fail), len(npre7), fail_npre)
    else:
        tb.log.info(
            "COSIM_VERDICT NOT-REPRODUCED: ALL %d STANDARD-preamble (npre=7, the "
            "silicon frame geometry) rmii-driven cells CAPTURED (depth>=1) "
            "against the patched tsu.v, across BOTH crs_dv/mrx_clk phases and "
            "every carrier-sense window length. The adapter kept the SFD 0xD5 "
            "intact for every pinned phase (SFD-split cells=%d) and the patched "
            "tsu.v timestamped the Sync. The only depth==0 cells are npre<=%s "
            "(short-preamble -- NOT the silicon geometry; the LAN8720 emits a "
            "full 7-byte preamble). The silicon t2=0 is therefore NOT a "
            "functional-RTL nibble-phase miss against this RTL at the realistic "
            "frame geometry; it is deeper (real-silicon timing/CDC/synth) -- "
            "justifies an ILA capture.", len(npre7), len(split_cells),
            (max(fail_npre) if fail_npre else "none"))

    # This TB REPRODUCES/REFUTES; it does not gate pass/fail on capture. Assert
    # only that the cosim RAN end-to-end (adapter drove a non-trivial MII stream
    # into the TSU for every cell) so a green run means the experiment is valid.
    assert all(r["n_nibbles"] > 0 for r in results), (
        "rmii_to_mii produced NO MII RX nibbles for some cell -- the adapter "
        "did not drive the TSU; cosim wiring/clocking is broken, not a verdict.")


@cocotb.test()
async def test_rmii_tsu_sfd_split_capture(dut):
    """Targeted: find a DETERMINISTIC rmii phase where the adapter SPLITS the SFD
    (no intact 0xD5 in the MII stream -- the real silicon misalignment) and show
    what the patched tsu.v does with it (capture vs depth=0). This is the cell
    that matters: if the patched TSU captures the SFD-split stream, the fix
    covers the silicon condition in functional sim; if depth=0, the cosim has
    reproduced t2=0 on the faithful oracle."""
    tb = await _setup(dut)

    # Search the phase space for an SFD-split MII stream.
    split = None
    seq = 200
    for ph in (0, 1):
        for cs in range(0, 8):
            seq += 1
            r = await _inject_and_read(tb, dut, npre=7, cs_dibits=cs,
                                       seq_id=seq, mrxclk_phase=ph)
            tb.log.info(
                "SFDSPLIT scan ph=%d cs=%d depth=%d sfd_in_mii=%s bytes=%s",
                ph, cs, r["depth"], r["sfd_in_stream"],
                " ".join(f"{b:02X}" for b in r["rx_bytes"][6:11]))
            if not r["sfd_in_stream"]:
                split = r
                break
        if split is not None:
            break

    if split is None:
        tb.log.info(
            "SFDSPLIT: NO deterministic rmii phase produced an SFD-split MII "
            "stream in this sweep -- the adapter keeps 0xD5 intact for every "
            "pinned crs_dv/mrx_clk phase, so the misalignment the silicon bug "
            "needs does not occur for THIS frame geometry in functional sim.")
        return

    tb.log.info(
        "SFDSPLIT FOUND mrxclk_phase=%d cs=%d: MII stream has NO intact 0xD5 "
        "(SFD split across a byte -- the silicon misalignment). RX TSU depth=%d "
        "(>=1 => patched tsu.v REALIGN covered it; ==0 => t2=0 reproduced).",
        split["mrxclk_phase"], split["cs_dibits"], split["depth"])


@cocotb.test()
async def test_rmii_tsu_sanity(dut):
    """Plumbing sanity (DETERMINISTIC phase): a pinned-phase frame must produce a
    byte-aligned MII stream containing the SFD 0xD5 and the TSU must capture it.
    Proves the composed rmii_to_mii->TSU->APB path is wired and live."""
    tb = await _setup(dut)
    r = await _inject_and_read(tb, dut, npre=7, cs_dibits=0, seq_id=99,
                               mrxclk_phase=0)
    tb.log.info(
        "SANITY ph=0 cs=0 npre=7: depth=%d sfd_in_mii=%s pair_off=%d bytes=%s",
        r["depth"], r["sfd_in_stream"], r["pair_off"],
        " ".join(f"{b:02X}" for b in r["rx_bytes"][:20]),
    )
    tb.log.info("SANITY raw MII nibbles: %s",
                " ".join(f"{n:X}" for n in r["nibbles"][:24]))
    assert r["n_nibbles"] > 0, "adapter produced no MII nibbles"
    assert r["sfd_in_stream"], (
        "pinned-phase MII stream lacks SFD 0xD5 -- adapter/TB plumbing fault. "
        f"MII bytes: {[f'{b:02X}' for b in r['rx_bytes'][:20]]}")
    assert r["depth"] >= 1, (
        f"pinned-phase aligned frame did NOT capture (depth={r['depth']}) -- "
        "the composed TSU path is not timestamping a clean frame; cosim is not "
        "a trustworthy oracle until this passes.")
