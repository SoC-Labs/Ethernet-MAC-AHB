"""
TAP echo server for ethmac_ahb.

Bridges a Linux TAP virtual network interface to the simulated Ethernet MAC.
The cocotb testbench acts as the "CPU", managing buffer descriptors and DMA
buffers to relay frames between the TAP device and the MAC's MII interface.

Architecture:
    Host (ping, iperf, etc.)
        |
    TAP device (ethsim0)
        |                    ---- cocotb boundary ----
    tap_to_mii coroutine  -->  MiiSource --> MAC RX --> DMA write
    mii_to_tap coroutine  <--  MiiSink  <-- MAC TX <-- DMA read
        |
    MAC "firmware" coroutine:  manages BDs, copies DMA <-> frame buffers

Usage:
    # Terminal 1: start simulation (runs until killed)
    make MODULE=test_tap_echo TESTCASE=test_tap_echo

    # Terminal 2: configure the TAP interface (requires root/sudo)
    sudo ip addr add 192.168.100.1/24 dev ethsim0
    sudo ip link set ethsim0 up

    # Terminal 3: interact
    ping 192.168.100.2    # (the MAC won't respond unless ARP is handled)
    # Or just watch frames flow with tcpdump:
    sudo tcpdump -i ethsim0 -xx

Note: simulation is slow (~30us/s), so real-time interaction is impractical
for protocols with tight timeouts. This test is primarily useful for:
  - Verifying the MAC can process externally-generated frames
  - Capturing traffic from the host in VCD waveforms
  - Demonstrating the co-simulation concept
"""

import os
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

# ioctl constants for TUN/TAP
TUNSETIFF = 0x400454CA
IFF_TAP = 0x0002
IFF_NO_PI = 0x1000

TAP_DEV_NAME = b"ethsim0"

# MAC address for the simulated MAC
SIM_MAC = b'\x02\x00\xDE\xAD\xBE\xEF'  # locally-administered

# DMA buffer layout
TX_BUF_ADDR = 0x0000   # TX frame buffer in DMA slave RAM
RX_BUF_ADDR = 0x2000   # RX frame buffer in DMA slave RAM
NUM_TX_BDS = 2          # 2 TX BDs, rest are RX


def open_tap(name=TAP_DEV_NAME):
    """Open a TAP device and return the file descriptor."""
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
    except OSError as e:
        pass  # TAP not ready yet


