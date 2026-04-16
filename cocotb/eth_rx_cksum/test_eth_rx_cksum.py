"""Cocotb tests for eth_rx_cksum (area-optimised flags-only architecture).

Register map:
  0x00 ID, 0x04 CTRL, 0x08 STATUS, 0x0C-0x1C counters,
  0x20 LAST_FLAGS (peek), 0x24 LAST_SEQNUM (read-pops), 0x28 IRQ_STATUS

Copyright 2026, SoC Labs (www.soclabs.org)
"""
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import FallingEdge, RisingEdge, Timer
from scapy.all import Ether, IP, IPv6, UDP, TCP, Raw, Dot1Q, ARP

# ── Register offsets ────────────────────────────────────────────────────
OFF_ID            = 0x00
OFF_CTRL          = 0x04
OFF_STATUS        = 0x08
OFF_FRAME_COUNT   = 0x0C
OFF_IP_GOOD       = 0x10
OFF_IP_BAD        = 0x14
OFF_L4_GOOD       = 0x18
OFF_L4_BAD        = 0x1C
OFF_LAST_FLAGS    = 0x20
OFF_LAST_SEQNUM   = 0x24  # read-pops
OFF_IRQ_STATUS    = 0x28

ID_VALUE          = 0x434B534D
CTRL_EN           = 1 << 0
CTRL_MODE_LAST    = 0b00 << 1
CTRL_MODE_DROP_N  = 0b01 << 1
CTRL_MODE_DROP_O  = 0b10 << 1
CTRL_IRQ_FRAME    = 1 << 8
CTRL_IRQ_BAD      = 1 << 9
CTRL_IRQ_OVF      = 1 << 10
CTRL_CLR_CTR      = 1 << 16
CTRL_CLR_FIFO     = 1 << 17
CTRL_CLR_OVF      = 1 << 18

STATUS_EMPTY      = 1 << 4
STATUS_FULL       = 1 << 5
STATUS_OVF        = 1 << 6
FIFO_DEPTH        = 2  # matches RTL default

# Flag bits in LAST_FLAGS
F_VLAN    = 1 << 0
F_IPV4    = 1 << 1
F_IPV6    = 1 << 2
F_UDP     = 1 << 3
F_TCP     = 1 << 4
F_IP_OK   = 1 << 5
F_L4_OK   = 1 << 6
F_FRAG    = 1 << 7

PCLK_NS  = 20
MRX_NS   = 40
PREAMBLE = bytes([0x55]*7 + [0xD5])
DUMMY_FCS = bytes(4)

# ── Helpers ─────────────────────────────────────────────────────────────
async def apb_write(dut, addr, data):
    dut.apb_psel.value=1; dut.apb_penable.value=0; dut.apb_paddr.value=addr
    dut.apb_pwrite.value=1; dut.apb_pwdata.value=data; dut.apb_pstrb.value=0xF
    await RisingEdge(dut.pclk)
    dut.apb_penable.value=1
    await RisingEdge(dut.pclk)
    dut.apb_psel.value=0; dut.apb_penable.value=0; dut.apb_pwrite.value=0
    await RisingEdge(dut.pclk)

async def apb_read(dut, addr):
    dut.apb_psel.value=1; dut.apb_penable.value=0; dut.apb_paddr.value=addr
    dut.apb_pwrite.value=0; dut.apb_pstrb.value=0xF
    await RisingEdge(dut.pclk)
    dut.apb_penable.value=1
    await RisingEdge(dut.pclk)
    val = int(dut.apb_prdata.value)
    dut.apb_psel.value=0; dut.apb_penable.value=0
    await RisingEdge(dut.pclk)
    return val

async def init(dut):
    cocotb.start_soon(Clock(dut.pclk, PCLK_NS, unit="ns").start())
    cocotb.start_soon(Clock(dut.mrx_clk_i, MRX_NS, unit="ns").start())
    dut.presetn.value=0; dut.mrx_rstn_i.value=0
    dut.apb_psel.value=0; dut.apb_penable.value=0; dut.apb_pwrite.value=0
    dut.apb_paddr.value=0; dut.apb_pwdata.value=0; dut.apb_pstrb.value=0xF
    dut.mrxd_i.value=0; dut.mrxdv_i.value=0; dut.mrxerr_i.value=0
    await Timer(200, unit="ns")
    dut.presetn.value=1; dut.mrx_rstn_i.value=1
    for _ in range(10): await RisingEdge(dut.pclk)

