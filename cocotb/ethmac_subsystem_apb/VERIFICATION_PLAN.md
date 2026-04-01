# Ethernet Subsystem APB — Functional Coverage Verification Plan

## DUT: `ethmac_subsystem_apb`

Combined Ethernet MAC + IEEE 1588 PTP subsystem with APB slave register
access (address-decoded via CMSDK APB mux) and AHB master DMA.

### Address Map

| Range           | Peripheral            |
|-----------------|-----------------------|
| 0x0000 – 0x0FFF | Ethernet MAC (Port 0) |
| 0x1000 – 0x1FFF | HA1588 PTP   (Port 1) |

### Architecture

```
                              +-- apb_to_wb --- eth_top (regs/BDs)
APB Slave --> apb_slave_mux --+
                              +-- apb_to_wb --- wb_slv_wrapper --- ha1588

AHB Master <-- wb_to_ahb3lite <-- eth_top (DMA)

MII <---------> eth_top (PHY interface)
                  |
                  +-- {4'b0, mrxd} --> ha1588 rx_gmii (giga_mode=0)
                  +-- {4'b0, mtxd} --> ha1588 tx_gmii (giga_mode=0)

RTC outputs <-- ha1588
int_o       <-- eth_top
```

### Clock Domains

| Clock | Frequency | Domain |
|-------|-----------|--------|
| pclk  | 100 MHz   | APB/AHB/register |
| rtc_clk | 125 MHz | RTC accumulator |
| mtx_clk / mrx_clk | 25 MHz | MII TX/RX |

---

## CP1 — APB Mux Address Decode

Verify that the CMSDK APB slave mux routes transactions to the correct
peripheral based on `paddr[15:12]`.

| ID    | Description                                   | Method |
|-------|-----------------------------------------------|--------|
| CP1.1 | Write/read to Ethernet MAC register space     | Cocotb + UVM |
| CP1.2 | Write/read to HA1588 PTP register space       | Cocotb + UVM |
| CP1.3 | Interleaved access across both peripherals    | Cocotb + UVM |
| CP1.4 | Access to disabled/unused mux port            | Cocotb + UVM |

---

## CP2 — Ethernet MAC Register Access via APB

Verify APB -> apb_to_wb -> eth_top register path.

| ID    | Description                              | Method |
|-------|------------------------------------------|--------|
| CP2.1 | Read MODER default after reset           | Cocotb + UVM |
| CP2.2 | Write/readback MODER                     | Cocotb + UVM |
| CP2.3 | Write/readback INT_MASK                  | Cocotb + UVM |
| CP2.4 | Write/readback MAC address               | Cocotb + UVM |
| CP2.5 | Buffer descriptor write/read             | Cocotb + UVM |
| CP2.6 | Walking-ones on scratch-capable register | Cocotb + UVM |

---

## CP3 — HA1588 PTP Register Access via APB

Verify APB -> apb_to_wb -> wb_slv_wrapper -> ha1588 register path.

| ID    | Description                              | Method |
|-------|------------------------------------------|--------|
| CP3.1 | Write/readback PTP scratch register      | Cocotb + UVM |
| CP3.2 | Write/readback RTC period registers      | Cocotb + UVM |
| CP3.3 | Write/readback RTC time registers        | Cocotb + UVM |
| CP3.4 | Write/readback ADJ registers             | Cocotb + UVM |
| CP3.5 | Write TSU RX message ID mask             | Cocotb + UVM |
| CP3.6 | Walking-ones on PTP scratch register     | Cocotb + UVM |

---

## CP4 — RTC Functional Operation

Verify the PTP Real-Time Clock accumulates time.

| ID    | Description                              | Method |
|-------|------------------------------------------|--------|
| CP4.1 | RTC period load and time advance         | Cocotb + UVM |
| CP4.2 | RTC direct time load                     | Cocotb + UVM |
| CP4.3 | PTP ns output advances                   | Cocotb + UVM |
| CP4.4 | One-PPS pulse generation                 | Cocotb |

---

## CP5 — Ethernet MAC DMA via AHB Master

Verify eth_top DMA master -> wb_to_ahb3lite -> AHB master port.

