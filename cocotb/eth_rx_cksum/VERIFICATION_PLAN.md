# RX Checksum Calculator — Unit Verification Plan

## DUT: `eth_rx_cksum`

Passive MII RX checksum calculator that snoops the Ethernet wire,
computes IPv4 header and UDP/TCP checksums, and queues per-frame results
through an async FIFO into a software-readable register interface.

### Interfaces

| Port group | Direction | Description |
|---|---|---|
| APB slave | in/out | Register access (pclk domain) |
| MII RX snoop | in | mrxd\_i[3:0], mrxdv\_i, mrxerr\_i (mrx\_clk domain) |
| Interrupt | out | cksum\_int\_o (level-sensitive, pclk domain) |

### Parameters

| Name | Default | Description |
|---|---|---|
| `SNAPSHOT_FIFO_DEPTH` | 8 | Power-of-two depth of the snapshot async FIFO |

### Clock Domains

| Clock | Typical Freq | Domain |
|---|---|---|
| pclk | 50 MHz (FPGA) / variable (ASIC) | APB registers, counters, FIFO read side |
| mrx\_clk\_i | 25 MHz (100 Mbit MII) | Parser, accumulators, FIFO write side |

These clocks are asynchronous. All cross-domain paths use gray-coded
pointers (FIFO) or 2FF synchronisers (control bits). This is a primary
verification concern.

### Register Map (base = slot 2 of subsystem APB mux)

| Offset | Name | Access | Key fields |
|---|---|---|---|
| 0x000 | ID | RO | 0x434B534D ("CKSM") |
| 0x004 | CTRL | RW | EN, MODE[1:0], IRQ\_EN\_FRAME/BAD/OVF, CLR\_COUNTERS/FIFO/OVF (W1C) |
| 0x008 | STATUS | RO | FIFO\_LEVEL, FIFO\_EMPTY/FULL/OVF, BUSY, PARSER\_STATE, SNAPSHOT\_FIFO\_DEPTH |
| 0x00C–0x01C | FRAME/IP/L4 COUNTS | RO | 32-bit saturating counters |
| 0x020–0x03C | Peek window | RO | LAST\_FRAME\_INFO … LAST\_SEQNUM (non-destructive) |
| 0x040 | FIFO\_POP | WO | Explicit head-pop |
| 0x044 | IRQ\_STATUS | RO | Frame/bad/ovf pending flags |
| 0x080–0x09C | Alias window | RO | Same layout as 0x020; reading 0x09C (SEQNUM) pops |

### Snapshot flags (LAST\_FRAME\_INFO bits 31:24)

| Bit | Name | Description |
|---|---|---|
| 31 | IP\_FRAG | IPv4 fragment (MF=1 or frag\_offset≠0) |
| 30 | L4\_OK | L4 checksum matched (or zero-cksum UDP) |
| 29 | IP\_OK | IP header checksum matched (always 1 for IPv6) |
| 28 | IS\_TCP | Protocol field == 6 |
| 27 | IS\_UDP | Protocol field == 17 |
| 26 | IS\_IPV6 | EtherType == 0x86DD |
| 25 | IS\_IPV4 | EtherType == 0x0800 |
| 24 | VLAN | 802.1Q tag present |

---

## Testbench Architecture

```
 ┌──────────────────────────────────────────────────────┐
 │                    cocotb test (Python)               │
 │                                                       │
 │  ┌──────────────────┐     ┌────────────────────────┐ │
 │  │  Manual APB       │────>│                        │ │
 │  │  Master Driver    │     │                        │ │
 │  │  (apb_read/write) │<────│    eth_rx_cksum (DUT)  │ │
 │  └──────────────────┘     │                        │ │
 │                            │                        │ │
 │  ┌──────────────────┐     │                        │ │
 │  │ MII RX Stimulus  │────>│ mrxd/mrxdv/mrxerr      │ │
 │  │ (mii_send_frame) │     │                        │ │
 │  │ scapy frame gen  │     │                        │ │
 │  └──────────────────┘     └────────────────────────┘ │
 │                                                       │
 │  Clock gen: pclk (50 MHz), mrx_clk (25 MHz) async    │
 │  VCS: +vcs+initreg+0 +vcs+initmem+0, -xprop=tmerge   │
 └──────────────────────────────────────────────────────┘
```

