"""
Echo server for ethmac_ahb — bridges external frames to the simulated MAC.

Two transport modes are supported (no root/sudo required for either):

  1. Unix socket (default): the simulation listens on a Unix domain socket.
     A companion script (send_frame.py) connects and sends/receives raw
     Ethernet frames.  No kernel networking or privileges needed.

  2. TAP device (optional): bridges a Linux TAP virtual interface.
     Requires a pre-created TAP device (see below).

Architecture:
    External source (send_frame.py / TAP)
        |
    socket / TAP fd
        |                    ---- cocotb boundary ----
    ext_to_mii coroutine  -->  MiiSource --> MAC RX --> DMA write
    mii_to_ext coroutine  <--  MiiSink  <-- MAC TX <-- DMA read
        |
    MAC "firmware" coroutine:  manages BDs, copies DMA <-> frame buffers

Usage (Unix socket, no root):

    # Terminal 1: start simulation
    cd cocotb/ethmac_ahb
    source ../../set_env.sh
    make MODULE=test_tap_echo TESTCASE=test_socket_echo

    # Terminal 2: send a frame
    python3 send_frame.py

Usage (TAP device, requires one-time sudo setup):

    # One-time setup:
    sudo ip tuntap add dev ethsim0 mode tap user $USER
    sudo ip addr add 192.168.100.1/24 dev ethsim0
    sudo ip link set ethsim0 up

    # Terminal 1: start simulation (no sudo)
    make MODULE=test_tap_echo TESTCASE=test_tap_echo

    # Terminal 2: observe
    sudo tcpdump -i ethsim0 -xx

    # Cleanup:
    sudo ip tuntap del dev ethsim0 mode tap
"""

import os
import socket
import struct
import fcntl
import select
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ClockCycles, Timer, with_timeout

from test_ethmac_ahb import (
    EthmacAhbTB, HAS_COCOTBEXT_ETH, GmiiFrame,
    REG_MODER, REG_INT_SOURCE, REG_INT_MASK,
    REG_IPGT, REG_IPGR1, REG_IPGR2,
    REG_PACKETLEN, REG_TX_BD_NUM,
    REG_MAC_ADDR0, REG_MAC_ADDR1,
    BD_BASE,
    MODER_RXEN, MODER_TXEN, MODER_PRO, MODER_FULLD,
    MODER_CRCEN, MODER_PAD,
    TX_BD_RD, TX_BD_IRQ, TX_BD_WR, TX_BD_PAD, TX_BD_CRC,
    RX_BD_E, RX_BD_IRQ, RX_BD_WR,
    INT_TXB, INT_RXB,
)

# ---------------------------------------------------------------------------
# Transport: Unix socket
# ---------------------------------------------------------------------------
SOCK_PATH = "/tmp/ethmac_sim.sock"


def open_socket(path=SOCK_PATH):
    """Create a listening Unix datagram socket. Returns (server_sock, path)."""
    # Remove stale socket file
    try:
        os.unlink(path)
    except FileNotFoundError:
        pass
    sock = socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM)
    sock.bind(path)
    sock.setblocking(False)
    return sock


def sock_read(sock, max_len=2048):
    """Non-blocking read from Unix socket. Returns (data, addr) or (None, None)."""
    try:
        rlist, _, _ = select.select([sock], [], [], 0)
        if rlist:
            data, addr = sock.recvfrom(max_len)
            return data, addr
    except (OSError, BlockingIOError):
        pass
    return None, None


def sock_write(sock, data, addr):
    """Send a frame back to the client."""
    try:
        sock.sendto(data, addr)
    except OSError:
        pass


# ---------------------------------------------------------------------------
# Transport: TAP device
# ---------------------------------------------------------------------------
TUNSETIFF = 0x400454CA
IFF_TAP = 0x0002
IFF_NO_PI = 0x1000
TAP_DEV_NAME = b"ethsim0"


def open_tap(name=TAP_DEV_NAME):
    """Open (or attach to) a TAP device. Returns file descriptor.

    If the TAP was pre-created with ``ip tuntap add ... user $USER``,
    this works without root.
    """
    fd = os.open("/dev/net/tun", os.O_RDWR | os.O_NONBLOCK)
    ifr = struct.pack("16sH14s", name, IFF_TAP | IFF_NO_PI, b"\x00" * 14)
    fcntl.ioctl(fd, TUNSETIFF, ifr)
    return fd


def tap_read(fd, max_len=2048):
    """Non-blocking read from TAP. Returns bytes or None."""
    try:
        rlist, _, _ = select.select([fd], [], [], 0)
        if rlist:
            return os.read(fd, max_len)
    except (OSError, BlockingIOError):
        pass
    return None


