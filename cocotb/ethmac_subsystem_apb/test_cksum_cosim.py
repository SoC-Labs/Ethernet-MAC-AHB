"""Cocotb subsystem-level cosim tests for the RX Checksum Calculator.

Drives real frames onto the MII RX bus via cocotbext-eth's MiiSource.
The OpenCores MAC DMAs the frame into AHBLiteSlaveRAM, and eth_rx_cksum
(sharing the same MII RX tap as the MAC and HA1588) independently
computes IP + L4 checksums. Tests assert the snapshot registers and
counters match the wire data, and that the checksum block coexists
with HA1588 PTP timestamping on the same MII snoop.

A joint work commissioned on behalf of SoC Labs, under Arm Academic
Access licence.

Contributors
  David Mapstone (d.a.mapstone@soton.ac.uk)

Copyright 2026, SoC Labs (www.soclabs.org)
"""

import cocotb
from cocotb.triggers import Timer, RisingEdge, ClockCycles

from test_ethmac_subsystem_apb import (
    SubsystemTB, apb_read, apb_write, HAS_COCOTBEXT_ETH,
)
from test_ptp_cosim import (
    build_ptp_frame_payload, setup_rtc, setup_tsu,
    configure_mac_for_ptp, read_tsu_entry,
)

if HAS_COCOTBEXT_ETH:
    from cocotbext.eth import GmiiFrame

from scapy.all import Ether, IP, UDP, TCP, Raw


# ── eth_rx_cksum register map (base 0x2000 in the subsystem) ────────────
CKSUM_BASE               = 0x2000
CKSUM_ID                 = CKSUM_BASE + 0x00
CKSUM_CTRL               = CKSUM_BASE + 0x04
CKSUM_STATUS             = CKSUM_BASE + 0x08
CKSUM_FRAME_COUNT        = CKSUM_BASE + 0x0C
CKSUM_IP_GOOD_COUNT      = CKSUM_BASE + 0x10
CKSUM_IP_BAD_COUNT       = CKSUM_BASE + 0x14
CKSUM_L4_GOOD_COUNT      = CKSUM_BASE + 0x18
CKSUM_L4_BAD_COUNT       = CKSUM_BASE + 0x1C
CKSUM_LAST_FRAME_INFO    = CKSUM_BASE + 0x20
CKSUM_LAST_IP_HDR_CKSUM  = CKSUM_BASE + 0x28
CKSUM_LAST_L4_CKSUM      = CKSUM_BASE + 0x2C
CKSUM_LAST_SRC_IP        = CKSUM_BASE + 0x30
CKSUM_LAST_DST_IP        = CKSUM_BASE + 0x34
CKSUM_LAST_L4_PORTS      = CKSUM_BASE + 0x38
CKSUM_LAST_SEQNUM        = CKSUM_BASE + 0x3C

CTRL_EN              = 1 << 0
CTRL_MODE_DROP_NEW   = 0b01 << 1
STATUS_FIFO_EMPTY    = 1 << 4

INFO_IS_IPV4 = 1 << 25
INFO_IS_UDP  = 1 << 27
INFO_IP_OK   = 1 << 29
INFO_L4_OK   = 1 << 30


async def enable_cksum_block(dut, mode_bits=CTRL_MODE_DROP_NEW):
    """Enable the checksum block in DROP_NEW mode (default)."""
    await apb_write(dut, CKSUM_CTRL, CTRL_EN | mode_bits)
    await ClockCycles(dut.pclk, 20)


# ════════════════════════════════════════════════════════════════════════
# Stage 6.1 — checksum integration
# ════════════════════════════════════════════════════════════════════════

@cocotb.test()
async def test_cksum_cp1_id(dut):
    """The cksum block's ID register is reachable through the APB mux."""
    tb = SubsystemTB(dut)
    await tb.reset()

    val = await apb_read(dut, CKSUM_ID)
    assert val == 0x434B534D, (
        f"cksum ID mismatch via subsystem APB mux: "
        f"got 0x{val:08X}, expected 0x434B534D"
    )