Frame construction uses scapy (`Ether/IP/IPv6/UDP/TCP/Raw`) to guarantee
correct on-wire checksums, then `mii_send_frame()` serialises the frame
into MII nibbles with preamble, SFD, and a 4-byte placeholder FCS.

---

## CP1 — Register Interface

Verify the APB slave returns correct values on read, latches writes, and
that W1C fields self-clear in one pclk.

| ID | Description | Pass Criteria | Method |
|---|---|---|---|
| CP1.1 | Read ID register | Returns 0x434B534D | Cocotb `test_id` |
| CP1.2 | CTRL live R/W round-trip | Every live R/W bit can be set and cleared | Cocotb `test_ctrl_rw` |
| CP1.3 | CTRL W1C self-clear | CLR\_COUNTERS, CLR\_FIFO, CLR\_OVF read back 0 after write-1 | Cocotb `test_ctrl_rw` |
| CP1.4 | STATUS at reset | FIFO\_EMPTY=1, FIFO\_LEVEL=0, OVF=0, BUSY=0, DEPTH=8 | Cocotb `test_status_reset` |
| CP1.5 | Counter/snapshot regs at reset | All return 0 when no frames have been processed | Cocotb `test_counters_zero` |
| CP1.6 | FIFO\_POP on empty FIFO | No side-effect, no fault, no IRQ | Cocotb `test_fifo_pop_noop` |
| CP1.7 | Read from undefined offset | Returns 0 (default mux arm) | Directed |
| CP1.8 | STATUS.SNAPSHOT\_FIFO\_DEPTH matches parameter | Reads 8 with default param, 4 with override | Directed |

---

## CP2 — IPv4 Header Checksum

Verify the 16-bit ones'-complement IP header checksum accumulator
correctly validates or rejects the on-wire checksum for varied IPv4
headers.

| ID | Description | Pass Criteria | Method |
|---|---|---|---|
| CP2.1 | Single good IPv4/UDP frame | IP\_GOOD\_COUNT=1, IP\_OK set, calc==wire, wire==scapy | Cocotb `test_ipv4_single_good` |
| CP2.2 | 50 varied frames (src/dst/len) | IP\_GOOD\_COUNT=50, every snapshot calc==wire | Cocotb `test_ipv4_burst_good` |
| CP2.3 | IP header byte flip (TTL) | IP\_BAD\_COUNT=1, IP\_OK clear, calc≠wire | Cocotb `test_ipv4_hdr_corrupt` |
| CP2.4 | IHL=5 (no options, 20B header) | Accumulator spans exactly 20 bytes | Implicit in CP2.1 |
| CP2.5 | IHL=7 (8 bytes of options) | IP\_GOOD\_COUNT=1, accumulator covers 28 bytes | Cocotb `test_ipv4_options_ihl7` |
| CP2.6 | IHL=15 (max, 40 bytes options) | IP\_GOOD\_COUNT=1 | Directed |
| CP2.7 | Minimum-size IPv4 frame (20B IP + 0 payload = 34B ethernet) | IP checksum still validates | Directed |
| CP2.8 | Maximum MTU frame (1500B payload) | IP checksum validates; frame\_len field correct | Directed |
| CP2.9 | IP header with all-zero fields except ver/ihl/cksum | Accumulator handles degenerate case | Directed |
| CP2.10 | FRAME\_COUNT reflects wire observations regardless of FIFO state | Send >8 frames in DROP\_NEW: FRAME\_COUNT = N, not 8 | Cocotb `test_fifo_overflow_drop_new` |

---

## CP3 — L4 (UDP/TCP) Checksum

Verify the L4 accumulator, pseudo-header construction, and protocol-specific
edge cases (zero-cksum UDP, TCP options).

