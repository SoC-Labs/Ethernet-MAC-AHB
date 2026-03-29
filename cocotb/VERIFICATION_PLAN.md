# Ethernet MAC AHB Wrapper — Verification Plan

## 1. Scope

This plan covers verification of the bridge and adapter logic added by this
project. The OpenCores `eth_top` core itself is treated as a pre-verified IP;
tests exercise it only to the extent needed to prove the wrappers work.

### Modules Under Test (MUT)

| Module | Description |
|---|---|
| `ahb3lite_to_wb` | AHB3-Lite slave to WISHBONE slave bridge |
| `wb_to_ahb3lite` | WISHBONE master to AHB3-Lite master bridge |
| `ethmac_ahb` | Integrated wrapper (both bridges + eth_top) |
| `rmii_to_mii` | RMII to MII adapter |
| `ethmac_ahb_rmii` | Full system (ethmac_ahb + RMII adapter) |

---

## 2. Testbench Architecture

```
 ┌──────────────────────────────────────────────────────────────────┐
 │                     cocotb test (Python)                        │
 │                                                                  │
 │  ┌──────────────────┐                  ┌──────────────────────┐ │
 │  │  AHBLiteMaster   │──── AHB Slave ──>│                      │ │
 │  │ (cocotbext-ahb)  │     Port         │                      │ │
 │  └──────────────────┘                  │                      │ │
 │                                         │    ethmac_ahb (DUT)  │ │
 │  ┌──────────────────┐                  │                      │ │
 │  │ AHBLiteSlaveRAM  │<── AHB Master ──│                      │ │
 │  │ (cocotbext-ahb)  │     Port (DMA)   │                      │ │
 │  └──────────────────┘                  │                      │ │
 │                                         │                      │ │
 │  ┌──────────────────┐                  │                      │ │
 │  │    MiiPhy         │<── MII I/F ────>│                      │ │
 │  │ (cocotbext-eth)  │                  │                      │ │
 │  │  .tx (MiiSink)   │  captures TX     │                      │ │
 │  │  .rx (MiiSource) │  injects  RX     │                      │ │
 │  └──────────────────┘                  └──────────────────────┘ │
 │                                                                  │
 │  ┌──────────────────┐                                           │
 │  │   AHBMonitor     │  protocol compliance checking (optional)  │
 │  │ (cocotbext-ahb)  │                                           │
 │  └──────────────────┘                                           │
 └──────────────────────────────────────────────────────────────────┘
```

### Key Libraries

| Library | Purpose |
|---|---|
| `cocotbext-ahb` | AHB master/slave bus functional models and monitor |
| `cocotbext-eth` | MII PHY model (MiiPhy, MiiSource, MiiSink, frame objects) |
| `cocotb` | Core verification framework |

### Signal Remapping

A Verilog testbench wrapper (`tb_ethmac_ahb.v`) provides signal prefix
remapping so that `cocotbext-ahb` can bind cleanly:

| cocotbext-ahb prefix | DUT port | Direction |
|---|---|---|
| `slv_*` | AHB slave port (`*_s`) | Master drives → DUT slave |
| `mst_*` | AHB master port (DMA) | DUT master → Slave RAM responds |

---

## 3. Test Strategy

Tests are structured in layers, from isolated unit tests on individual bridges
up to integration tests on the full wrapped system.

### Layer 1 — AHB-to-WB Bridge (`ahb3lite_to_wb`)

| ID | Feature | Description | Pass Criteria |
|---|---|---|---|
| 1.1 | Single word write | AHB NONSEQ write, verify WB cyc/stb/we/adr/dat | WB signals match AHB address/data |
| 1.2 | Single word read | AHB NONSEQ read, verify returned data matches WB slave | Read data matches WB dat_o |
| 1.3 | Back-to-back transfers | Consecutive NONSEQ transfers without idle cycles | All transfers complete without stall |
| 1.4 | Idle transfer | HTRANS=IDLE should not generate WB activity | WB cyc/stb remain low |
| 1.5 | WB slave wait states | WB slave delays ACK, verify AHB HREADYOUT deasserts | HREADYOUT=0 until ACK received |
| 1.6 | WB slave error | WB err_o asserted, verify HRESP=ERROR | HRESP reflects ERROR |
| 1.7 | Reset behaviour | Verify clean state after reset assertion | All outputs at default |

### Layer 2 — WB-to-AHB Bridge (`wb_to_ahb3lite`)