async def enable(dut, mode=CTRL_MODE_DROP_N):
    await apb_write(dut, OFF_CTRL, CTRL_EN | mode)
    for _ in range(8): await RisingEdge(dut.mrx_clk_i)

async def mii_send(dut, frame_bytes, gap=24):
    full = PREAMBLE + bytes(frame_bytes) + DUMMY_FCS
    await FallingEdge(dut.mrx_clk_i)
    for b in full:
        dut.mrxd_i.value = b & 0xF; dut.mrxdv_i.value = 1
        await FallingEdge(dut.mrx_clk_i)
        dut.mrxd_i.value = (b >> 4) & 0xF; dut.mrxdv_i.value = 1
        await FallingEdge(dut.mrx_clk_i)
    dut.mrxd_i.value = 0; dut.mrxdv_i.value = 0
    for _ in range(gap): await FallingEdge(dut.mrx_clk_i)

async def settle(dut, n=20):
    for _ in range(n): await RisingEdge(dut.pclk)

def udp_frame(**kw):
    pkt = Ether(dst="00:11:22:33:44:55", src="aa:bb:cc:dd:ee:ff") \
        / IP(src=kw.get("sip","10.0.0.1"), dst=kw.get("dip","10.0.0.2")) \
        / UDP(sport=kw.get("sp",1234), dport=kw.get("dp",5678)) \
        / Raw(kw.get("payload", b"hello"))
    return bytes(pkt)

async def pop(dut):
    """Read flags + seqnum (which pops). Returns (flags, seqnum)."""
    f = await apb_read(dut, OFF_LAST_FLAGS)
    s = await apb_read(dut, OFF_LAST_SEQNUM)
    return f & 0xFF, s

# ── Tests ───────────────────────────────────────────────────────────────
@cocotb.test()
async def test_id(dut):
    await init(dut)
    assert await apb_read(dut, OFF_ID) == ID_VALUE

@cocotb.test()
async def test_ctrl_rw(dut):
    await init(dut)
    assert await apb_read(dut, OFF_CTRL) == 0
    live = CTRL_EN | CTRL_MODE_DROP_O | CTRL_IRQ_FRAME | CTRL_IRQ_BAD | CTRL_IRQ_OVF
    await apb_write(dut, OFF_CTRL, live)
    assert await apb_read(dut, OFF_CTRL) == live
    await apb_write(dut, OFF_CTRL, CTRL_CLR_CTR)
    assert (await apb_read(dut, OFF_CTRL) & CTRL_CLR_CTR) == 0

@cocotb.test()
async def test_status_reset(dut):
    await init(dut)
    s = await apb_read(dut, OFF_STATUS)
    assert s & STATUS_EMPTY
    assert ((s >> 16) & 0xFF) == FIFO_DEPTH

@cocotb.test()
async def test_counters_zero(dut):
    await init(dut)
    for off in (OFF_FRAME_COUNT, OFF_IP_GOOD, OFF_IP_BAD, OFF_L4_GOOD, OFF_L4_BAD,
                OFF_LAST_FLAGS, OFF_LAST_SEQNUM, OFF_IRQ_STATUS):
        assert await apb_read(dut, off) == 0

@cocotb.test()
async def test_ipv4_udp_good(dut):
    await init(dut); await enable(dut)
    await mii_send(dut, udp_frame()); await settle(dut, 30)
    assert await apb_read(dut, OFF_FRAME_COUNT) == 1
    assert await apb_read(dut, OFF_IP_GOOD) == 1
    assert await apb_read(dut, OFF_L4_GOOD) == 1
    f, s = await pop(dut)
    assert f & F_IPV4; assert f & F_IP_OK; assert f & F_L4_OK; assert f & F_UDP
    assert s == 1

@cocotb.test()
async def test_ipv4_hdr_corrupt(dut):
    await init(dut); await enable(dut)
    raw = bytearray(udp_frame()); raw[22] ^= 0x80
    await mii_send(dut, bytes(raw)); await settle(dut, 30)
    assert await apb_read(dut, OFF_IP_BAD) == 1
    f, _ = await pop(dut)
    assert f & F_IPV4; assert not (f & F_IP_OK)

@cocotb.test()
async def test_l4_payload_corrupt(dut):
    await init(dut); await enable(dut)
    raw = bytearray(udp_frame(payload=b"corrupt-me")); raw[42] ^= 0xFF
    await mii_send(dut, bytes(raw)); await settle(dut, 30)
    assert await apb_read(dut, OFF_IP_GOOD) == 1
    assert await apb_read(dut, OFF_L4_BAD) == 1
    f, _ = await pop(dut)
    assert f & F_IP_OK; assert not (f & F_L4_OK)

