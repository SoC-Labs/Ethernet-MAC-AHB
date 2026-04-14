"""Cocotb driver-in-the-loop tests for Ethernet MAC via compiled C driver.

Tests the actual compiled C ethmac driver (libethmac_driver.so) against
the RTL simulation using the shadow buffer + snapshot-diff replay pattern.

Requires: make driver-so  (builds libethmac_driver.so in this directory)

Usage:
    make MODULE=test_ethmac_ahb_cdriver
"""

import ctypes
import os
import sys

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ClockCycles, Timer

from cocotbext.ahb import AHBBus, AHBLiteMaster, AHBLiteSlaveRAM

# Add common directory to path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'common'))
from hal_bridge import HALBridge
import ethmac_regs_meta as meta

HCLK_PERIOD_NS = 10

# ── Load C Driver ──────────────────────────────────────────────────────

_so_path = os.path.join(os.path.dirname(__file__), 'libethmac_driver.so')
if not os.path.isfile(_so_path):
    raise FileNotFoundError(
        f"C driver shared library not found: {_so_path}\n"
        f"Run 'make driver-so' in cocotb/ethmac_ahb/ first."
    )
lib = ctypes.CDLL(_so_path)

# ── ctypes Struct Definitions ──────────────────────────────────────────


class EthmacHandle(ctypes.Structure):
    """Mirrors ethmac_t: { ETHMAC_REGS_TypeDef *regs; uint32_t *bd; uint32_t tx_bd_num; }"""
    _fields_ = [
        ("regs", ctypes.c_void_p),
        ("bd", ctypes.c_void_p),
        ("tx_bd_num", ctypes.c_uint32),
    ]


# ── C Function Prototypes ──────────────────────────────────────────────

# Host-safe init (from ethmac_test_wrappers.c)
lib.ethmac_init_host.argtypes = [
    ctypes.POINTER(EthmacHandle), ctypes.c_void_p, ctypes.c_uint32
]
lib.ethmac_init_host.restype = None

# ethmac.c functions
lib.ethmac_set_mac_addr.argtypes = [
    ctypes.POINTER(EthmacHandle), ctypes.c_char * 6
]
lib.ethmac_set_mac_addr.restype = None

lib.ethmac_init_bds.argtypes = [ctypes.POINTER(EthmacHandle)]
lib.ethmac_init_bds.restype = None

lib.ethmac_tx_bd_setup.argtypes = [
    ctypes.POINTER(EthmacHandle),
    ctypes.c_uint32, ctypes.c_uint32, ctypes.c_uint32,
    ctypes.c_uint32, ctypes.c_uint32,
]
lib.ethmac_tx_bd_setup.restype = None

lib.ethmac_rx_bd_setup.argtypes = [
    ctypes.POINTER(EthmacHandle),
    ctypes.c_uint32, ctypes.c_uint32, ctypes.c_uint32, ctypes.c_uint32,
]
lib.ethmac_rx_bd_setup.restype = None

# Wrappers for inline functions
lib.ethmac_enable_wrap.argtypes = [ctypes.POINTER(EthmacHandle)]
lib.ethmac_enable_wrap.restype = None

lib.ethmac_disable_wrap.argtypes = [ctypes.POINTER(EthmacHandle)]
lib.ethmac_disable_wrap.restype = None

lib.ethmac_set_full_duplex_wrap.argtypes = [ctypes.POINTER(EthmacHandle)]
lib.ethmac_set_full_duplex_wrap.restype = None

lib.ethmac_set_loopback_wrap.argtypes = [
    ctypes.POINTER(EthmacHandle), ctypes.c_uint32
]
lib.ethmac_set_loopback_wrap.restype = None

lib.ethmac_set_promiscuous_wrap.argtypes = [
    ctypes.POINTER(EthmacHandle), ctypes.c_uint32
]
lib.ethmac_set_promiscuous_wrap.restype = None

lib.ethmac_set_int_mask_wrap.argtypes = [
    ctypes.POINTER(EthmacHandle), ctypes.c_uint32
]
lib.ethmac_set_int_mask_wrap.restype = None

lib.ethmac_mii_set_clkdiv_wrap.argtypes = [
    ctypes.POINTER(EthmacHandle), ctypes.c_uint32
]
lib.ethmac_mii_set_clkdiv_wrap.restype = None


# ── Testbench Environment ──────────────────────────────────────────────

