# RX Checksum Calculator — System-Level Verification Plan

## Scope

This plan covers verification of the `eth_rx_cksum` block as integrated
into `ethmac_subsystem_apb` (and through the AHB wrapper
`ethmac_subsystem_ahb`). Tests drive real Ethernet frames through the
OpenCores MAC's MII interface — the same path firmware and PicoTCP see —
and verify that the checksum calculator produces correct results
observable through the subsystem's APB register interface at slot 2
(base offset 0x2000).

The unit-level plan (`cocotb/eth_rx_cksum/VERIFICATION_PLAN.md`) covers
the block in isolation with fine-grained stimulus. This system plan
focuses on:

1. **End-to-end integration** — frames transit the MAC's DMA path AND
   the checksum block simultaneously; results are coherent.
2. **Coexistence with HA1588 PTP** — the checksum block and HA1588
   share the MII RX snoop tap; neither starves the other.
3. **Software driver fidelity** — the C driver
   (`eth_ss_rx_cksum.{c,h}`) can probe, enable, pop, and clear the
   block correctly through the full APB mux → AHB bridge chain.
4. **TCP/IP-level traffic scenarios** — realistic PicoTCP workloads
   (UDP echo, TCP connections, mixed traffic) exercise the checksum
   offload path end-to-end.

### Modules Under Test

| Module | Role |
|---|---|
| `eth_rx_cksum` | Passive checksum calculator (slot 2, 0x2000) |
| `ethmac_subsystem_apb` | Subsystem wrapper (APB mux, MAC, PTP, cksum) |
| `ethmac_subsystem_ahb` | AHB wrapper (AHB-to-APB bridge + subsystem) |

### Testbench Architecture

```
 ┌──────────────────────────────────────────────────────────────────────┐
 │                      cocotb test (Python)                           │
 │                                                                      │
 │  ┌──────────────────┐                  ┌──────────────────────────┐ │
 │  │  Manual APB       │──── APB Slave ──>│                          │ │
 │  │  Driver            │     Port         │  ethmac_subsystem_apb    │ │
 │  │ (apb_read/write)  │<────────────────│  ┌────────────────────┐ │ │
 │  └──────────────────┘                  │  │ eth_top (MAC+DMA)  │ │ │
 │                                         │  ├────────────────────┤ │ │
 │  ┌──────────────────┐                  │  │ ha1588 (PTP)       │ │ │
 │  │ AHBLiteSlaveRAM  │<── AHB Master ──│  ├────────────────────┤ │ │
 │  │ (cocotbext-ahb)  │     (DMA)        │  │ eth_rx_cksum       │ │ │
 │  └──────────────────┘                  │  │ (checksum calc)    │ │ │
 │                                         │  └────────────────────┘ │ │
 │  ┌──────────────────┐                  │                          │ │
 │  │  MiiSource        │── MII RX ──────>│ mrxd / mrxdv / mrxerr   │ │
 │  │ (cocotbext-eth)  │                  │   ├─> eth_top RX path   │ │
 │  │ + scapy frame    │                  │   ├─> ha1588 timestamp  │ │
 │  │   construction   │                  │   └─> eth_rx_cksum      │ │
 │  └──────────────────┘                  └──────────────────────────┘ │
 └──────────────────────────────────────────────────────────────────────┘
```

### Address Map (from CPU's perspective)

| Offset | Peripheral |
|---|---|
| 0x0000–0x0FFF | Ethernet MAC registers + buffer descriptors |
| 0x1000–0x1FFF | HA1588 PTP |
| 0x2000–0x2FFF | RX Checksum Calculator |

---

## SCP1 — APB Mux Reachability

Verify the checksum block is accessible through the APB slave mux
alongside the existing MAC and PTP blocks.

| ID | Description | Pass Criteria | Method |
|---|---|---|---|
| SCP1.1 | ID register at 0x2000 | Returns 0x434B534D ("CKSM") | Cocotb `test_cksum_cp1_id` |
| SCP1.2 | MAC regs (0x0000) still accessible | MODER readback unchanged | Cocotb `test_cp1_1_apb_mux_eth_access` |
| SCP1.3 | PTP regs (0x1000) still accessible | Scratch register readback | Cocotb `test_cp1_2_apb_mux_ptp_access` |
| SCP1.4 | Interleaved MAC → PTP → cksum access | No bus contention; all return correct data | Directed |
| SCP1.5 | Disabled port (0x3000) doesn't hang | Reads complete with default data | Cocotb `test_cp1_4_apb_mux_disabled_port` |