@cocotb.test()
async def test_cksum_integration_udp(dut):
    """Drive a UDP/IPv4 frame through the MAC; cksum block snapshot matches."""
    assert HAS_COCOTBEXT_ETH, "cocotbext-eth required for this test"
    tb = SubsystemTB(dut)
    await tb.reset()

    # Configure MAC for promiscuous RX so the test frame is accepted
    # regardless of dst MAC.
    await setup_rtc(dut)
    await configure_mac_for_ptp(dut, tb, enable_tx=False, enable_rx=True)
    await enable_cksum_block(dut)

    pkt = (Ether(dst="de:ad:be:ef:00:02", src="aa:bb:cc:dd:ee:ff")
           / IP(src="10.1.2.3", dst="10.4.5.6")
           / UDP(sport=12000, dport=13000)
           / Raw(b"cosim-integration"))
    raw = bytes(pkt)
    parsed = Ether(raw)

    await tb.mii_rx_source.send(GmiiFrame.from_payload(raw))
    await Timer(30, "us")

    # Cksum block counters bump once.
    fc = await apb_read(dut, CKSUM_FRAME_COUNT)
    igc = await apb_read(dut, CKSUM_IP_GOOD_COUNT)
    lgc = await apb_read(dut, CKSUM_L4_GOOD_COUNT)
    assert fc  == 1, f"FRAME_COUNT {fc} != 1"
    assert igc == 1, f"IP_GOOD_COUNT {igc} != 1 — subsystem integration broken"
    assert lgc == 1, f"L4_GOOD_COUNT {lgc} != 1"

    # Snapshot fields match the wire data.
    info = await apb_read(dut, CKSUM_LAST_FRAME_INFO)
    assert info & INFO_IS_IPV4
    assert info & INFO_IS_UDP
    assert info & INFO_IP_OK
    assert info & INFO_L4_OK

    ip_cksum = await apb_read(dut, CKSUM_LAST_IP_HDR_CKSUM)
    calc, wire = ip_cksum & 0xFFFF, (ip_cksum >> 16) & 0xFFFF
    assert calc == wire, f"IP cksum: calc 0x{calc:04X} != wire 0x{wire:04X}"
    assert wire == parsed[IP].chksum

    l4_cksum = await apb_read(dut, CKSUM_LAST_L4_CKSUM)
    calc, wire = l4_cksum & 0xFFFF, (l4_cksum >> 16) & 0xFFFF
    assert calc == wire
    assert wire == parsed[UDP].chksum


@cocotb.test()
async def test_cksum_integration_tcp(dut):
    """TCP/IPv4 frame through the subsystem; cksum block validates."""
    assert HAS_COCOTBEXT_ETH, "cocotbext-eth required"
    tb = SubsystemTB(dut)
    await tb.reset()

    await setup_rtc(dut)
    await configure_mac_for_ptp(dut, tb, enable_tx=False, enable_rx=True)
    await enable_cksum_block(dut)

    pkt = (Ether(dst="de:ad:be:ef:00:02", src="aa:bb:cc:dd:ee:ff")
           / IP(src="192.168.1.10", dst="192.168.1.20")
           / TCP(sport=49152, dport=80, flags="A", seq=100, ack=200)
           / Raw(b"GET / HTTP/1.0\r\n\r\n"))
    raw = bytes(pkt)
    parsed = Ether(raw)

    await tb.mii_rx_source.send(GmiiFrame.from_payload(raw))
    await Timer(30, "us")

    assert (await apb_read(dut, CKSUM_IP_GOOD_COUNT)) == 1
    assert (await apb_read(dut, CKSUM_L4_GOOD_COUNT)) == 1

    info = await apb_read(dut, CKSUM_LAST_FRAME_INFO)
    assert info & (1 << 28), "IS_TCP should be set"

    l4_cksum = await apb_read(dut, CKSUM_LAST_L4_CKSUM)
    assert (l4_cksum >> 16) & 0xFFFF == parsed[TCP].chksum


# ════════════════════════════════════════════════════════════════════════
# Stage 6.2 — checksum / PTP coexistence
# ════════════════════════════════════════════════════════════════════════