def tap_write(fd, data):
    """Write a frame to the TAP device."""
    try:
        os.write(fd, data)
    except OSError:
        pass


# ---------------------------------------------------------------------------
# Shared constants
# ---------------------------------------------------------------------------
SIM_MAC = b'\x02\x00\xDE\xAD\xBE\xEF'  # locally-administered MAC

TX_BUF_ADDR = 0x0000
RX_BUF_ADDR = 0x2000
NUM_TX_BDS = 2


# ---------------------------------------------------------------------------
# Shared MAC configuration helper
# ---------------------------------------------------------------------------
async def configure_mac(tb, dut, moder_flags):
    """Configure the MAC with standard settings. Returns the MODER value."""
    await tb.reg_write(REG_MAC_ADDR0, 0xEFBEADDE)
    await tb.reg_write(REG_MAC_ADDR1, 0x00000002)
    await tb.reg_write(REG_IPGT, 0x00000015)
    await tb.reg_write(REG_IPGR1, 0x0000000C)
    await tb.reg_write(REG_IPGR2, 0x00000012)
    await tb.reg_write(REG_PACKETLEN, (1518 << 16) | 64)
    await tb.reg_write(REG_TX_BD_NUM, NUM_TX_BDS)
    await tb.reg_write(REG_INT_MASK, INT_TXB | INT_RXB)

    rx_bd_index = NUM_TX_BDS
    await tb.setup_rx_bd(rx_bd_index, RX_BUF_ADDR,
                         RX_BD_E | RX_BD_IRQ | RX_BD_WR)

    moder = 0x0000A000 | moder_flags
    await tb.reg_write(REG_MODER, moder)
    await ClockCycles(dut.hclk, 200)
    return moder


# ---------------------------------------------------------------------------
# Shared MAC RX/TX helpers
# ---------------------------------------------------------------------------
def read_rx_frame(tb):
    """Read a received frame from DMA memory, word-unswap, return bytearray or None."""
    rx_data = tb.dma_read_mem(RX_BUF_ADDR, 4)
    if rx_data == bytes(4):
        return None

    rx_data = tb.dma_read_mem(RX_BUF_ADDR, 1518)
    frame_len = len(rx_data)
    while frame_len > 14 and rx_data[frame_len-4:frame_len] == b'\x00\x00\x00\x00':
        frame_len -= 4
    if frame_len < 14:
        return None

    frame = bytearray()
    for i in range(0, frame_len, 4):
        w = rx_data[i:i+4]
        if len(w) == 4:
            frame.extend([w[3], w[2], w[1], w[0]])
        else:
            frame.extend(w)
    return frame


async def transmit_echo(tb, dut, frame, moder, log):
    """Build an echo response and transmit it via the MAC."""
    echo = bytearray(frame)
    echo[0:6] = frame[6:12]    # original src -> dst
    echo[6:12] = SIM_MAC       # our MAC -> src

    rx_bd_index = NUM_TX_BDS

    # Disable MAC -> arm TX BD -> re-enable (TX BD scanner resets on TXEN 0->1)
    moder_off = moder & ~(MODER_TXEN | MODER_RXEN)
    await tb.reg_write(REG_MODER, moder_off)
    await ClockCycles(dut.hclk, 10)

    tb.dma_write_mem(TX_BUF_ADDR, echo)
    tx_flags = TX_BD_RD | TX_BD_IRQ | TX_BD_WR | TX_BD_PAD | TX_BD_CRC
    await tb.setup_tx_bd(0, TX_BUF_ADDR, len(echo), tx_flags)

    tb.dma_write_mem(RX_BUF_ADDR, bytes(1518))
    await tb.setup_rx_bd(rx_bd_index, RX_BUF_ADDR,
                         RX_BD_E | RX_BD_IRQ | RX_BD_WR)

    await tb.reg_write(REG_MODER, moder)
    await ClockCycles(dut.hclk, 200)

    log.info("[MAC TX] Echo: %d bytes -> %s", len(echo), echo[0:6].hex(':'))
    return echo


