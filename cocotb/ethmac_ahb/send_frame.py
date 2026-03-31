#!/usr/bin/env python3
"""
Send raw Ethernet frames to the ethmac_ahb simulation via Unix socket.

Usage:
    # While the simulation is running (make MODULE=test_tap_echo TESTCASE=test_socket_echo):
    python3 send_frame.py                     # send one test frame and wait for echo
    python3 send_frame.py --count 5           # send 5 frames
    python3 send_frame.py --payload "Hello!"  # custom payload
    python3 send_frame.py --hex ff01020304    # raw hex payload
"""

import argparse
import os
import socket
import struct
import sys
import time

SOCK_PATH = "/tmp/ethmac_sim.sock"
CLIENT_SOCK_PATH = "/tmp/ethmac_client.sock"

# MAC addresses
SIM_MAC  = bytes.fromhex("0200deadbeef")   # simulation's MAC
HOST_MAC = bytes.fromhex("aabbccddeeff")   # our (host) MAC


def build_frame(dst, src, ethertype, payload):
    """Build a raw Ethernet frame (no preamble/FCS — MAC adds those)."""
    frame = bytearray(dst) + bytearray(src)
    frame += struct.pack("!H", ethertype)
    frame += bytearray(payload)
    # Pad to 60-byte minimum
    if len(frame) < 60:
        frame += b'\x00' * (60 - len(frame))
    return bytes(frame)


def main():
    parser = argparse.ArgumentParser(description="Send frames to ethmac simulation")
    parser.add_argument("--socket", default=SOCK_PATH,
                        help="Unix socket path (default: %(default)s)")
    parser.add_argument("--count", type=int, default=1,
                        help="Number of frames to send (default: 1)")
    parser.add_argument("--payload", default="Hello from host!",
                        help="ASCII payload string")
    parser.add_argument("--hex", default=None,
                        help="Hex payload (overrides --payload)")
    parser.add_argument("--ethertype", default="0x88B5",
                        help="EtherType in hex (default: 0x88B5 = IEEE test)")
    parser.add_argument("--timeout", type=float, default=30.0,
                        help="Seconds to wait for echo reply (default: 30)")
    args = parser.parse_args()

    if not os.path.exists(args.socket):
        print(f"Error: socket {args.socket} not found.")
        print("Start the simulation first:")
        print("  make MODULE=test_tap_echo TESTCASE=test_socket_echo")
        sys.exit(1)

    # Build payload
    if args.hex:
        payload = bytes.fromhex(args.hex)
    else:
        payload = args.payload.encode()

    ethertype = int(args.ethertype, 16)

    # Create client socket (datagram — need a bound path to receive replies)
    try:
        os.unlink(CLIENT_SOCK_PATH)
    except FileNotFoundError:
        pass

    client = socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM)
    client.bind(CLIENT_SOCK_PATH)
    client.settimeout(args.timeout)

    try:
        for i in range(args.count):
            # Build frame: dst=SIM_MAC (so the MAC accepts it), src=HOST_MAC
            frame = build_frame(SIM_MAC, HOST_MAC, ethertype, payload)

            print(f"[{i+1}/{args.count}] Sending {len(frame)} bytes: "
                  f"dst={SIM_MAC.hex(':')} src={HOST_MAC.hex(':')} "
                  f"type=0x{ethertype:04X} payload={payload[:20]!r}...")

            client.sendto(frame, args.socket)

            # Wait for echo
            print(f"  Waiting for echo (up to {args.timeout}s, "
                  f"simulation is ~30us/s)...")
            try:
                reply, _ = client.recvfrom(2048)
                print(f"  Echo received: {len(reply)} bytes")
                print(f"    dst={reply[0:6].hex(':')}")
                print(f"    src={reply[6:12].hex(':')}")
                print(f"    type=0x{int.from_bytes(reply[12:14], 'big'):04X}")
                if len(reply) > 14:
                    print(f"    payload={reply[14:14+40]!r}")
            except socket.timeout:
                print(f"  Timeout waiting for echo (simulation may be slow)")

            if i < args.count - 1:
                time.sleep(0.1)

    finally:
        client.close()
        try:
            os.unlink(CLIENT_SOCK_PATH)
        except FileNotFoundError:
            pass

    print("Done.")


if __name__ == "__main__":
    main()