---

## SCP2 — MAC DMA + Checksum Coherence

Frames injected on MII are received by the MAC (DMA'd to AHB SRAM) AND
observed by the checksum block (snapshot pushed to FIFO). Verify both
paths produce consistent results for the same frame.

| ID | Description | Pass Criteria | Method |
|---|---|---|---|
| SCP2.1 | IPv4/UDP frame: MAC DMA + cksum snapshot | FRAME\_COUNT=1, IP\_GOOD=1, L4\_GOOD=1; cksum wire field == scapy; MAC DMA memory contains the same frame bytes | Cocotb `test_cksum_integration_udp` |
| SCP2.2 | IPv4/TCP frame: MAC DMA + cksum snapshot | Same consistency checks with TCP | Cocotb `test_cksum_integration_tcp` |
| SCP2.3 | Multiple frames: cksum seqnum tracks MAC BD order | Pop snapshots in FIFO order; seqnum strictly monotonic; frame\_len matches MAC-reported BD length | Directed |
| SCP2.4 | Broadcast frame (dst FF:FF:FF:FF:FF:FF) | MAC accepts in promiscuous mode; cksum block parses normally | Directed |
| SCP2.5 | Multicast frame | Same as SCP2.4 | Directed |
| SCP2.6 | Frame rejected by MAC (address filter, no promiscuous) | MAC drops; cksum block STILL observes it (passive tap) | Directed |
| SCP2.7 | Frame with CRC error (MAC signals RX error) | MAC discards via BD error flag; cksum block also discards (mrxerr gating) | Directed |

---

## SCP3 — PTP / Checksum Coexistence

The checksum block and HA1588 both tap the same MII RX nibble stream.
Neither must interfere with the other.

| ID | Description | Pass Criteria | Method |
|---|---|---|---|
| SCP3.1 | PTP Sync + UDP interleaved | cksum: FRAME\_COUNT=2, IP\_GOOD=1 (UDP only), L4\_GOOD=1; HA1588: RX TSU queue non-empty | Cocotb `test_cksum_ptp_coexist` |
| SCP3.2 | PTP Delay\_Req between two UDP frames | Both HA1588 timestamps and cksum snapshots land correctly | Directed |
| SCP3.3 | 100 rapid UDP frames with PTP Sync every 10th | cksum FRAME\_COUNT=100, IP\_GOOD=90, HA1588 captures 10 timestamps | Directed |
| SCP3.4 | PTP event detector pulse unaffected | rx\_ptp\_event fires on PTP frames exactly as before cksum block was added | Directed |
| SCP3.5 | VLAN-tagged PTP + VLAN-tagged UDP | Both subsystems handle the 4-byte VLAN shift correctly | Directed |

---

## SCP4 — Counter & FIFO via Subsystem APB

| ID | Description | Pass Criteria | Method |
|---|---|---|---|
| SCP4.1 | CLR\_COUNTERS via subsystem APB mux | All 5 counters zero after write to 0x2004 | Cocotb `test_cksum_counter_clear` |
| SCP4.2 | CLR\_FIFO via subsystem APB mux | STATUS.FIFO\_EMPTY=1 after CLR\_FIFO | Directed |
| SCP4.3 | Alias-window pop through APB mux | Read 0x209C pops FIFO head; FIFO\_LEVEL decrements | Directed |
| SCP4.4 | FIFO overflow under MAC load | Drop 12 frames in DROP\_NEW mode; FRAME\_COUNT=12, FIFO\_LEVEL=8, OVF sticky set | Directed |
| SCP4.5 | Counter overflow (saturating at 2^32-1) | Send >4G simulated frames (or force-write count near max); counter does not wrap | Directed / constrained |

---

## SCP5 — Interrupt at Subsystem Level

| ID | Description | Pass Criteria | Method |
|---|---|---|---|
| SCP5.1 | cksum\_int\_o propagates to subsystem wrapper | New output pin asserts when FIFO non-empty + IRQ\_EN\_FRAME | Directed |
| SCP5.2 | cksum\_int\_o independent from MAC int\_o | Asserting one doesn't affect the other | Directed |
| SCP5.3 | IRQ\_EN\_BAD fires on corrupt frame through MAC | Bad IP header on wire → cksum\_int\_o asserts; MAC int\_o (RXB) also fires independently | Directed |

---

## SCP6 — TCP/IP Traffic Scenarios

Realistic application-level traffic patterns that exercise the checksum
offload path as PicoTCP would see it on the Cortex-M0.

| ID | Description | Pass Criteria | Method |
|---|---|---|---|
| SCP6.1 | UDP echo: 100 back-to-back UDP packets | FRAME\_COUNT=100, IP\_GOOD=100, L4\_GOOD=100; no BAD counts; every snapshot's calc==wire | Directed |
| SCP6.2 | TCP SYN/SYN-ACK/ACK handshake | 3 TCP frames with different flag combinations; all validate L4\_OK | Directed |
| SCP6.3 | TCP data transfer (10 segments, varying payload) | L4\_GOOD=10; LAST\_L4\_PORTS shows correct src/dst for each segment | Directed |
| SCP6.4 | TCP FIN/RST | Edge-case TCP flag combos; L4 still validates | Directed |
| SCP6.5 | Mixed UDP + TCP + ARP | FRAME\_COUNT = total; IP counters = IPv4 only; L4 counters = UDP+TCP; ARP = non-IP | Directed |
| SCP6.6 | DHCP Discover/Offer (broadcast UDP, port 67/68) | L4\_GOOD bumps; ports read 67/68 from snapshot | Directed |
| SCP6.7 | DNS query + response (UDP port 53) | Correct L4 checksums on small query and larger response | Directed |
| SCP6.8 | ICMP echo request + reply | IP\_GOOD bumps (IP cksum valid); L4 untouched (ICMP not UDP/TCP) | Directed |
| SCP6.9 | IPv6 Neighbor Discovery (ICMPv6, proto=58) | IS\_IPV6 set; L4 untouched (proto != 6 or 17) | Directed |
| SCP6.10 | UDP flood at line-rate (minimum IFG) | FRAME\_COUNT matches total; OVF may fire; no counter skips/decrements | Directed |
| SCP6.11 | Frame with IP options + TCP (IHL=8, TCP w/ options) | Both IP and L4 checksums validate through extended headers | Directed |
| SCP6.12 | Jumbo frame (9000B payload) | Checksum validates for payloads beyond standard MTU | Directed |

---

## SCP7 — Software Driver Integration

Verify the bare-metal C driver (`eth_ss_rx_cksum.{c,h}`) works correctly
when called against the register interface as exposed through the
subsystem APB mux. These tests can be run via the cocotb HAL bridge
(`hal_bridge.py`) or directly in an RTL-cosim with firmware.

| ID | Description | Pass Criteria | Method |
|---|---|---|---|
| SCP7.1 | `eth_ss_rx_cksum_probe()` returns 0x434B534D | Block detected | Firmware / HAL bridge |
| SCP7.2 | `eth_ss_rx_cksum_init()` returns 0 | Init succeeds; CTRL cleared | Firmware / HAL bridge |
| SCP7.3 | `eth_ss_rx_cksum_enable(1)` → EN bit set | CTRL readback confirms EN=1 | Firmware / HAL bridge |
| SCP7.4 | `eth_ss_rx_cksum_pop()` returns snapshot matching wire | Send a frame; pop; compare fields to scapy reference | Firmware / HAL bridge |
| SCP7.5 | `eth_ss_rx_cksum_pop()` returns -1 when FIFO empty | No false data | Firmware / HAL bridge |
| SCP7.6 | `eth_ss_rx_cksum_clear_counters()` zeros all counts | Register readback confirms | Firmware / HAL bridge |
| SCP7.7 | `eth_ss_rx_cksum_flush_fifo()` drains FIFO | STATUS.FIFO\_EMPTY=1 | Firmware / HAL bridge |
| SCP7.8 | Driver absent (ID mismatch) → `init()` returns -1 | Graceful fallback; no bus fault | Firmware |
| SCP7.9 | PicoTCP poll loop with cksum pop | Per-frame pop in `eth_ss_poll()` stays in sync with MAC BD ring | Firmware cosim |
| SCP7.10 | PicoTCP poll under overflow | OVF latches; driver detects via counter mismatch | Firmware cosim |

---

## SCP8 — Reset & Power-On

| ID | Description | Pass Criteria | Method |
|---|---|---|---|
| SCP8.1 | Subsystem reset clears cksum block | CTRL=0, counters=0, FIFO empty, IRQ low | Directed |
| SCP8.2 | cksum\_int\_o low after reset | Even with EN previously set | Directed |
| SCP8.3 | First frame after reset parses correctly | All fields match scapy reference | Directed |
| SCP8.4 | Reset during mid-frame reception | MAC discards; cksum discards; next frame OK | Directed |

---

## SCP9 — X-Propagation

| ID | Description | Pass Criteria | Method |
|---|---|---|---|
| SCP9.1 | APB prdata X-free on cksum register read | No X on any offset 0x2000–0x20FF | Directed (xprop=tmerge) |
| SCP9.2 | cksum\_int\_o X-free at all times | Level output never goes X/Z | Directed (xprop) |
| SCP9.3 | Snapshot fields X-free when FIFO non-empty | No X in head\_data when occupancy > 0 | Implicit in all frame tests |
| SCP9.4 | Snapshot fields zero when FIFO empty | head\_data masked to 0; no X bleed-through | Cocotb `test_counters_zero` at unit level |

---

## SCP10 — Protocol Edge Cases at System Level

Catch scenarios where MAC + cksum interaction could diverge from
unit-test expectations (e.g. MAC adds/strips bytes the unit TB didn't).

| ID | Description | Pass Criteria | Method |
|---|---|---|---|
| SCP10.1 | MAC pads short frames to 64B | frame\_len in cksum snapshot reflects padded length, not original | Directed |
| SCP10.2 | MAC CRC strip vs cksum FCS handling | cksum subtracts 4B for FCS; MAC BD length excludes FCS; lengths match | Directed |
| SCP10.3 | SWAP\_DMA\_BYTES=1 (little-endian CPU) | MAC DMA bytes match wire order; cksum snapshot unaffected (it snoops pre-DMA) | Directed |
| SCP10.4 | SWAP\_DMA\_BYTES=0 (big-endian) | Same as SCP10.3 but with swapped byte order | Directed |
| SCP10.5 | MAC in loopback mode (MODER.LOOPBK) | TX frames loop to RX; cksum block observes them | Directed |

---

## Coverage Closure

### Required cross-coverage (system level)

| Cross | Rationale |
|---|---|
| SCP frame\_kind × MAC\_DMA\_OK | Every protocol type must DMA correctly AND checksum-validate |
| SCP frame\_kind × PTP\_coexist | PTP frame interleaved with each protocol type |
| SCP FIFO\_mode × traffic\_rate | Each mode exercised under idle, moderate, and line-rate traffic |
| SCP VLAN × MAC\_config | VLAN + promiscuous, VLAN + address filter, VLAN + broadcast |

### Sign-off criteria

1. All SCP IDs with "Directed" method implemented and passing.
2. Unit-level vplan gaps (listed in `cocotb/eth_rx_cksum/VERIFICATION_PLAN.md`)
   closed.
3. System-level cross-coverage bins >95% hit.
4. Zero X-prop failures under `+vcs+initreg+random` (randomised init
   stress).
5. 10,000-frame random regression with no counter skip/decrement.

---

## Existing Test ↔ SCP Traceability

| Test | SCPs covered |
|---|---|
| `test_cksum_cp1_id` | SCP1.1 |
| `test_cksum_integration_udp` | SCP2.1 |
| `test_cksum_integration_tcp` | SCP2.2 |
| `test_cksum_ptp_coexist` | SCP3.1 |
| `test_cksum_counter_clear` | SCP4.1 |
| `test_cp1_1_apb_mux_eth_access` | SCP1.2 |
| `test_cp1_2_apb_mux_ptp_access` | SCP1.3 |
| `test_cp1_4_apb_mux_disabled_port` | SCP1.5 |
| `test_cp1_5_apb_mux_cksum_access` | SCP1.1 (alias) |

### Gaps (tests to implement)

SCP1.4, SCP2.3–SCP2.7, SCP3.2–SCP3.5, SCP4.2–SCP4.5, SCP5.1–SCP5.3,
SCP6.1–SCP6.12, SCP7.1–SCP7.10, SCP8.1–SCP8.4, SCP9.1–SCP9.2,
SCP10.1–SCP10.5.