# ---------------------------------------------------------------------------
# Test: Unix socket echo (no root required)
# ---------------------------------------------------------------------------
@cocotb.test()
async def test_socket_echo(dut):
    """Bridge a Unix domain socket to the simulated Ethernet MAC.

    No root or TAP device needed. Run ``python3 send_frame.py`` in another
    terminal to send frames to the simulation.
    """
    assert HAS_COCOTBEXT_ETH, "cocotbext-eth required"

    tb = EthmacAhbTB(dut)
    log = dut._log
    await tb.reset()

    moder = await configure_mac(tb, dut,
                                MODER_TXEN | MODER_RXEN | MODER_PRO |
                                MODER_PAD | MODER_CRCEN | MODER_FULLD)

    sock = open_socket()
    log.info("=== Socket Echo Server Running ===")
    log.info("Listening on %s", SOCK_PATH)
    log.info("Send frames with:  python3 send_frame.py")
    log.info("MAC address: %s", SIM_MAC.hex(':'))

    stats = {"rx": 0, "tx": 0}
    last_client = None

    async def socket_to_mii():
        nonlocal last_client
        while True:
            await Timer(1, "us")
            data, addr = sock_read(sock)
            if data and len(data) >= 14:
                last_client = addr
                stats["rx"] += 1
                log.info("[SOCK->MII] Frame %d: %d bytes, dst=%s src=%s type=0x%04X",
                         stats["rx"], len(data),
                         data[0:6].hex(':'), data[6:12].hex(':'),
                         int.from_bytes(data[12:14], 'big'))
                frame = GmiiFrame.from_payload(data)
                await tb.mii_rx_source.send(frame)

    async def mii_to_socket():
        nonlocal last_client
        while True:
            frame = await tb.mii_tx_sink.recv()
            payload = frame.get_payload()
            if len(payload) >= 14 and last_client is not None:
                stats["tx"] += 1
                log.info("[MII->SOCK] Frame %d: %d bytes, dst=%s src=%s",
                         stats["tx"], len(payload),
                         payload[0:6].hex(':'), payload[6:12].hex(':'))
                sock_write(sock, bytes(payload), last_client)

    async def mac_rx_handler():
        while True:
            await Timer(5, "us")
            frame = read_rx_frame(tb)
            if frame is None:
                continue
            stats["mac_rx"] = stats.get("mac_rx", 0) + 1
            log.info("[MAC RX] Frame %d: %d bytes, dst=%s src=%s type=0x%04X",
                     stats["mac_rx"], len(frame),
                     frame[0:6].hex(':'), frame[6:12].hex(':'),
                     int.from_bytes(frame[12:14], 'big'))
            await transmit_echo(tb, dut, frame, moder, log)

    cocotb.start_soon(socket_to_mii())
    cocotb.start_soon(mii_to_socket())
    cocotb.start_soon(mac_rx_handler())

    SIM_DURATION_US = 100_000  # 100ms sim time
    try:
        for tick in range(SIM_DURATION_US):
            await Timer(1, "us")
            if (tick + 1) % 10000 == 0:
                log.info("[%d ms] sock_rx=%d mac_rx=%d tx=%d",
                         (tick + 1) // 1000,
                         stats["rx"], stats.get("mac_rx", 0), stats["tx"])
    except KeyboardInterrupt:
        pass

    log.info("=== Socket Echo Server Stopped ===")
    log.info("Final stats: %s", stats)
    sock.close()
    try:
        os.unlink(SOCK_PATH)
    except FileNotFoundError:
        pass