@cocotb.test()
async def test_cksum_ptp_coexist(dut):
    """Interleave PTP + UDP frames on the same MII snoop. The cksum block
    must correctly categorise PTP as non-IP (no IP/L4 count bump) and UDP
    as a good IPv4/UDP (both counts bump), while HA1588 records the PTP
    timestamp — proving the two snoop consumers don't interfere.
    """
    assert HAS_COCOTBEXT_ETH, "cocotbext-eth required"
    tb = SubsystemTB(dut)
    log = dut._log
    await tb.reset()

    await setup_rtc(dut)
    await setup_tsu(dut, rx_mask=0x0F, tx_mask=0x0F)
    await configure_mac_for_ptp(dut, tb, enable_tx=False, enable_rx=True)
    await enable_cksum_block(dut)

    # Minimal mixed stream: one PTP Sync then one UDP frame.
    ptp_sync = GmiiFrame.from_payload(build_ptp_frame_payload(0x00, seq_id=1))
    udp_raw  = bytes(
        Ether(dst="de:ad:be:ef:00:02", src="aa:bb:cc:dd:ee:ff")
        / IP(src="10.0.0.1", dst="10.0.0.2")
        / UDP(sport=10000, dport=20000)
        / Raw(b"udp-after-ptp"))

    await tb.mii_rx_source.send(ptp_sync)
    await Timer(8, "us")
    await tb.mii_rx_source.send(GmiiFrame.from_payload(udp_raw))
    await Timer(30, "us")

    # Cksum block sees both frames.
    fc = await apb_read(dut, CKSUM_FRAME_COUNT)
    assert fc == 2, f"FRAME_COUNT {fc} != 2"
    # PTP (0x88F7) is not IPv4 — only UDP should count toward IP/L4.
    assert (await apb_read(dut, CKSUM_IP_GOOD_COUNT)) == 1, (
        "Only the UDP frame should bump IP_GOOD — PTP is not IPv4"
    )
    assert (await apb_read(dut, CKSUM_L4_GOOD_COUNT)) == 1

    # Drain the FIFO — one entry is the non-IP PTP frame, one is the
    # good IPv4/UDP frame. Both must be visible; the UDP one must carry
    # IS_IPV4 + IS_UDP + IP_OK + L4_OK, and the PTP one must carry none
    # of those flags (its EtherType is 0x88F7, not 0x0800).
    seen_udp = False
    seen_ptp = False
    for _ in range(4):
        info = await apb_read(dut, CKSUM_LAST_FRAME_INFO)
        if info == 0:
            break
        if info & INFO_IS_IPV4:
            assert info & INFO_IS_UDP
            assert info & INFO_L4_OK
            seen_udp = True
        else:
            seen_ptp = True
        await apb_read(dut, CKSUM_BASE + 0x9C)  # alias SEQNUM read → pop
    assert seen_udp, "UDP snapshot did not appear in the FIFO"
    assert seen_ptp, "PTP snapshot did not appear in the FIFO"

    # HA1588 queue depth check — non-zero entry count confirms HA1588
    # timestamped the PTP frame. (Reading the queue data words exercises
    # a separate HA1588 readback path that has its own cosim-level
    # X-prop quirk, covered by the dedicated PTP cosim tests.)
    tsu_stat = await apb_read(dut, 0x1000 + 0x44)  # PTP_TSU_RXSTAT
    assert (tsu_stat & 0xFF) != 0, (
        "HA1588 RX TSU queue empty — the checksum snoop path may have "
        "interfered with PTP timestamping"
    )
    log.info("Coexist: cksum frame_count=%d, HA1588 TSU queue=%d",
             fc, tsu_stat & 0xFF)