| ID    | Description                              | Method |
|-------|------------------------------------------|--------|
| CP5.1 | TX DMA read from AHB memory              | Cocotb + UVM |
| CP5.2 | TX frame appears on MII                  | Cocotb |
| CP5.3 | RX DMA write to AHB memory               | Cocotb |
| CP5.4 | TX interrupt fires after transmission    | Cocotb + UVM |

---

## CP6 — MII Data Path

Verify Ethernet frame TX/RX through the MII interface.

| ID    | Description                              | Method |
|-------|------------------------------------------|--------|
| CP6.1 | TX frame with CRC/PAD                    | Cocotb |
| CP6.2 | RX frame capture                         | Cocotb |
| CP6.3 | RX interrupt fires after reception       | Cocotb |

---

## CP7 — PTP Timestamping Integration (IEEE 1588 Co-Simulation)

Verify the HA1588 TSU timestamps frames flowing through the MAC's MII.
These tests exercise the full data path: MiiSource -> MAC RX -> DMA ->
firmware -> DMA -> MAC TX -> MiiSink, with ha1588 passively capturing
timestamps on both RX and TX paths.

| ID    | Description                              | Method |
|-------|------------------------------------------|--------|
| CP7.1 | RX PTP Sync timestamp captured via MAC   | Cocotb (test_ptp_cosim) |
| CP7.2 | TX PTP Sync timestamp captured via MAC   | Cocotb (test_ptp_cosim) |
| CP7.3 | PTP echo delay measurement (t3 > t2)     | Cocotb (test_ptp_cosim) |
| CP7.4 | Multiple PTP message types (Sync + Delay_Req) | Cocotb (test_ptp_cosim) |
| CP7.5 | VLAN-tagged PTP frame timestamp capture  | Cocotb (test_ptp_cosim) |
| CP7.6 | Timestamp monotonicity across N frames   | Cocotb (test_ptp_cosim) |
| CP7.7 | 1-PPS fires during active PTP traffic    | Cocotb (test_ptp_cosim) |
| CP7.8 | Full loopback: 2x Sync/Delay_Req rounds  | Cocotb (test_ptp_cosim) |

---

## CP8 — Reset Behaviour

Verify system-level reset handling.

| ID    | Description                                   | Method |
|-------|-----------------------------------------------|--------|
| CP8.1 | Reset clears MAC registers to defaults        | Cocotb + UVM |
| CP8.2 | Reset de-asserts int_o                        | Cocotb + UVM |
| CP8.3 | AHB master idle after reset                   | Cocotb + UVM |

---

## CP9 — X-Propagation (xprop)

Verify no X-values propagate to outputs under valid stimulus.

| ID    | Description                                   | Method |
|-------|-----------------------------------------------|--------|
| CP9.1 | APB prdata is X-free on valid read            | Cocotb + UVM (VCS -xprop=tmerge) |
| CP9.2 | AHB master outputs X-free during DMA          | Cocotb + UVM |
| CP9.3 | MII outputs X-free during TX                  | Cocotb |
| CP9.4 | RTC outputs X-free after period load           | Cocotb + UVM |

---

## Test Matrix

### Cocotb Tests

| Module | Test Count | Coverage Points |
|--------|-----------|-----------------|
| `test_ethmac_subsystem_apb` | 21 | CP1-CP5, CP8-CP9 |
| `test_ptp_cosim`            | 8  | CP7.1-CP7.8 |

### UVM Tests

| Test | Coverage Points |
|------|-----------------|
| `subsystem_register_test` | CP1-CP3 |
| `subsystem_random_test` | CP1-CP3 |
| `subsystem_reset_test` | CP8 |
| `subsystem_rtc_test` | CP4.1-CP4.3 |
| `subsystem_dma_test` | CP5.1, CP5.4 |

---

## Code Coverage Targets (ASIC)

| Metric | Target | Notes |
|--------|--------|-------|
| Line coverage | >= 95% | Excluding unreachable dead code |
| Branch coverage | >= 90% | All if/else/case arms |
| Condition coverage | >= 85% | Boolean sub-expressions |
| Toggle coverage | >= 90% | All flip-flop outputs |
| FSM coverage | 100% | All states and transitions |

Coverage is collected via VCS `-cm line+cond+tgl+fsm+branch` flags and merged
across all test runs using `urg`.