@cocotb.test()
async def test_tcp_good(dut):
    await init(dut); await enable(dut)
    pkt = Ether(dst="00:11:22:33:44:55",src="aa:bb:cc:dd:ee:ff") \
        / IP(src="10.0.0.1",dst="10.0.0.2") / TCP(sport=80,dport=49000,flags="A") / Raw(b"tcp")
    await mii_send(dut, bytes(pkt)); await settle(dut, 30)
    assert await apb_read(dut, OFF_L4_GOOD) == 1
    f, _ = await pop(dut)
    assert f & F_TCP; assert f & F_L4_OK

@cocotb.test()
async def test_udp_zero_cksum(dut):
    await init(dut); await enable(dut)
    raw = bytearray(udp_frame()); raw[40]=0; raw[41]=0
    await mii_send(dut, bytes(raw)); await settle(dut, 30)
    assert await apb_read(dut, OFF_L4_GOOD) == 1

@cocotb.test()
async def test_vlan_tagged(dut):
    await init(dut); await enable(dut)
    pkt = Ether(type=0x8100)/Dot1Q(vlan=100,type=0x0800)/IP(src="10.0.0.1",dst="10.0.0.2") \
        /UDP(sport=3000,dport=4000)/Raw(b"vlan")
    await mii_send(dut, bytes(pkt)); await settle(dut, 30)
    f, _ = await pop(dut)
    assert f & F_VLAN; assert f & F_IPV4; assert f & F_IP_OK; assert f & F_L4_OK

@cocotb.test()
async def test_ipv4_fragment(dut):
    await init(dut); await enable(dut)
    pkt = Ether(dst="00:11:22:33:44:55",src="aa:bb:cc:dd:ee:ff") \
        / IP(src="10.0.0.1",dst="10.0.0.2",flags="MF",frag=0) / UDP()/Raw(b"frag"*4)
    await mii_send(dut, bytes(pkt)); await settle(dut, 30)
    assert await apb_read(dut, OFF_IP_GOOD) == 1
    assert await apb_read(dut, OFF_L4_GOOD) == 0
    assert await apb_read(dut, OFF_L4_BAD) == 0
    f, _ = await pop(dut)
    assert f & F_FRAG; assert f & F_IP_OK; assert not (f & F_L4_OK)

@cocotb.test()
async def test_df_only_not_fragment(dut):
    await init(dut); await enable(dut)
    pkt = Ether(dst="00:11:22:33:44:55",src="aa:bb:cc:dd:ee:ff") \
        / IP(src="10.0.0.1",dst="10.0.0.2",flags="DF") / UDP(sport=1234,dport=5678)/Raw(b"df")
    await mii_send(dut, bytes(pkt)); await settle(dut, 30)
    f, _ = await pop(dut)
    assert not (f & F_FRAG); assert f & F_L4_OK

@cocotb.test()
async def test_non_ip_frame(dut):
    await init(dut); await enable(dut)
    pkt = Ether(dst="ff:ff:ff:ff:ff:ff",src="aa:bb:cc:dd:ee:ff") / ARP(op=1)
    await mii_send(dut, bytes(pkt)); await settle(dut, 30)
    assert await apb_read(dut, OFF_FRAME_COUNT) == 1
    assert await apb_read(dut, OFF_IP_GOOD) == 0
    f, _ = await pop(dut)
    assert not (f & F_IPV4)

@cocotb.test()
async def test_rx_err_midframe(dut):
    await init(dut); await enable(dut)
    raw = udp_frame()
    full = PREAMBLE + bytes(raw) + DUMMY_FCS
    await FallingEdge(dut.mrx_clk_i)
    for i, b in enumerate(full):
        err = 1 if i == len(PREAMBLE)+18 else 0
        dut.mrxd_i.value=b&0xF; dut.mrxdv_i.value=1; dut.mrxerr_i.value=err
        await FallingEdge(dut.mrx_clk_i)
        dut.mrxd_i.value=(b>>4)&0xF; dut.mrxdv_i.value=1; dut.mrxerr_i.value=err
        await FallingEdge(dut.mrx_clk_i)
    dut.mrxd_i.value=0; dut.mrxdv_i.value=0; dut.mrxerr_i.value=0
    await settle(dut, 30)
    assert await apb_read(dut, OFF_FRAME_COUNT) == 0