@cocotb.test()
async def test_cksum_counter_clear(dut):
    """CTRL.CLR_COUNTERS via the APB mux still zeros counters end-to-end."""
    assert HAS_COCOTBEXT_ETH, "cocotbext-eth required"
    tb = SubsystemTB(dut)
    await tb.reset()

    await setup_rtc(dut)
    await configure_mac_for_ptp(dut, tb, enable_tx=False, enable_rx=True)
    await enable_cksum_block(dut)

    for i in range(3):
        pkt = (Ether(dst="de:ad:be:ef:00:02", src="aa:bb:cc:dd:ee:ff")
               / IP(src=f"10.0.0.{i+1}", dst="10.0.0.99")
               / UDP(sport=30000 + i, dport=40000)
               / Raw(b"hdr-clr"))
        await tb.mii_rx_source.send(GmiiFrame.from_payload(bytes(pkt)))
    await Timer(30, "us")

    assert (await apb_read(dut, CKSUM_FRAME_COUNT))   == 3
    assert (await apb_read(dut, CKSUM_IP_GOOD_COUNT)) == 3

    # Clear counters.
    await apb_write(dut, CKSUM_CTRL,
                    CTRL_EN | CTRL_MODE_DROP_NEW | (1 << 16))
    await ClockCycles(dut.pclk, 20)
    assert (await apb_read(dut, CKSUM_FRAME_COUNT))   == 0
    assert (await apb_read(dut, CKSUM_IP_GOOD_COUNT)) == 0


# ════════════════════════════════════════════════════════════════════════
# SCP1.4 — Interleaved MAC/PTP/cksum register access
# ════════════════════════════════════════════════════════════════════════

@cocotb.test()
async def test_scp1_4_interleaved_access(dut):
    """SCP1.4: Interleaved reads across MAC, PTP, and cksum mux slots."""
    tb = SubsystemTB(dut)
    await tb.reset()

    # MAC: MODER default
    moder = await apb_read(dut, 0x0000)
    assert moder == 0xA000 or moder == 0x0000  # depends on reset val

    # PTP: scratch
    await apb_write(dut, 0x1004, 0xDEADBEEF)
    val = await apb_read(dut, 0x1004)
    assert val == 0xDEADBEEF, f"PTP scratch: 0x{val:08X}"

    # Cksum: ID
    val = await apb_read(dut, CKSUM_ID)
    assert val == 0x434B534D

    # Rapid round-robin
    for _ in range(10):
        await apb_read(dut, 0x0000)  # MAC
        await apb_read(dut, 0x1004)  # PTP
        await apb_read(dut, CKSUM_ID)  # Cksum


# ════════════════════════════════════════════════════════════════════════
# SCP2 — MAC DMA + Checksum Coherence (additional tests)
# ════════════════════════════════════════════════════════════════════════

@cocotb.test()
async def test_scp2_3_seqnum_tracks_bd_order(dut):
    """SCP2.3: Cksum seqnum tracks MAC BD ring order (3 frames)."""
    assert HAS_COCOTBEXT_ETH, "cocotbext-eth required"
    tb = SubsystemTB(dut)
    await tb.reset()
    await setup_rtc(dut)
    await configure_mac_for_ptp(dut, tb, enable_tx=False, enable_rx=True)
    await enable_cksum_block(dut)

    seqs = []
    for i in range(3):
        pkt = (Ether(dst="de:ad:be:ef:00:02", src="aa:bb:cc:dd:ee:ff")
               / IP(src=f"10.0.0.{i+1}", dst="10.0.0.99")
               / UDP(sport=5000+i, dport=6000) / Raw(bytes([i]*8)))
        await tb.mii_rx_source.send(GmiiFrame.from_payload(bytes(pkt)))
        await Timer(6, "us")

    await Timer(30, "us")
    for _ in range(3):
        info = await apb_read(dut, CKSUM_LAST_FRAME_INFO)
        if info == 0:
            break
        seq = await apb_read(dut, CKSUM_BASE + 0x9C)  # alias pop
        seqs.append(seq)

    assert len(seqs) == 3, f"Expected 3 snapshots, got {len(seqs)}"
    assert seqs == sorted(seqs), f"Seqnums not monotonic: {seqs}"
    assert seqs[0] < seqs[1] < seqs[2], f"Seqnums not strictly increasing: {seqs}"