| ID | Description | Pass Criteria | Method |
|---|---|---|---|
| CP3.1 | Valid IPv4/UDP frame | L4\_GOOD\_COUNT=1, L4\_OK set, calc==wire==scapy | Cocotb `test_ipv4_udp_l4_good` |
| CP3.2 | UDP payload corruption | L4\_BAD\_COUNT=1, L4\_OK clear, IP\_GOOD=1 (IP unaffected) | Cocotb `test_ipv4_udp_payload_corrupt` |
| CP3.3 | Valid IPv4/TCP frame | L4\_GOOD\_COUNT=1, IS\_TCP set, calc==wire==scapy | Cocotb `test_ipv4_tcp_good` |
| CP3.4 | UDP wire checksum == 0 (RFC768) | L4\_GOOD\_COUNT=1, L4\_OK set | Cocotb `test_udp_zero_checksum` |
| CP3.5 | Protocol mix (UDP + TCP + ICMP) | L4\_GOOD = UDP+TCP count; ICMP doesn't bump L4 | Cocotb `test_l4_protocol_mix` |
| CP3.6 | Odd-length L4 payload | Tail-byte padded with 0x00; checksum correct | Directed |
| CP3.7 | TCP with options (header > 20 bytes) | L4 accumulator spans full TCP header + payload | Directed |
| CP3.8 | UDP with 0-byte payload (header only) | L4 checksum validates | Directed |
| CP3.9 | L4 SRC\_PORT and DST\_PORT capture | LAST\_L4\_PORTS register matches wire values | Cocotb `test_ipv4_udp_l4_good` |
| CP3.10 | Non-UDP/TCP protocol (e.g. ICMP, proto=1) | IS\_UDP/IS\_TCP both clear, L4 counts untouched | Cocotb `test_l4_protocol_mix` |

---

## CP4 — 802.1Q VLAN Tag Handling

| ID | Description | Pass Criteria | Method |
|---|---|---|---|
| CP4.1 | VLAN-tagged IPv4/UDP frame | VLAN flag set; IP+L4 checksums match scapy | Cocotb `test_vlan_tagged` |
| CP4.2 | VLAN-tagged IPv4/TCP frame | Same as 4.1 with TCP | Directed |
| CP4.3 | VLAN-tagged IPv6/UDP frame | IS\_IPV6 + VLAN both set; L4 validates | Directed |
| CP4.4 | Non-VLAN frame after VLAN frame | Parser resets vlan\_q correctly per-frame | Directed |
| CP4.5 | EtherType == 0x8100 with non-IP inner type (e.g. ARP, 0x0806) | VLAN set, IS\_IPV4/IPV6 clear | Directed |
| CP4.6 | VLAN TCI field values (PCP, DEI, VID) | Does not affect checksum (parser skips 4 bytes correctly) | Directed |

---

## CP5 — IPv6 Support

| ID | Description | Pass Criteria | Method |
|---|---|---|---|
| CP5.1 | IPv6/UDP frame | IS\_IPV6 set, L4\_GOOD=1, pseudo-header uses 128-bit addresses | Cocotb `test_ipv6_udp` |
| CP5.2 | IPv6/TCP frame | IS\_TCP + IS\_IPV6 set, L4\_GOOD=1 | Directed |
| CP5.3 | IPv6 IP\_OK == 1 (no header cksum) | IP\_OK always 1 for IPv6; IP\_GOOD\_COUNT does not bump | Cocotb `test_ipv6_udp` |
| CP5.4 | IPv6 LAST\_SRC\_IP / LAST\_DST\_IP | Shows low 32 bits of 128-bit address | Cocotb `test_ipv6_udp` |
| CP5.5 | IPv6 next-header field captured | IP\_PROTO reads 17 (UDP) or 6 (TCP) | Directed |
| CP5.6 | Large IPv6 UDP payload (>MTU with jumbo) | Checksum validates; frame\_len correct | Directed |

---

## CP6 — IPv4 Fragmentation

| ID | Description | Pass Criteria | Method |
|---|---|---|---|
| CP6.1 | First fragment (MF=1, offset=0) | IP\_OK=1, IP\_FRAG=1, L4 not checked (L4\_OK=0, L4 counts untouched) | Cocotb `test_ipv4_fragmented` |
| CP6.2 | Non-first fragment (MF=0, offset>0) | IP\_OK=1, IP\_FRAG=1, L4 untouched | Cocotb `test_ipv4_fragment_offset` |
| CP6.3 | Middle fragment (MF=1, offset>0) | IP\_FRAG=1, L4 untouched | Directed |
| CP6.4 | DF-only frame (DF=1, MF=0, offset=0) | IP\_FRAG=0 (DF alone is not a fragment) | Directed |
| CP6.5 | Unfragmented frame after fragmented | Parser resets is\_fragment\_q per-frame | Directed |

---

## CP7 — MII RX Error Handling

