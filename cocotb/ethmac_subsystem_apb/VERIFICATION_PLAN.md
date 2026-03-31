# Ethernet Subsystem APB — Functional Coverage Verification Plan

## DUT: `ethmac_subsystem_apb`

Combined Ethernet MAC + IEEE 1588 PTP subsystem with APB slave register
access (address-decoded via CMSDK APB mux) and AHB master DMA.

### Address Map

| Range           | Peripheral            |
|-----------------|-----------------------|
| 0x0000 – 0x0FFF | Ethernet MAC (Port 0) |
| 0x1000 – 0x1FFF | HA1588 PTP   (Port 1) |

---

## CP1 — APB Mux Address Decode

Verify that the CMSDK APB slave mux routes transactions to the correct
peripheral based on `paddr[15:12]`.

| ID    | Description                                   | Stimulus                                            |
|-------|-----------------------------------------------|-----------------------------------------------------|
| CP1.1 | Write/read to Ethernet MAC register space     | APB write to 0x0004 (SCRATCH-equivalent), readback  |
| CP1.2 | Write/read to HA1588 PTP register space       | APB write to 0x1004 (PTP SCRATCH), readback         |
| CP1.3 | Interleaved access across both peripherals    | Alternating writes to 0x0xxx and 0x1xxx              |
| CP1.4 | Access to disabled/unused mux port            | APB read from 0x2000 (port 2, disabled)             |

---

## CP2 — Ethernet MAC Register Access via APB

Verify APB → apb_to_wb → eth_top register path.

| ID    | Description                              | Stimulus                                              |
|-------|------------------------------------------|-------------------------------------------------------|
| CP2.1 | Read MODER default after reset           | Read 0x0000, expect 0x0000A000                        |
| CP2.2 | Write/readback MODER                     | Write 0x0000 with TXEN\|RXEN, readback                |
| CP2.3 | Write/readback INT_MASK                  | Write 0x0008 with 0x7F, readback                      |
| CP2.4 | Write/readback MAC address               | Write 0x0040/0x0044, readback                         |
| CP2.5 | Buffer descriptor write/read             | Write BD at 0x0400, readback status + pointer          |
| CP2.6 | Walking-ones on scratch-capable register | Write 1<<n for n=0..31 to HASH0 (0x0048), readback   |

---

## CP3 — HA1588 PTP Register Access via APB

Verify APB → apb_to_wb → wb_slv_wrapper → ha1588 register path.

| ID    | Description                              | Stimulus                                              |
|-------|------------------------------------------|-------------------------------------------------------|
| CP3.1 | Write/readback PTP scratch register      | Write 0x1004 with 0xDEADBEEF, readback                |
| CP3.2 | Write/readback RTC period registers      | Write 0x1020/0x1024 (PERIOD_H/L), readback            |
| CP3.3 | Write/readback RTC time registers        | Write 0x1010–0x101C (TIME_SEC/NSC), readback          |
| CP3.4 | Write/readback ADJ registers             | Write 0x1028–0x1030 (ADJ_PERIOD/NUM), readback        |
| CP3.5 | Write TSU RX message ID mask             | Write 0x1044[31:24], readback mask bits               |
| CP3.6 | Walking-ones on PTP scratch register     | Write 1<<n for n=0..31 to 0x1004, readback            |

---

## CP4 — RTC Functional Operation

Verify the PTP Real-Time Clock accumulates time.

| ID    | Description                              | Stimulus                                              |
|-------|------------------------------------------|-------------------------------------------------------|
| CP4.1 | RTC period load and time advance         | Load 8ns period via APB, SET_PERIOD, wait, GET_TIME   |
| CP4.2 | RTC direct time load                     | Load time via APB, SET_TIME, wait, GET_TIME, verify   |
| CP4.3 | PTP ns output advances                   | After period load, observe rtc_time_ptp_ns > 0        |
| CP4.4 | One-PPS pulse generation                 | Load period, wait long enough for seconds rollover    |

---

## CP5 — Ethernet MAC DMA via AHB Master

Verify eth_top DMA master → wb_to_ahb3lite → AHB master port.

| ID    | Description                              | Stimulus                                              |
|-------|------------------------------------------|-------------------------------------------------------|
| CP5.1 | TX DMA read from AHB memory              | Configure TX BD, load frame in AHB RAM, enable TX     |
| CP5.2 | TX frame appears on MII                  | After TX DMA, verify MII TX data/enable               |
| CP5.3 | RX DMA write to AHB memory              | Inject frame on MII RX, verify data in AHB RAM        |
| CP5.4 | TX interrupt fires after transmission    | Enable INT_MASK TXB, arm TX BD, verify int_o          |

---

## CP6 — MII Data Path

Verify Ethernet frame TX/RX through the MII interface.

| ID    | Description                              | Stimulus                                              |
|-------|------------------------------------------|-------------------------------------------------------|
| CP6.1 | TX frame with CRC/PAD                    | Configure MODER with CRCEN\|PAD, send short frame     |
| CP6.2 | RX frame capture                         | Inject valid frame via MII RX, read via DMA           |
| CP6.3 | RX interrupt fires after reception       | Enable INT_MASK RXB, inject frame, verify int_o       |

---

## CP7 — PTP Timestamping Integration

Verify the HA1588 TSU timestamps frames flowing through the MAC's MII.

| ID    | Description                              | Stimulus                                              |
|-------|------------------------------------------|-------------------------------------------------------|
| CP7.1 | RX PTP timestamp captured                | Enable RX TSU mask, inject L2 PTP frame on MII RX, read queue |
| CP7.2 | TX PTP timestamp captured                | Enable TX TSU mask, transmit L2 PTP frame via MAC, read queue  |
| CP7.3 | Non-PTP frames produce no timestamp      | Inject non-PTP frame, verify queue count stays 0      |

---

## CP8 — Reset Behaviour

Verify system-level reset handling.

| ID    | Description                                   | Stimulus                                          |
|-------|-----------------------------------------------|---------------------------------------------------|
| CP8.1 | Reset clears MAC registers to defaults        | Write registers, assert reset, verify defaults     |
| CP8.2 | Reset de-asserts int_o                        | Verify int_o=0 after reset                         |
| CP8.3 | AHB master idle after reset                   | Verify htrans=IDLE after reset                     |

---

## CP9 — X-Propagation (xprop)

Verify no X-values propagate to outputs under valid stimulus.

| ID    | Description                                   | Stimulus                                          |
|-------|-----------------------------------------------|---------------------------------------------------|
| CP9.1 | APB prdata is X-free on valid read            | Read each peripheral, check no X in prdata         |
| CP9.2 | AHB master outputs X-free during DMA         | Trigger TX DMA, check haddr/hwdata not X           |
| CP9.3 | MII outputs X-free during TX                 | Transmit frame, check mtxd/mtxen not X             |
| CP9.4 | RTC outputs X-free after period load          | Load period, check rtc_time_ptp_ns not X           |