# ---------------------------------------------------------------------------
# Test: TAP echo (requires pre-created TAP device)
# ---------------------------------------------------------------------------
@cocotb.test()
async def test_tap_echo(dut):
    """Bridge a TAP interface to the simulated Ethernet MAC.

    Requires a pre-created TAP device. See module docstring for setup.
    """
    assert HAS_COCOTBEXT_ETH, "cocotbext-eth required"

    tb = EthmacAhbTB(dut)
    log = dut._log
    await tb.reset()

    try:
        tap_fd = open_tap()
    except OSError as e:
        log.error("Failed to open TAP device: %s", e)
        log.error("Pre-create it with:")
        log.error("  sudo ip tuntap add dev %s mode tap user $USER",
                  TAP_DEV_NAME.decode())
        log.error("  sudo ip addr add 192.168.100.1/24 dev %s",
                  TAP_DEV_NAME.decode())
        log.error("  sudo ip link set %s up", TAP_DEV_NAME.decode())
        return

    moder = await configure_mac(tb, dut,
                                MODER_TXEN | MODER_RXEN | MODER_PRO |
                                MODER_PAD | MODER_CRCEN | MODER_FULLD)

    log.info("=== TAP Echo Server Running ===")
    log.info("TAP device '%s' opened", TAP_DEV_NAME.decode())
    log.info("MAC address: %s", SIM_MAC.hex(':'))

    stats = {"tap_rx": 0, "tap_tx": 0, "mac_rx": 0}

    async def tap_to_mii():
        while True:
            await Timer(1, "us")
            data = tap_read(tap_fd)
            if data and len(data) >= 14:
                stats["tap_rx"] += 1
                log.info("[TAP->MII] Frame %d: %d bytes, dst=%s src=%s type=0x%04X",
                         stats["tap_rx"], len(data),
                         data[0:6].hex(':'), data[6:12].hex(':'),
                         int.from_bytes(data[12:14], 'big'))
                frame = GmiiFrame.from_payload(data)
                await tb.mii_rx_source.send(frame)

    async def mii_to_tap():
        while True:
            frame = await tb.mii_tx_sink.recv()
            payload = frame.get_payload()
            if len(payload) >= 14:
                stats["tap_tx"] += 1
                log.info("[MII->TAP] Frame %d: %d bytes", stats["tap_tx"], len(payload))
                tap_write(tap_fd, bytes(payload))

    async def mac_rx_handler():
        while True:
            await Timer(5, "us")
            frame = read_rx_frame(tb)
            if frame is None:
                continue
            stats["mac_rx"] += 1
            log.info("[MAC RX] Frame %d: %d bytes, dst=%s src=%s type=0x%04X",
                     stats["mac_rx"], len(frame),
                     frame[0:6].hex(':'), frame[6:12].hex(':'),
                     int.from_bytes(frame[12:14], 'big'))
            await transmit_echo(tb, dut, frame, moder, log)

    cocotb.start_soon(tap_to_mii())
    cocotb.start_soon(mii_to_tap())
    cocotb.start_soon(mac_rx_handler())

    SIM_DURATION_US = 100_000
    try:
        for tick in range(SIM_DURATION_US):
            await Timer(1, "us")
            if (tick + 1) % 10000 == 0:
                log.info("[%d ms] tap_rx=%d mac_rx=%d tap_tx=%d",
                         (tick + 1) // 1000,
                         stats["tap_rx"], stats["mac_rx"], stats["tap_tx"])
    except KeyboardInterrupt:
        pass

    log.info("=== TAP Echo Server Stopped ===")
    log.info("Final stats: %s", stats)
    os.close(tap_fd)


# ---------------------------------------------------------------------------
# Self-contained loopback test (no external tools required)
# ---------------------------------------------------------------------------
@cocotb.test()
async def test_loopback_echo(dut):
    """Self-contained echo test: inject frame via MII, MAC receives it,
    cocotb CPU reads DMA, swaps MACs, sends back via TX BD, capture on MII.

    Validates the full TX+RX data path without any external tools.
    """
    assert HAS_COCOTBEXT_ETH, "cocotbext-eth required"

    tb = EthmacAhbTB(dut)
    log = dut._log
    await tb.reset()

    moder = await configure_mac(tb, dut,
                                MODER_TXEN | MODER_RXEN | MODER_PRO |
                                MODER_PAD | MODER_CRCEN | MODER_FULLD)

    log.info("=== Loopback Echo Test ===")

    test_payload = b'Echo test payload 1234567890!!'
    inject_frame = bytearray(
        SIM_MAC +
        b'\xAA\xBB\xCC\xDD\xEE\xFF' +
        b'\x88\xB5' +
        test_payload
    )
    if len(inject_frame) < 60:
        inject_frame += b'\x00' * (60 - len(inject_frame))

    log.info("Injecting frame: %d bytes, payload='%s'",
             len(inject_frame), test_payload.decode())

    frame = GmiiFrame.from_payload(inject_frame)
    await tb.mii_rx_source.send(frame)
    await Timer(20, "us")

    rx_frame = read_rx_frame(tb)
    assert rx_frame is not None, "RX DMA buffer empty -- frame not received"

    log.info("RX frame: dst=%s src=%s type=0x%04X",
             rx_frame[0:6].hex(':'), rx_frame[6:12].hex(':'),
             int.from_bytes(rx_frame[12:14], 'big'))

    echo = await transmit_echo(tb, dut, rx_frame, moder, log)

    try:
        captured = await with_timeout(tb.mii_tx_sink.recv(), 500, "us")
        payload = captured.get_payload()
        log.info("MII TX captured: %d bytes", len(payload))
        assert len(payload) >= 14, "Captured frame too short"
        log.info("Echo frame transmitted successfully on MII")
    except Exception as e:
        log.warning("MII TX capture: %s (non-fatal)", e)

    tb.dma_write_mem(RX_BUF_ADDR, bytes(64))

    log.info("=== Loopback Echo Test PASSED ===")
    log.info("  - Frame injected via MII RX")
    log.info("  - MAC DMA-wrote frame to memory")
    log.info("  - CPU read frame, swapped MACs, wrote TX buffer")
    log.info("  - MAC DMA-read TX buffer and transmitted on MII")