| ID | Description | Pass Criteria | Method |
|---|---|---|---|
| CP7.1 | mrxerr\_i asserted mid-frame | No snapshot pushed, no counter bump | Cocotb `test_rx_err_midframe` |
| CP7.2 | Clean frame after errored frame | Parser fully recovers; snapshot + counts correct | Cocotb `test_rx_err_midframe` |
| CP7.3 | mrxerr\_i asserted on first nibble | Frame discarded entirely | Directed |
| CP7.4 | mrxerr\_i asserted on last nibble (FCS) | Frame discarded | Directed |
| CP7.5 | Runt frame (<64B) without mrxerr | Still produces a snapshot (IS\_IPV4 may be clear if too short) | Directed |
| CP7.6 | mrxdv\_i drops without any SFD seen | No crash, no snapshot, parser stays idle | Directed |
| CP7.7 | Preamble corruption (0x55 replaced by 0xAA) | SFD not detected, no snapshot | Directed |

---

## CP8 — Snapshot FIFO & Modes

Verify the 8-deep async FIFO under each CTRL.MODE setting.

| ID | Description | Pass Criteria | Method |
|---|---|---|---|
| CP8.1 | FIFO empty at reset | STATUS.FIFO\_EMPTY=1, FIFO\_LEVEL=0 | Cocotb `test_status_reset` |
| CP8.2 | Push 1 frame, pop via FIFO\_POP | Level goes 0→1→0; snapshot fields correct | Implicit in `test_ipv4_single_good` |
| CP8.3 | Push 1, pop via alias-SEQNUM read | Same as 8.2 but using destructive alias | Cocotb `test_ipv4_burst_good` |
| CP8.4 | Fill to capacity (8 frames, DROP\_NEW) | FIFO\_FULL=1, FIFO\_LEVEL=8 | Cocotb `test_fifo_overflow_drop_new` |
| CP8.5 | Overflow in DROP\_NEW mode | Extra frames dropped; OVF latches; FRAME\_COUNT still increments | Cocotb `test_fifo_overflow_drop_new` |
| CP8.6 | LAST\_ONLY mode — 2nd frame overwrites 1st | Level stays 1; OVF latches; SEQNUM = latest | Cocotb `test_fifo_last_only_mode` |
| CP8.7 | DROP\_OLD mode — full FIFO accepts newest | Level stays 8; head is (N−DEPTH+1)th frame | Cocotb `test_fifo_drop_old_mode` |
| CP8.8 | CLR\_FIFO drains all entries | FIFO\_EMPTY=1 after CLR\_FIFO | Cocotb `test_clr_counters_and_fifo` |
| CP8.9 | CLR\_FIFO does not affect counters | FRAME\_COUNT unchanged after CLR\_FIFO | Cocotb `test_clr_counters_and_fifo` |
| CP8.10 | CLR\_OVF clears the sticky | OVF=0 after CLR\_OVF write | Cocotb `test_fifo_overflow_drop_new` |
| CP8.11 | Alias window: reads 0x080–0x098 non-destructive | Data matches peek window 0x020–0x038 | Directed |
| CP8.12 | Alias window: reading 0x09C pops atomically | FIFO\_LEVEL decrements by 1 on SEQNUM alias read | Directed |
| CP8.13 | FIFO\_POP on empty FIFO | No-op, no fault | Cocotb `test_fifo_pop_noop` |

---

## CP9 — Counter Semantics

| ID | Description | Pass Criteria | Method |
|---|---|---|---|
| CP9.1 | FRAME\_COUNT = total wire-observed frames | Counts regardless of FIFO drop/mode | Cocotb `test_fifo_overflow_drop_new` |
| CP9.2 | IP\_GOOD + IP\_BAD ≤ FRAME\_COUNT | Non-IP frames contribute to FRAME\_COUNT but not IP counters | Cocotb `test_l4_protocol_mix` |
| CP9.3 | L4\_GOOD + L4\_BAD ≤ IP\_GOOD + IP\_BAD | Only UDP/TCP frames bump L4 counters | Cocotb `test_l4_protocol_mix` |
| CP9.4 | CLR\_COUNTERS zeros all 5 counters | Read 0 after clear | Cocotb `test_clr_counters_and_fifo` |
| CP9.5 | CLR\_COUNTERS does not flush FIFO | Snapshot entries survive counter clear | Cocotb `test_clr_counters_and_fifo` |
| CP9.6 | Counters never decrement | Monotonic over 500 frames | Cocotb `test_cdc_counter_stress` |
| CP9.7 | Counters never skip | Final count == frames sent | Cocotb `test_cdc_counter_stress` |