| ID | Feature | Description | Pass Criteria |
|---|---|---|---|
| 2.1 | Single word write | WB master write, verify AHB NONSEQ + correct addr/data | AHB addr/data match WB master |
| 2.2 | Single word read | WB master read, verify returned data from AHB slave | WB dat_i matches AHB read data |
| 2.3 | Back-to-back transfers | Consecutive WB cycles | All transfers complete |
| 2.4 | AHB slave wait states | AHB HREADY deasserted by slave, verify WB ack delays | WB ack delayed until HREADY |
| 2.5 | AHB slave error | HRESP=ERROR, verify WB err_i returned | WB err_i asserted |
| 2.6 | Reset behaviour | Verify clean state after reset assertion | All outputs at default |

### Layer 3 — Integrated Wrapper (`ethmac_ahb`) — Register Access

| ID | Feature | Description | Pass Criteria |
|---|---|---|---|
| 3.1 | Register read defaults | Read all eth_top registers via AHB slave, check reset values | Values match eth_defines.v defaults |
| 3.2 | Register write/readback | Write known patterns to RW registers, read back via AHB | Written data == read data |
| 3.3 | MODER register | Write to MODER (0x00), readback, verify fields | All RW bits toggle correctly |
| 3.4 | MAC address registers | Write MAC_ADDR0/1 (0x40, 0x44), readback | 48-bit MAC address stored correctly |
| 3.5 | INT_MASK register | Write INT_MASK (0x08), readback | Mask bits set/clear correctly |
| 3.6 | TX_BD_NUM register | Write TX_BD_NUM (0x20), readback | BD partition value correct |
| 3.7 | IPGT register | Write IPGT (0x0C), readback | Inter-packet gap value correct |
| 3.8 | PACKETLEN register | Write PACKETLEN (0x18), readback | Min/max frame lengths correct |
| 3.9 | MIIMODER register | Write MIIMODER (0x28), readback | Clock divider and reset bits |
| 3.10 | CTRLMODER register | Write CTRLMODER (0x24), readback | Control mode bits |
| 3.11 | HASH registers | Write HASH0/1 (0x48, 0x4C), readback | Multicast hash filter |
| 3.12 | Walking-1 pattern | Write walking-1 to each RW register | Detects stuck-at-0 faults |
| 3.13 | Walking-0 pattern | Write walking-0 to each RW register | Detects stuck-at-1 faults |

### Layer 4 — Integrated Wrapper (`ethmac_ahb`) — Buffer Descriptors

| ID | Feature | Description | Pass Criteria |
|---|---|---|---|
| 4.1 | TX BD write/read | Write/read TX buffer descriptors (0x400+) | Data integrity across BD space |
| 4.2 | RX BD write/read | Write/read RX buffer descriptors | Data integrity across BD space |
| 4.3 | BD boundary test | Access first and last BD entries | Correct wrap at boundaries |
| 4.4 | BD pointer field | Write frame buffer pointers to BDs | Pointer values preserved |
| 4.5 | BD status/length field | Write status/length to BD word 0 | Status bits preserved |

### Layer 5 — Integrated Wrapper (`ethmac_ahb`) — DMA and Data Path

| ID | Feature | Description | Pass Criteria |
|---|---|---|---|
| 5.1 | DMA TX read | Configure TX BD, enable TX, verify AHB master reads frame data | Master reads from correct address with correct data |
| 5.2 | DMA RX write | Configure RX BD, inject MII frame, verify AHB master writes | Master writes received frame to correct address |
| 5.3 | TX frame on MII | Full TX: AHB slave configures, DMA reads, MII outputs frame | Valid Ethernet frame on MII TX pins |
| 5.4 | RX frame from MII | Full RX: MII injects frame, DMA writes, BD status updated | Frame data in DMA memory matches injected frame |
| 5.5 | TX-then-RX sequence | TX followed by RX on same configuration | Both paths work in sequence |
| 5.6 | Small frame TX | Transmit minimum-size frame (64 bytes) | Frame padded and transmitted correctly |
| 5.7 | Large frame TX | Transmit maximum-size frame (1518 bytes) | Full frame transmitted without truncation |
| 5.8 | Multiple TX frames | Transmit multiple frames using BD ring | All frames sent in order |
| 5.9 | Multiple RX frames | Receive multiple frames into BD ring | All frames received in order |
| 5.10 | DMA backpressure | AHB slave RAM inserts wait states during DMA | DMA completes despite wait states |

### Layer 6 — Integrated Wrapper (`ethmac_ahb`) — Interrupts

| ID | Feature | Description | Pass Criteria |
|---|---|---|---|
| 6.1 | TX complete interrupt | Enable TX interrupt, transmit frame | int_o asserts after TX done |
| 6.2 | RX complete interrupt | Enable RX interrupt, receive frame | int_o asserts after RX done |
| 6.3 | Interrupt masking | Disable interrupt via INT_MASK, verify no assertion | int_o stays low |
| 6.4 | Interrupt clear | Write to INT_SOURCE to clear interrupt | int_o deasserts |
| 6.5 | Multiple interrupts | TX and RX both complete, check combined status | INT_SOURCE reflects both events |