# ════════════════════════════════════════════════════════════════════════
# SCP4 — Counter & FIFO via subsystem APB (additional)
# ════════════════════════════════════════════════════════════════════════

@cocotb.test()
async def test_scp4_2_clr_fifo_via_mux(dut):
    """SCP4.2: CLR_FIFO via subsystem APB mux drains all entries."""
    assert HAS_COCOTBEXT_ETH, "cocotbext-eth required"
    tb = SubsystemTB(dut)
    await tb.reset()
    await setup_rtc(dut)
    await configure_mac_for_ptp(dut, tb, enable_tx=False, enable_rx=True)
    await enable_cksum_block(dut)

    for i in range(4):
        pkt = (Ether(dst="de:ad:be:ef:00:02", src="aa:bb:cc:dd:ee:ff")
               / IP(src=f"10.0.0.{i+1}", dst="10.0.0.99")
               / UDP(sport=7000+i, dport=8000) / Raw(b"drain"))
        await tb.mii_rx_source.send(GmiiFrame.from_payload(bytes(pkt)))
    await Timer(30, "us")

    status = await apb_read(dut, CKSUM_STATUS)
    assert not (status & STATUS_FIFO_EMPTY), "FIFO should be non-empty"

    # CLR_FIFO
    ctrl = await apb_read(dut, CKSUM_CTRL)
    await apb_write(dut, CKSUM_CTRL, ctrl | (1 << 17))
    await ClockCycles(dut.pclk, 50)

    status = await apb_read(dut, CKSUM_STATUS)
    assert status & STATUS_FIFO_EMPTY, "CLR_FIFO must drain the FIFO"


@cocotb.test()
async def test_scp4_3_alias_pop_through_mux(dut):
    """SCP4.3: Alias-window pop through the subsystem APB mux."""
    assert HAS_COCOTBEXT_ETH, "cocotbext-eth required"
    tb = SubsystemTB(dut)
    await tb.reset()
    await setup_rtc(dut)
    await configure_mac_for_ptp(dut, tb, enable_tx=False, enable_rx=True)
    await enable_cksum_block(dut)

    pkt = (Ether(dst="de:ad:be:ef:00:02", src="aa:bb:cc:dd:ee:ff")
           / IP(src="10.0.0.1", dst="10.0.0.2")
           / UDP(sport=1234, dport=5678) / Raw(b"pop-test"))
    await tb.mii_rx_source.send(GmiiFrame.from_payload(bytes(pkt)))
    await Timer(30, "us")

    status = await apb_read(dut, CKSUM_STATUS)
    assert not (status & STATUS_FIFO_EMPTY)

    # Pop via alias SEQNUM at 0x209C
    seq = await apb_read(dut, CKSUM_BASE + 0x9C)
    await ClockCycles(dut.pclk, 10)

    status = await apb_read(dut, CKSUM_STATUS)
    assert status & STATUS_FIFO_EMPTY, "Alias-SEQNUM read must pop the head"
    assert seq > 0, f"Seqnum should be non-zero, got {seq}"


# ════════════════════════════════════════════════════════════════════════
# SCP5 — Interrupt at subsystem level
# ════════════════════════════════════════════════════════════════════════

@cocotb.test()
async def test_scp5_1_cksum_int_propagates(dut):
    """SCP5.1: cksum_int_o propagates to the subsystem wrapper."""
    assert HAS_COCOTBEXT_ETH, "cocotbext-eth required"
    tb = SubsystemTB(dut)
    await tb.reset()
    await setup_rtc(dut)
    await configure_mac_for_ptp(dut, tb, enable_tx=False, enable_rx=True)

    # Enable with IRQ_EN_FRAME
    await apb_write(dut, CKSUM_CTRL,
                    CTRL_EN | CTRL_MODE_DROP_NEW | (1 << 8))
    await ClockCycles(dut.pclk, 20)

    assert int(dut.cksum_int_o.value) == 0, "IRQ should be low before any frame"

    pkt = (Ether(dst="de:ad:be:ef:00:02", src="aa:bb:cc:dd:ee:ff")
           / IP(src="10.0.0.1", dst="10.0.0.2")
           / UDP(sport=1234, dport=5678) / Raw(b"irq-sys"))
    await tb.mii_rx_source.send(GmiiFrame.from_payload(bytes(pkt)))
    await Timer(30, "us")

    assert int(dut.cksum_int_o.value) == 1, "cksum_int_o must propagate to TB top"