@cocotb.test()
async def test_fifo_overflow_drop_new(dut):
    await init(dut); await enable(dut, CTRL_MODE_DROP_N)
    for i in range(5):
        await mii_send(dut, udp_frame(sp=1000+i))
    await settle(dut, 80)  # extra settle for OVF toggle CDC
    s = await apb_read(dut, OFF_STATUS)
    assert s & STATUS_OVF, f"OVF not set (STATUS=0x{s:08X})"

@cocotb.test()
async def test_fifo_last_only(dut):
    await init(dut); await enable(dut, CTRL_MODE_LAST)
    for i in range(4):
        await mii_send(dut, udp_frame(sp=2000+i))
    await settle(dut, 50)
    s = await apb_read(dut, OFF_STATUS)
    assert (s & 0xF) == 1  # level == 1
    _, seq = await pop(dut)
    assert seq == 4  # latest frame

@cocotb.test()
async def test_clr_counters_and_fifo(dut):
    await init(dut); await enable(dut)
    for _ in range(2): await mii_send(dut, udp_frame())
    await settle(dut, 30)
    assert await apb_read(dut, OFF_FRAME_COUNT) == 2
    await apb_write(dut, OFF_CTRL, CTRL_EN|CTRL_MODE_DROP_N|CTRL_CLR_CTR)
    await settle(dut, 5)
    assert await apb_read(dut, OFF_FRAME_COUNT) == 0
    assert not (await apb_read(dut, OFF_STATUS) & STATUS_EMPTY)  # FIFO still has data
    await apb_write(dut, OFF_CTRL, CTRL_EN|CTRL_MODE_DROP_N|CTRL_CLR_FIFO)
    await settle(dut, 30)
    assert await apb_read(dut, OFF_STATUS) & STATUS_EMPTY

@cocotb.test()
async def test_irq_frame(dut):
    await init(dut)
    await apb_write(dut, OFF_CTRL, CTRL_EN|CTRL_MODE_DROP_N|CTRL_IRQ_FRAME)
    for _ in range(8): await RisingEdge(dut.mrx_clk_i)
    assert int(dut.cksum_int_o.value) == 0
    await mii_send(dut, udp_frame()); await settle(dut, 30)
    assert int(dut.cksum_int_o.value) == 1
    await pop(dut); await settle(dut, 5)
    assert int(dut.cksum_int_o.value) == 0

@cocotb.test()
async def test_seqnum_pop(dut):
    await init(dut); await enable(dut)
    await mii_send(dut, udp_frame(sp=100)); await settle(dut, 20)
    await mii_send(dut, udp_frame(sp=200)); await settle(dut, 20)
    _, s1 = await pop(dut)
    _, s2 = await pop(dut)
    assert s1 == 1 and s2 == 2
    assert await apb_read(dut, OFF_STATUS) & STATUS_EMPTY

@cocotb.test()
async def test_burst_10(dut):
    """10 frames with interleaved drain."""
    await init(dut); await enable(dut)
    for i in range(10):
        await mii_send(dut, udp_frame(sp=3000+i, payload=bytes([i]*16)))
        if (i+1) % 2 == 0:
            await settle(dut, 20)
            while not (await apb_read(dut, OFF_STATUS) & STATUS_EMPTY):
                await pop(dut)
    await settle(dut, 30)
    while not (await apb_read(dut, OFF_STATUS) & STATUS_EMPTY):
        await pop(dut)
    assert await apb_read(dut, OFF_FRAME_COUNT) == 10
    assert await apb_read(dut, OFF_IP_GOOD) == 10
    assert await apb_read(dut, OFF_L4_GOOD) == 10

@cocotb.test()
async def test_ihl7_options(dut):
    await init(dut); await enable(dut)
    from scapy.all import IPOption_NOP, IPOption_EOL
    pkt = Ether(dst="00:11:22:33:44:55",src="aa:bb:cc:dd:ee:ff") \
        / IP(src="10.1.1.1",dst="10.2.2.2",
             options=[IPOption_NOP()]*7+[IPOption_EOL()]) \
        / UDP(sport=4321,dport=8765)/Raw(b"opts!")
    await mii_send(dut, bytes(pkt)); await settle(dut, 30)
    assert await apb_read(dut, OFF_IP_GOOD) == 1

@cocotb.test()
async def test_en_gates_fifo(dut):
    """EN=0: frame counted but no snapshot pushed."""
    await init(dut)
    await mii_send(dut, udp_frame()); await settle(dut, 30)
    assert await apb_read(dut, OFF_STATUS) & STATUS_EMPTY
    await enable(dut)
    await mii_send(dut, udp_frame()); await settle(dut, 30)
    assert not (await apb_read(dut, OFF_STATUS) & STATUS_EMPTY)