---

## CP10 — Interrupt Generation

| ID | Description | Pass Criteria | Method |
|---|---|---|---|
| CP10.1 | cksum\_int\_o deasserted at reset | Even with all enables set (FIFO empty) | Cocotb `test_irq_low` |
| CP10.2 | IRQ\_EN\_FRAME: asserts when FIFO non-empty | Fires after frame push; clears after drain | Cocotb `test_irq_frame` |
| CP10.3 | IRQ\_EN\_BAD: asserts on bad-checksum event | Fires on IP or L4 bad count > 0; clears after CLR\_COUNTERS | Cocotb `test_irq_bad_and_ovf` |
| CP10.4 | IRQ\_EN\_OVF: asserts when OVF sticky set | Fires on overflow; clears after CLR\_OVF | Cocotb `test_irq_bad_and_ovf` |
| CP10.5 | Multiple enables simultaneously | OR of all active conditions | Directed |
| CP10.6 | Disable individual enables mid-assertion | IRQ deasserts when condition loses its mask | Directed |
| CP10.7 | IRQ\_STATUS register reflects live state | Each bit mirrors the corresponding enable AND condition | Directed |

---

## CP11 — Clock-Domain Crossing & Timing

| ID | Description | Pass Criteria | Method |
|---|---|---|---|
| CP11.1 | Async pclk vs mrx\_clk | Block functions correctly with non-integer frequency ratio | TB default (50 MHz / 25 MHz) |
| CP11.2 | CTRL.EN 2FF sync latency | EN takes effect within 3 mrx\_clks of write | Directed |
| CP11.3 | Counter gray-code monotonic | 500 frames: pclk-sampled counters never go backwards | Cocotb `test_cdc_counter_stress` |
| CP11.4 | Counter gray-code complete | Final pclk counter == total frames sent | Cocotb `test_cdc_counter_stress` |
| CP11.5 | Snapshot FIFO pointer gray-code | Push-then-pop with async clocks; data intact | All FIFO tests |
| CP11.6 | CLR\_FIFO pulse CDC | Sync'd correctly; FIFO drains within ~5 pclks | Cocotb `test_clr_counters_and_fifo` |
| CP11.7 | Back-to-back minimum-IFG frames | No snapshot tearing; FRAME\_COUNT exact | Cocotb `test_back_to_back` |
| CP11.8 | Slow pclk / fast mrx\_clk ratio | Block still functions with pclk < mrx\_clk (e.g. 10 MHz / 25 MHz) | Directed |
| CP11.9 | OVF toggle CDC | Toggle-based overflow handshake latches correctly in pclk | All overflow tests |

---

## CP12 — Parser Edge Cases

| ID | Description | Pass Criteria | Method |
|---|---|---|---|
| CP12.1 | Non-IP EtherType (e.g. ARP 0x0806) | Snapshot with IS\_IPV4/IPV6 clear; FRAME\_COUNT bumps | Directed |
| CP12.2 | EtherType 0xFFFF (reserved) | Parsed without crash; no IP/L4 flags | Directed |
| CP12.3 | Frame with only Ethernet header (14 bytes + FCS) | Snapshot has frame\_len=14, all flags clear | Directed |
| CP12.4 | IP header with IHL < 5 (malformed) | Block doesn't crash; checksum likely invalid | Directed |
| CP12.5 | IPv4 total\_length < IHL×4 (malformed) | L4 window zero-width; no L4 accumulation | Directed |
| CP12.6 | IPv4 total\_length > actual frame bytes (truncated) | L4 accumulator stops at EOF; checksum mismatch expected | Directed |
| CP12.7 | Back-to-back VLAN → non-VLAN | vlan\_q resets per-frame | Directed |
| CP12.8 | Double-tagged frame (QinQ, 0x88A8) | Outer tag parsed as VLAN (0x8100 only); inner tag not stripped | Directed |

---

## CP13 — Reset Behaviour