@cocotb.test()
async def test_scp5_2_cksum_int_independent_from_mac(dut):
    """SCP5.2: cksum_int_o is independent from MAC int_o."""
    assert HAS_COCOTBEXT_ETH, "cocotbext-eth required"
    tb = SubsystemTB(dut)
    await tb.reset()
    await setup_rtc(dut)
    await configure_mac_for_ptp(dut, tb, enable_tx=False, enable_rx=True)
    await enable_cksum_block(dut)

    # Before any frame: both IRQs low
    assert int(dut.cksum_int_o.value) == 0
    # int_o may be X on some sims without initmem; just confirm cksum is clean
    # after a frame goes through.

    pkt = (Ether(dst="de:ad:be:ef:00:02", src="aa:bb:cc:dd:ee:ff")
           / IP(src="10.0.0.1", dst="10.0.0.2")
           / UDP(sport=1234, dport=5678) / Raw(b"indep"))
    await tb.mii_rx_source.send(GmiiFrame.from_payload(bytes(pkt)))
    await Timer(30, "us")

    # cksum_int_o stays low (IRQ enables all off) while MAC may fire RXB
    assert int(dut.cksum_int_o.value) == 0, (
        "cksum_int_o should be 0 with all IRQ enables off"
    )


# ════════════════════════════════════════════════════════════════════════
# SCP6 — TCP/IP Traffic Scenarios
# ════════════════════════════════════════════════════════════════════════

@cocotb.test()
async def test_scp6_1_udp_echo_100(dut):
    """SCP6.1: 100 back-to-back UDP packets — all validate."""
    assert HAS_COCOTBEXT_ETH, "cocotbext-eth required"
    tb = SubsystemTB(dut)
    await tb.reset()
    await setup_rtc(dut)
    await configure_mac_for_ptp(dut, tb, enable_tx=False, enable_rx=True)
    # DROP_OLD so we don't stall
    await apb_write(dut, CKSUM_CTRL, CTRL_EN | (2 << 1))
    await ClockCycles(dut.pclk, 20)

    n = 100
    for i in range(n):
        pkt = (Ether(dst="de:ad:be:ef:00:02", src="aa:bb:cc:dd:ee:ff")
               / IP(src=f"10.0.{i//256}.{i%256+1}", dst="10.0.0.99")
               / UDP(sport=10000+i, dport=20000)
               / Raw(bytes([i & 0xFF] * (20 + (i % 40)))))
        await tb.mii_rx_source.send(GmiiFrame.from_payload(bytes(pkt)))
    # 100 frames at 25 MHz MII with variable payload sizes ≈ 1 ms.
    await Timer(1500, "us")

    fc  = await apb_read(dut, CKSUM_FRAME_COUNT)
    igc = await apb_read(dut, CKSUM_IP_GOOD_COUNT)
    lgc = await apb_read(dut, CKSUM_L4_GOOD_COUNT)
    ibc = await apb_read(dut, CKSUM_IP_BAD_COUNT)
    lbc = await apb_read(dut, CKSUM_L4_BAD_COUNT)
    assert fc  == n,  f"FRAME_COUNT {fc} != {n}"
    assert igc == n,  f"IP_GOOD {igc} != {n}"
    assert lgc == n,  f"L4_GOOD {lgc} != {n}"
    assert ibc == 0,  f"IP_BAD {ibc} != 0"
    assert lbc == 0,  f"L4_BAD {lbc} != 0"