# Buffer size: registers (0x058) + gap to BD base (0x400) + BDs (0x400)
# Total shadow buffer must cover both register space and BD space
BUF_SIZE = 0x800  # 2KB covers registers + BDs


class EthmacCDriverTB:
    """Testbench helper for C driver-in-the-loop ethmac tests."""

    def __init__(self, dut, tx_bd_num=64):
        self.dut = dut
        self.log = dut._log
        self.tx_bd_num = tx_bd_num

        # Start system clock
        cocotb.start_soon(
            Clock(dut.hclk, HCLK_PERIOD_NS, unit="ns").start()
        )
        cocotb.start_soon(self._mii_clock_gen())

        # AHB master for register access
        slv_bus = AHBBus.from_prefix(dut, "slv")
        self.ahb = AHBLiteMaster(
            slv_bus, dut.hclk, dut.hresetn, timeout=200
        )

        # AHB slave RAM for DMA
        mst_bus = AHBBus.from_prefix(dut, "mst")
        self.dma_slave = AHBLiteSlaveRAM(
            mst_bus, dut.hclk, dut.hresetn, mem_size=65536
        )

        # HAL bridge — covers register space only (BDs handled separately)
        self.bridge = HALBridge(
            ahb_read=self._ahb_read,
            ahb_write=self._ahb_write,
            reg_size=meta.REG_SPACE_SIZE,
            rw_offsets=meta.RW_OFFSETS,
            ro_offsets=meta.RO_OFFSETS,
            trigger_offsets=meta.TRIGGER_OFFSETS,
        )

        # C driver handle
        self.eth = EthmacHandle()
        lib.ethmac_init_host(
            ctypes.byref(self.eth), self.bridge.base_addr, tx_bd_num
        )

    async def _ahb_read(self, offset):
        resp = await self.ahb.read(offset)
        return int(resp[0].get("data", "0x0"), 16)

    async def _ahb_write(self, offset, data):
        await self.ahb.write(offset, data)

    async def _mii_clock_gen(self, period_ns=40):
        half = period_ns // 2
        while True:
            self.dut.mtx_clk_pad_i.value = 0
            self.dut.mrx_clk_pad_i.value = 0
            await Timer(half, unit="ns")
            self.dut.mtx_clk_pad_i.value = 1
            self.dut.mrx_clk_pad_i.value = 1
            await Timer(half, unit="ns")

    async def reset(self, cycles=10):
        self.dut.hresetn.value = 0
        self.dut.mrxd_pad_i.value = 0
        self.dut.mrxdv_pad_i.value = 0
        self.dut.mrxerr_pad_i.value = 0
        self.dut.mcoll_pad_i.value = 0
        self.dut.mcrs_pad_i.value = 0
        self.dut.md_pad_i.value = 1
        await ClockCycles(self.dut.hclk, cycles)
        self.dut.hresetn.value = 1
        await ClockCycles(self.dut.hclk, 5)


# ══════════════════════════════════════════════════════════════════════════
# Tests
# ══════════════════════════════════════════════════════════════════════════