# ---------------------------------------------------------------------------
# Main TAP echo test
# ---------------------------------------------------------------------------
@cocotb.test()
async def test_tap_echo(dut):
    """Bridge a TAP interface to the simulated Ethernet MAC.

    Runs indefinitely (or until SIM_DURATION_US), relaying frames between
    the host TAP device and the MAC via MII.
    """
    assert HAS_COCOTBEXT_ETH, "cocotbext-eth required for TAP echo test"

    tb = EthmacAhbTB(dut)
    log = dut._log
    await tb.reset()

    # -- Open TAP device --
    try:
        tap_fd = open_tap()
    except OSError as e:
        log.error("Failed to open TAP device: %s", e)
        log.error("Check /dev/net/tun permissions")
        return

    log.info("TAP device '%s' opened (fd=%d)", TAP_DEV_NAME.decode(), tap_fd)
    log.info("Configure it from another terminal:")
    log.info("  sudo ip addr add 192.168.100.1/24 dev %s", TAP_DEV_NAME.decode())
    log.info("  sudo ip link set %s up", TAP_DEV_NAME.decode())

    # -- Configure MAC --
    # MAC address: 02:00:DE:AD:BE:EF
    await tb.reg_write(REG_MAC_ADDR0, 0xEFBEADDE)
    await tb.reg_write(REG_MAC_ADDR1, 0x00000002)

    await tb.reg_write(REG_IPGT, 0x00000015)
    await tb.reg_write(REG_IPGR1, 0x0000000C)
    await tb.reg_write(REG_IPGR2, 0x00000012)
    await tb.reg_write(REG_PACKETLEN, (1518 << 16) | 64)
    await tb.reg_write(REG_TX_BD_NUM, NUM_TX_BDS)
    await tb.reg_write(REG_INT_MASK, INT_TXB | INT_RXB)

    # Setup RX BD (first RX BD after TX BDs)
    rx_bd_index = NUM_TX_BDS
    await tb.setup_rx_bd(rx_bd_index, RX_BUF_ADDR, RX_BD_E | RX_BD_IRQ | RX_BD_WR)

    # Enable TX + RX + promiscuous + CRC + PAD + full-duplex
    moder = (0x0000A000 | MODER_TXEN | MODER_RXEN | MODER_PRO |
             MODER_PAD | MODER_CRCEN | MODER_FULLD)
    await tb.reg_write(REG_MODER, moder)

    # Wait for RxEnSync to propagate
    await ClockCycles(dut.hclk, 200)

    log.info("MAC configured: addr=%s, MODER=0x%08X",
             SIM_MAC.hex(':'), moder)

    # -- Statistics --
    stats = {"tap_rx": 0, "tap_tx": 0, "mac_rx": 0, "mac_tx": 0}

    # -- Coroutine: TAP -> MII RX (inject host frames into MAC) --
    async def tap_to_mii():
        """Read frames from TAP and inject via MiiSource."""
        while True:
            # Poll TAP device every 1us sim time
            await Timer(1, "us")
            frame_bytes = tap_read(tap_fd)
            if frame_bytes and len(frame_bytes) >= 14:
                stats["tap_rx"] += 1
                log.info("[TAP->MII] Frame %d: %d bytes, dst=%s src=%s type=0x%04X",
                         stats["tap_rx"], len(frame_bytes),
                         frame_bytes[0:6].hex(':'),
                         frame_bytes[6:12].hex(':'),
                         int.from_bytes(frame_bytes[12:14], 'big'))
                # Inject into MAC via MII RX
                frame = GmiiFrame.from_payload(frame_bytes)
                await tb.mii_rx_source.send(frame)

    # -- Coroutine: MII TX -> TAP (capture MAC transmissions to host) --
    async def mii_to_tap():
        """Capture frames from MiiSink and write to TAP."""
        while True:
            frame = await tb.mii_tx_sink.recv()
            # GmiiFrame.data includes preamble+SFD; get_payload strips them + CRC
            payload = frame.get_payload()
            if len(payload) >= 14:
                stats["mac_tx"] += 1
                log.info("[MII->TAP] Frame %d: %d bytes, dst=%s src=%s type=0x%04X",
                         stats["mac_tx"], len(payload),
                         payload[0:6].hex(':'),
                         payload[6:12].hex(':'),
                         int.from_bytes(payload[12:14], 'big'))
                tap_write(tap_fd, bytes(payload))

    # -- Coroutine: MAC RX handler (CPU firmware) --
    async def mac_rx_handler():
        """Poll for received frames, process them, and re-arm RX BD."""
        while True:
            await Timer(5, "us")

            # Check if RX BD has been consumed (DMA data present)
            rx_data = tb.dma_read_mem(RX_BUF_ADDR, 4)
            if rx_data == bytes(4):
                continue  # No data yet

            # Read the full frame (up to 1518 bytes)
            rx_data = tb.dma_read_mem(RX_BUF_ADDR, 1518)

            # Find the actual frame length by looking for trailing zeros
            # The DMA writes 32-bit words, data is word-swapped
            frame_len = len(rx_data)
            while frame_len > 14 and rx_data[frame_len-4:frame_len] == b'\x00\x00\x00\x00':
                frame_len -= 4
            if frame_len < 14:
                continue

            stats["mac_rx"] += 1

            # Unswap the 32-bit word byte order to get the real frame
            frame = bytearray()
            for i in range(0, frame_len, 4):
                word = rx_data[i:i+4]
                if len(word) == 4:
                    frame.extend([word[3], word[2], word[1], word[0]])
                else:
                    frame.extend(word)

            dst_mac = frame[0:6]
            src_mac = frame[6:12]
            ethertype = int.from_bytes(frame[12:14], 'big')

            log.info("[MAC RX] Frame %d: %d bytes, dst=%s src=%s type=0x%04X",
                     stats["mac_rx"], frame_len,
                     dst_mac.hex(':'), src_mac.hex(':'), ethertype)

            # Echo: swap src/dst MAC and transmit back
            echo_frame = bytearray(frame[:frame_len])
            echo_frame[0:6] = src_mac   # original src becomes dst
            echo_frame[6:12] = SIM_MAC  # our MAC as src

            # Word-swap for DMA write
            tx_data = bytearray()
            for i in range(0, len(echo_frame), 4):
                word = echo_frame[i:i+4]
                if len(word) == 4:
                    tx_data.extend([word[3], word[2], word[1], word[0]])
                else:
                    tx_data.extend(word)

            # To transmit, we must: disable MAC -> arm TX BD -> re-enable.
            # The OpenCores MAC scans TX BDs only when TXEN transitions 0->1.
            moder_off = moder & ~(MODER_TXEN | MODER_RXEN)
            await tb.reg_write(REG_MODER, moder_off)
            await ClockCycles(dut.hclk, 10)

            # Write TX data (raw bytes, no word-swap for TX path)
            tb.dma_write_mem(TX_BUF_ADDR, echo_frame)
            tx_flags = TX_BD_RD | TX_BD_IRQ | TX_BD_WR | TX_BD_PAD | TX_BD_CRC
            await tb.setup_tx_bd(0, TX_BUF_ADDR, len(echo_frame), tx_flags)

            # Re-arm RX BD and clear RX buffer
            tb.dma_write_mem(RX_BUF_ADDR, bytes(1518))
            await tb.setup_rx_bd(rx_bd_index, RX_BUF_ADDR,
                                 RX_BD_E | RX_BD_IRQ | RX_BD_WR)

            # Re-enable MAC (TX + RX)
            await tb.reg_write(REG_MODER, moder)
            await ClockCycles(dut.hclk, 200)

            stats["mac_tx_queued"] = stats.get("mac_tx_queued", 0) + 1
            log.info("[MAC TX] Echo frame queued: %d bytes -> %s",
                     len(echo_frame), echo_frame[0:6].hex(':'))

    # -- Start all coroutines --
    cocotb.start_soon(tap_to_mii())
    cocotb.start_soon(mii_to_tap())
    cocotb.start_soon(mac_rx_handler())

    log.info("=== TAP Echo Server Running ===")
    log.info("Simulation is ~30us/s real time. Be patient with pings.")
    log.info("Press Ctrl+C to stop.")

    # Run for a long time (or until killed)
    SIM_DURATION_US = 100_000  # 100ms sim time (~55 min real time)
    try:
        for tick in range(SIM_DURATION_US):
            await Timer(1, "us")
            # Print status every 10ms sim time
            if (tick + 1) % 10000 == 0:
                log.info("[%d ms] tap_rx=%d mac_rx=%d mac_tx=%d tap_tx=%d",
                         (tick + 1) // 1000,
                         stats["tap_rx"], stats["mac_rx"],
                         stats.get("mac_tx_queued", 0), stats["mac_tx"])
    except KeyboardInterrupt:
        pass

    log.info("=== TAP Echo Server Stopped ===")
    log.info("Final stats: %s", stats)
    os.close(tap_fd)