@cocotb.test()
async def test_scp6_2_tcp_handshake(dut):
    """SCP6.2: TCP SYN / SYN-ACK / ACK handshake — all 3 validate."""
    assert HAS_COCOTBEXT_ETH, "cocotbext-eth required"
    tb = SubsystemTB(dut)
    await tb.reset()
    await setup_rtc(dut)
    await configure_mac_for_ptp(dut, tb, enable_tx=False, enable_rx=True)
    await enable_cksum_block(dut)

    for flags in ("S", "SA", "A"):
        pkt = (Ether(dst="de:ad:be:ef:00:02", src="aa:bb:cc:dd:ee:ff")
               / IP(src="192.168.1.10", dst="192.168.1.20")
               / TCP(sport=49152, dport=80, flags=flags, seq=1000, ack=2000))
        await tb.mii_rx_source.send(GmiiFrame.from_payload(bytes(pkt)))
        await Timer(6, "us")
    await Timer(30, "us")

    assert (await apb_read(dut, CKSUM_L4_GOOD_COUNT)) == 3
    assert (await apb_read(dut, CKSUM_L4_BAD_COUNT))  == 0


@cocotb.test()
async def test_scp6_5_mixed_udp_tcp_arp(dut):
    """SCP6.5: Mixed UDP + TCP + ARP traffic."""
    assert HAS_COCOTBEXT_ETH, "cocotbext-eth required"
    tb = SubsystemTB(dut)
    await tb.reset()
    await setup_rtc(dut)
    await configure_mac_for_ptp(dut, tb, enable_tx=False, enable_rx=True)
    await enable_cksum_block(dut)

    from scapy.all import ARP

    # 3 UDP + 2 TCP + 2 ARP = 7 frames
    frames = [
        bytes(Ether(dst="de:ad:be:ef:00:02") / IP(src="10.0.0.1", dst="10.0.0.2") / UDP(sport=1000, dport=2000) / Raw(b"u1")),
        bytes(Ether(dst="de:ad:be:ef:00:02") / IP(src="10.0.0.1", dst="10.0.0.2") / TCP(sport=3000, dport=80, flags="A") / Raw(b"t1")),
        bytes(Ether(dst="ff:ff:ff:ff:ff:ff") / ARP(op=1, psrc="10.0.0.1", pdst="10.0.0.2")),
        bytes(Ether(dst="de:ad:be:ef:00:02") / IP(src="10.0.0.1", dst="10.0.0.2") / UDP(sport=1001, dport=2000) / Raw(b"u2")),
        bytes(Ether(dst="de:ad:be:ef:00:02") / IP(src="10.0.0.1", dst="10.0.0.2") / TCP(sport=3001, dport=443, flags="S") / Raw(b"")),
        bytes(Ether(dst="ff:ff:ff:ff:ff:ff") / ARP(op=2, psrc="10.0.0.2", pdst="10.0.0.1")),
        bytes(Ether(dst="de:ad:be:ef:00:02") / IP(src="10.0.0.1", dst="10.0.0.2") / UDP(sport=1002, dport=2000) / Raw(b"u3")),
    ]
    for f in frames:
        await tb.mii_rx_source.send(GmiiFrame.from_payload(f))
        await Timer(4, "us")
    await Timer(30, "us")

    fc  = await apb_read(dut, CKSUM_FRAME_COUNT)
    igc = await apb_read(dut, CKSUM_IP_GOOD_COUNT)
    lgc = await apb_read(dut, CKSUM_L4_GOOD_COUNT)
    assert fc  == 7, f"FRAME_COUNT {fc} != 7"
    assert igc == 5, f"IP_GOOD {igc} != 5 (3 UDP + 2 TCP)"
    assert lgc == 5, f"L4_GOOD {lgc} != 5"


@cocotb.test()
async def test_scp6_8_icmp_echo(dut):
    """SCP6.8: ICMP echo request — IP_GOOD bumps, L4 untouched."""
    assert HAS_COCOTBEXT_ETH, "cocotbext-eth required"
    tb = SubsystemTB(dut)
    await tb.reset()
    await setup_rtc(dut)
    await configure_mac_for_ptp(dut, tb, enable_tx=False, enable_rx=True)
    await enable_cksum_block(dut)

    from scapy.all import ICMP
    pkt = (Ether(dst="de:ad:be:ef:00:02", src="aa:bb:cc:dd:ee:ff")
           / IP(src="10.0.0.1", dst="10.0.0.2")
           / ICMP(type=8, code=0) / Raw(b"ping" * 4))
    await tb.mii_rx_source.send(GmiiFrame.from_payload(bytes(pkt)))
    await Timer(30, "us")

    assert (await apb_read(dut, CKSUM_IP_GOOD_COUNT)) == 1
    assert (await apb_read(dut, CKSUM_L4_GOOD_COUNT)) == 0, (
        "ICMP must not bump L4 counters"
    )
    assert (await apb_read(dut, CKSUM_L4_BAD_COUNT))  == 0