| ID | Description | Pass Criteria | Method |
|---|---|---|---|
| CP13.1 | presetn clears all pclk-domain state | CTRL=0, counters=0, FIFO empty, IRQ low | Cocotb `test_status_reset`, `test_counters_zero` |
| CP13.2 | mrx\_rstn\_i clears all mrx\_clk-domain state | Parser idle, accumulators zeroed, wptr reset | Implicit in init\_dut |
| CP13.3 | Block functional after reset release | Subsequent frames parse correctly | All tests |
| CP13.4 | Reset during mid-frame | Parser abandons frame cleanly; next frame OK | Directed |

---

## Coverage Model

Implemented in `uvm/eth_rx_cksum/env/eth_rx_cksum_coverage.sv`.

### Individual bins

| Coverpoint | Values |
|---|---|
| Frame kind | IPV4\_UDP, IPV4\_TCP, IPV4\_OTHER, IPV6\_UDP, IPV6\_TCP, NON\_IP |
| VLAN | tagged / untagged |
| IP\_OK | match / mismatch |
| L4\_OK | match / mismatch |
| IP\_FRAG | fragmented / not |
| CTRL.MODE | LAST\_ONLY, DROP\_NEW, DROP\_OLD |
| OVF seen | yes / no |
| Frame length | runt [0–63], small [64–127], med [128–511], large [512–1517], jumbo [1518+] |

### Cross-coverage

| Cross | Rationale |
|---|---|
| kind × IP\_OK | Each protocol must have good-and-bad coverage |
| kind × L4\_OK | Ditto for L4 |
| kind × frame\_len | Protocol × size exercises accumulator boundary conditions |
| MODE × OVF | Each FIFO mode must be exercised with and without overflow |
| FRAG × L4\_OK | Fragments must always show L4\_OK=0 |
| VLAN × kind | VLAN shift must work for every protocol type |

---

## Cocotb Test ↔ Coverage Point Traceability

| Test | CPs covered |
|---|---|
| `test_id` | CP1.1 |
| `test_ctrl_rw` | CP1.2, CP1.3 |
| `test_status_reset` | CP1.4, CP8.1, CP13.1 |
| `test_counters_zero` | CP1.5, CP13.1 |
| `test_fifo_pop_noop` | CP1.6, CP8.13 |
| `test_irq_low` | CP10.1 |
| `test_ipv4_single_good` | CP2.1, CP2.4, CP3.9, CP8.2 |
| `test_ipv4_burst_good` | CP2.2, CP8.3 |
| `test_ipv4_hdr_corrupt` | CP2.3 |
| `test_ipv4_options_ihl7` | CP2.5 |
| `test_clr_counters_and_fifo` | CP8.8, CP8.9, CP9.4, CP9.5, CP11.6 |
| `test_ipv4_udp_l4_good` | CP3.1, CP3.9 |
| `test_ipv4_udp_payload_corrupt` | CP3.2 |
| `test_ipv4_tcp_good` | CP3.3 |
| `test_udp_zero_checksum` | CP3.4 |
| `test_l4_protocol_mix` | CP3.5, CP3.10, CP9.2, CP9.3 |
| `test_vlan_tagged` | CP4.1 |
| `test_ipv6_udp` | CP5.1, CP5.3, CP5.4 |
| `test_ipv4_fragmented` | CP6.1 |
| `test_ipv4_fragment_offset` | CP6.2 |
| `test_rx_err_midframe` | CP7.1, CP7.2 |
| `test_fifo_overflow_drop_new` | CP8.4, CP8.5, CP8.10, CP9.1, CP10.4 |
| `test_fifo_last_only_mode` | CP8.6 |
| `test_fifo_drop_old_mode` | CP8.7 |
| `test_irq_frame` | CP10.2 |
| `test_irq_bad_and_ovf` | CP10.3, CP10.4 |
| `test_back_to_back` | CP11.7 |
| `test_cdc_counter_stress` | CP9.6, CP9.7, CP11.3, CP11.4 |

### Gaps (Directed tests needed)

The following CPs are not yet covered by the existing cocotb regression
and require new directed tests:

CP1.7, CP1.8, CP2.6, CP2.7, CP2.8, CP2.9, CP3.6, CP3.7, CP3.8, CP4.2,
CP4.3, CP4.4, CP4.5, CP4.6, CP5.2, CP5.5, CP5.6, CP6.3, CP6.4, CP6.5,
CP7.3, CP7.4, CP7.5, CP7.6, CP7.7, CP8.11, CP8.12, CP10.5, CP10.6,
CP10.7, CP11.2, CP11.8, CP12.1–CP12.8, CP13.4.