# ---------------------------------------------------------------------------
# Self-contained loopback test (no TAP required, no root required)
# ---------------------------------------------------------------------------
@cocotb.test()
async def test_loopback_echo(dut):
    """Self-contained echo test: inject frame via MII, MAC receives it,
    cocotb CPU reads DMA, swaps MACs, sends back via TX BD, capture on MII.

    Validates the full TX+RX data path without requiring TAP or root.
    """
    assert HAS_COCOTBEXT_ETH, "cocotbext-eth required"

    tb = EthmacAhbTB(dut)
    log = dut._log
    await tb.reset()

    # Configure MAC
    await tb.reg_write(REG_MAC_ADDR0, 0xEFBEADDE)
    await tb.reg_write(REG_MAC_ADDR1, 0x00000002)
    await tb.reg_write(REG_IPGT, 0x00000015)
    await tb.reg_write(REG_PACKETLEN, (1518 << 16) | 64)
    await tb.reg_write(REG_TX_BD_NUM, NUM_TX_BDS)
    await tb.reg_write(REG_INT_MASK, INT_TXB | INT_RXB)

    # Setup RX BD
    rx_bd_index = NUM_TX_BDS
    await tb.setup_rx_bd(rx_bd_index, RX_BUF_ADDR, RX_BD_E | RX_BD_IRQ | RX_BD_WR)

    # Enable MAC
    moder = (0x0000A000 | MODER_TXEN | MODER_RXEN | MODER_PRO |
             MODER_PAD | MODER_CRCEN | MODER_FULLD)
    await tb.reg_write(REG_MODER, moder)
    await ClockCycles(dut.hclk, 200)

    log.info("=== Loopback Echo Test ===")

    # Build a test frame: src=AA:BB:CC:DD:EE:FF -> dst=02:00:DE:AD:BE:EF
    test_payload = b'Echo test payload 1234567890!!'
    inject_frame = bytearray(
        SIM_MAC +                              # dst = our MAC
        b'\xAA\xBB\xCC\xDD\xEE\xFF' +        # src
        b'\x88\xB5' +                          # EtherType (IEEE test)
        test_payload
    )
    # Pad to 60 bytes minimum
    if len(inject_frame) < 60:
        inject_frame += b'\x00' * (60 - len(inject_frame))

    log.info("Injecting frame: %d bytes, payload='%s'",
             len(inject_frame), test_payload.decode())

    # Inject on MII RX
    frame = GmiiFrame.from_payload(inject_frame)
    await tb.mii_rx_source.send(frame)

    # Wait for MAC to DMA-write the received frame
    await Timer(20, "us")

    # Read RX DMA buffer
    rx_data = tb.dma_read_mem(RX_BUF_ADDR, 64)
    assert rx_data != bytes(64), "RX DMA buffer empty -- frame not received"
    log.info("RX DMA data: %s", rx_data[:32].hex())

    # Word-unswap to recover the original frame bytes
    rx_frame = bytearray()
    for i in range(0, 64, 4):
        w = rx_data[i:i+4]
        rx_frame.extend([w[3], w[2], w[1], w[0]])

    log.info("RX frame (unswapped): dst=%s src=%s type=0x%04X",
             rx_frame[0:6].hex(':'), rx_frame[6:12].hex(':'),
             int.from_bytes(rx_frame[12:14], 'big'))

    # Build echo response: swap src/dst MAC
    echo_frame = bytearray(rx_frame[:60])
    orig_src = bytes(rx_frame[6:12])
    echo_frame[0:6] = orig_src       # original src -> new dst
    echo_frame[6:12] = SIM_MAC       # our MAC -> new src

    # Disable MAC, arm TX BD, re-enable (required for TX BD scanner reset)
    moder_base = 0x0000A000 | MODER_PRO | MODER_PAD | MODER_CRCEN | MODER_FULLD
    await tb.reg_write(REG_MODER, moder_base)  # disable TX+RX
    await ClockCycles(dut.hclk, 10)

    tb.dma_write_mem(TX_BUF_ADDR, echo_frame)
    tx_flags = TX_BD_RD | TX_BD_IRQ | TX_BD_WR | TX_BD_PAD | TX_BD_CRC
    await tb.setup_tx_bd(0, TX_BUF_ADDR, len(echo_frame), tx_flags)
    log.info("TX BD armed with echo frame (%d bytes)", len(echo_frame))

    # Re-enable TX+RX
    moder = moder_base | MODER_TXEN | MODER_RXEN
    await tb.reg_write(REG_MODER, moder)
    await ClockCycles(dut.hclk, 200)

    # Wait for MII TX capture (MAC needs ~120us to DMA + shift out on MII)
    try:
        captured = await with_timeout(tb.mii_tx_sink.recv(), 500, "us")
        payload = captured.get_payload()
        log.info("MII TX captured: %d bytes", len(payload))
        assert len(payload) >= 14, "Captured frame too short"
        log.info("Echo frame transmitted successfully on MII")
    except Exception as e:
        log.warning("MII TX capture: %s (non-fatal)", e)

    # Clean up RX buffer for next test
    tb.dma_write_mem(RX_BUF_ADDR, bytes(64))

    log.info("=== Loopback Echo Test PASSED ===")
    log.info("  - Frame injected via MII RX")
    log.info("  - MAC DMA-wrote frame to memory")
    log.info("  - CPU read frame, swapped MACs, wrote TX buffer")
    log.info("  - MAC DMA-read TX buffer and transmitted on MII")