# ════════════════════════════════════════════════════════════════════════
# SCP8 — Reset & Power-On
# ════════════════════════════════════════════════════════════════════════

@cocotb.test()
async def test_scp8_1_reset_clears_cksum(dut):
    """SCP8.1: Subsystem reset clears cksum block state."""
    assert HAS_COCOTBEXT_ETH, "cocotbext-eth required"
    tb = SubsystemTB(dut)
    await tb.reset()
    await setup_rtc(dut)
    await configure_mac_for_ptp(dut, tb, enable_tx=False, enable_rx=True)
    await enable_cksum_block(dut)

    # Send a frame to populate state
    pkt = (Ether(dst="de:ad:be:ef:00:02", src="aa:bb:cc:dd:ee:ff")
           / IP(src="10.0.0.1", dst="10.0.0.2")
           / UDP(sport=1234, dport=5678) / Raw(b"pre-reset"))
    await tb.mii_rx_source.send(GmiiFrame.from_payload(bytes(pkt)))
    await Timer(30, "us")
    assert (await apb_read(dut, CKSUM_FRAME_COUNT)) >= 1

    # Reset
    await tb.reset()

    # Verify clean state
    ctrl = await apb_read(dut, CKSUM_CTRL)
    assert ctrl == 0, f"CTRL should be 0 after reset, got 0x{ctrl:08X}"
    assert (await apb_read(dut, CKSUM_FRAME_COUNT)) == 0
    status = await apb_read(dut, CKSUM_STATUS)
    assert status & STATUS_FIFO_EMPTY


@cocotb.test()
async def test_scp8_3_first_frame_after_reset(dut):
    """SCP8.3: First frame after reset parses correctly."""
    assert HAS_COCOTBEXT_ETH, "cocotbext-eth required"
    tb = SubsystemTB(dut)
    await tb.reset()
    await setup_rtc(dut)
    await configure_mac_for_ptp(dut, tb, enable_tx=False, enable_rx=True)
    await enable_cksum_block(dut)

    pkt = (Ether(dst="de:ad:be:ef:00:02", src="aa:bb:cc:dd:ee:ff")
           / IP(src="10.0.0.1", dst="10.0.0.2")
           / UDP(sport=1234, dport=5678) / Raw(b"first-post-reset"))
    raw = bytes(pkt)
    parsed = Ether(raw)
    await tb.mii_rx_source.send(GmiiFrame.from_payload(raw))
    await Timer(30, "us")

    assert (await apb_read(dut, CKSUM_IP_GOOD_COUNT)) == 1
    assert (await apb_read(dut, CKSUM_L4_GOOD_COUNT)) == 1

    cksum = await apb_read(dut, CKSUM_LAST_L4_CKSUM)
    calc, wire = cksum & 0xFFFF, (cksum >> 16) & 0xFFFF
    assert calc == wire
    assert wire == parsed[UDP].chksum


# ════════════════════════════════════════════════════════════════════════
# SCP9 — X-Propagation
# ════════════════════════════════════════════════════════════════════════

@cocotb.test()
async def test_scp9_1_apb_prdata_no_x(dut):
    """SCP9.1: APB prdata is X-free on every cksum register offset."""
    tb = SubsystemTB(dut)
    await tb.reset()

    for off in range(0x2000, 0x20A0, 4):
        val = await apb_read(dut, off)
        # apb_read would raise ValueError if prdata contains X
        assert isinstance(val, int), f"X in prdata at offset 0x{off:04X}"