@cocotb.test()
async def test_cdriver_01_reg_defaults(dut):
    """CDRIVER-01: Verify register defaults after reset via C driver."""
    tb = EthmacCDriverTB(dut)
    await tb.reset()

    await tb.bridge.pre_populate()

    # MODER default: 0x0A000 (CRCEN | HUGEN | PAD | RECSMALL)
    moder = tb.bridge.buf[0x000 // 4]
    tb.log.info(f"MODER default: 0x{moder:05X}")
    assert moder == 0x0A000, f"Expected MODER=0xA000, got 0x{moder:X}"

    # TX_BD_NUM default: 0x40
    tx_bd = tb.bridge.buf[0x020 // 4]
    assert tx_bd == 0x40, f"Expected TX_BD_NUM=0x40, got 0x{tx_bd:X}"

    # IPGT default: 0x12
    ipgt = tb.bridge.buf[0x00C // 4]
    assert ipgt == 0x12, f"Expected IPGT=0x12, got 0x{ipgt:X}"


@cocotb.test()
async def test_cdriver_02_set_mac_addr(dut):
    """CDRIVER-02: Set MAC address via C driver, verify via AHB read.

    Per the OpenCores ethmac spec, the on-wire MAC byte layout is:
        MAC_ADDR1[15:8] = byte 0 (first byte on wire, MSB of address)
        MAC_ADDR1[ 7:0] = byte 1
        MAC_ADDR0[31:24]= byte 2
        MAC_ADDR0[23:16]= byte 3
        MAC_ADDR0[15:8] = byte 4
        MAC_ADDR0[ 7:0] = byte 5 (LSB on wire)

    So for mac = AA:BB:CC:DD:EE:FF (byte 0 = 0xAA):
        MAC_ADDR0 = CC:DD:EE:FF = 0xCCDDEEFF
        MAC_ADDR1 = 00:00:AA:BB = 0x0000AABB
    """
    tb = EthmacCDriverTB(dut)
    await tb.reset()

    # Set MAC to AA:BB:CC:DD:EE:FF
    mac = (ctypes.c_char * 6)(0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF)
    await tb.bridge.call_and_replay(
        lib.ethmac_set_mac_addr, ctypes.byref(tb.eth), mac
    )
    await ClockCycles(dut.hclk, 2)

    # Verify via direct AHB reads
    addr0 = await tb._ahb_read(0x40)
    addr1 = await tb._ahb_read(0x44)
    tb.log.info(f"MAC_ADDR0=0x{addr0:08X}, MAC_ADDR1=0x{addr1:04X}")
    assert addr0 == 0xCCDDEEFF, f"Expected MAC_ADDR0=0xCCDDEEFF, got 0x{addr0:X}"
    assert addr1 == 0x0000AABB, f"Expected MAC_ADDR1=0x0000AABB, got 0x{addr1:X}"


@cocotb.test()
async def test_cdriver_03_enable_disable(dut):
    """CDRIVER-03: Enable/disable TX+RX via C driver."""
    tb = EthmacCDriverTB(dut)
    await tb.reset()

    # Enable
    await tb.bridge.call_and_replay(
        lib.ethmac_enable_wrap, ctypes.byref(tb.eth)
    )
    await ClockCycles(dut.hclk, 2)

    moder = await tb._ahb_read(0x00)
    assert moder & 0x3, f"Expected TXEN|RXEN set, MODER=0x{moder:X}"

    # Disable
    await tb.bridge.call_and_replay(
        lib.ethmac_disable_wrap, ctypes.byref(tb.eth)
    )
    await ClockCycles(dut.hclk, 2)

    moder = await tb._ahb_read(0x00)
    assert not (moder & 0x3), f"Expected TXEN|RXEN clear, MODER=0x{moder:X}"


@cocotb.test()
async def test_cdriver_04_full_duplex_loopback(dut):
    """CDRIVER-04: Set full-duplex and loopback via C driver."""
    tb = EthmacCDriverTB(dut)
    await tb.reset()

    await tb.bridge.call_and_replay(
        lib.ethmac_set_full_duplex_wrap, ctypes.byref(tb.eth)
    )
    await tb.bridge.call_and_replay(
        lib.ethmac_set_loopback_wrap, ctypes.byref(tb.eth), 1
    )
    await ClockCycles(dut.hclk, 2)

    moder = await tb._ahb_read(0x00)
    fulld = (moder >> 10) & 1
    loopbk = (moder >> 7) & 1
    assert fulld, f"Expected FULLD=1, MODER=0x{moder:X}"
    assert loopbk, f"Expected LOOPBK=1, MODER=0x{moder:X}"


@cocotb.test()
async def test_cdriver_05_mii_clkdiv(dut):
    """CDRIVER-05: Set MII clock divider via C driver."""
    tb = EthmacCDriverTB(dut)
    await tb.reset()

    # Set CLKDIV to 19 (for 2.5 MHz from 100 MHz)
    await tb.bridge.call_and_replay(
        lib.ethmac_mii_set_clkdiv_wrap, ctypes.byref(tb.eth), 19
    )
    await ClockCycles(dut.hclk, 2)

    miimoder = await tb._ahb_read(0x28)
    clkdiv = miimoder & 0xFF
    assert clkdiv == 19, f"Expected CLKDIV=19, got {clkdiv}"


@cocotb.test()
async def test_cdriver_06_int_mask(dut):
    """CDRIVER-06: Set interrupt mask via C driver."""
    tb = EthmacCDriverTB(dut)
    await tb.reset()

    # Enable TXB and RXB interrupts (bits 0 and 2)
    await tb.bridge.call_and_replay(
        lib.ethmac_set_int_mask_wrap, ctypes.byref(tb.eth), 0x05
    )
    await ClockCycles(dut.hclk, 2)

    mask = await tb._ahb_read(0x08)
    assert mask == 0x05, f"Expected INT_MASK=0x05, got 0x{mask:X}"