### Layer 7 — Integrated Wrapper (`ethmac_ahb`) — Reset and Edge Cases

| ID | Feature | Description | Pass Criteria |
|---|---|---|---|
| 7.1 | Reset clears registers | Assert hresetn, verify all registers return to defaults | All regs at default values |
| 7.2 | Reset during TX | Assert reset mid-transmission | MAC stops TX, no bus hang |
| 7.3 | Reset during DMA | Assert reset during DMA transfer | AHB master returns to IDLE |
| 7.4 | Back-to-back reg access | Rapid register writes then reads | No data corruption |
| 7.5 | Simultaneous reg + DMA | Register access while DMA active | Both paths function correctly |

### Layer 8 — RMII-to-MII Adapter (`rmii_to_mii`) — Future

| ID | Feature | Description | Pass Criteria |
|---|---|---|---|
| 8.1 | Clock division | Verify mtx_clk/mrx_clk are 25 MHz from 50 MHz ref_clk | Clock period = 40 ns |
| 8.2 | TX nibble serialisation | Drive 4-bit MII TX data, verify 2-bit RMII output sequence | Nibbles split correctly |
| 8.3 | RX nibble deserialisation | Drive 2-bit RMII RX data, verify 4-bit MII output | Nibbles merged correctly |
| 8.4 | TX enable propagation | MII txen maps to RMII tx_en over both phases | Enable held across phases |
| 8.5 | CRS_DV to CRS/RxDV decode | RMII crs_dv maps to MII mcrs and mrxdv | Signals decoded correctly |
| 8.6 | Collision detection | Simultaneous TX+RX asserts mcoll | mcoll asserted |
| 8.7 | Reset behaviour | All outputs clear on reset | All outputs = 0 |

### Layer 9 — Full System (`ethmac_ahb_rmii`) — Future

| ID | Feature | Description | Pass Criteria |
|---|---|---|---|
| 9.1 | Register access via AHB | Same as Layer 3 through RMII top-level | Register values correct |
| 9.2 | Loopback TX→RX via RMII | Transmit frame, loopback RMII TX to RX, verify reception | Received frame matches sent |

---

## 4. Register Map Reference

Byte addresses used in tests (from `eth_defines.v`):

| Address | Register | Default Value | Access |
|---|---|---|---|
| 0x00 | MODER | 0x0000_A000 | RW |
| 0x04 | INT_SOURCE | 0x0000_0000 | R/W1C |
| 0x08 | INT_MASK | 0x0000_0000 | RW |
| 0x0C | IPGT | 0x0000_0012 | RW |
| 0x10 | IPGR1 | 0x0000_000C | RW |
| 0x14 | IPGR2 | 0x0000_0012 | RW |
| 0x18 | PACKETLEN | 0x0040_0600 | RW |
| 0x1C | COLLCONF | 0x000F_003F | RW |
| 0x20 | TX_BD_NUM | 0x0000_0040 | RW |
| 0x24 | CTRLMODER | 0x0000_0000 | RW |
| 0x28 | MIIMODER | 0x0000_0064 | RW |
| 0x2C | MIICOMMAND | 0x0000_0000 | RW |
| 0x30 | MIIADDRESS | 0x0000_0000 | RW |
| 0x34 | MIITX_DATA | 0x0000_0000 | RW |
| 0x38 | MIIRX_DATA | 0x0000_0000 | RO |
| 0x3C | MIISTATUS | 0x0000_0000 | RO |
| 0x40 | MAC_ADDR0 | 0x0000_0000 | RW |
| 0x44 | MAC_ADDR1 | 0x0000_0000 | RW |
| 0x48 | HASH0 | 0x0000_0000 | RW |
| 0x4C | HASH1 | 0x0000_0000 | RW |
| 0x50 | TX_CTRL | 0x0000_0000 | RW |
| 0x54 | RX_CTRL | 0x0000_0000 | RW |
| 0x400–0x7FF | Buffer Descriptors | — | RW |

---

## 5. Pass/Fail Criteria

- All assertions in test functions pass
- No AHB protocol violations detected by monitor
- No unexpected error responses
- Interrupt signals assert/deassert as expected
- Data integrity: written data == read data for all register and DMA tests
- MII frames received match frames transmitted (accounting for preamble/FCS)

---

## 6. Environment Setup

### Prerequisites

```bash
pip install cocotb cocotbext-ahb cocotbext-eth
# Simulator: Icarus Verilog (recommended) or Verilator
sudo apt install iverilog  # or equivalent
```

### Running Tests

```bash
source set_env.sh                  # set ETHMAC_IP_DIR
cd cocotb/ethmac_ahb
make                               # run all tests
make TESTCASE=test_reg_defaults    # run single test
```
