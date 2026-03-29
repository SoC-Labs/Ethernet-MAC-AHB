# Ethernet MAC AHB -- Component Specification

This document describes the custom components developed around the OpenCores
Ethernet MAC (`eth_top`) to integrate it into ARM-based SoC designs using
AHB-Lite bus interfaces.

For documentation on the Ethernet MAC core itself, see the
[OpenCores Ethernet MAC Documentation](#opencores-ethernet-mac-documentation)
section at the end of this document.

## Overview

The OpenCores Ethernet MAC uses WISHBONE bus interfaces for both register
access (slave) and DMA transfers (master).  ARM-based SoCs use the AMBA
AHB-Lite protocol instead.  The components described here bridge that gap,
providing a drop-in AHB-Lite Ethernet MAC with optional RMII support.

```
                        ethmac_ahb
  +----------------------------------------------------------+
  |                                                          |
  |  AHB Slave --> AHB-to-WB --> eth_top (register port)     |
  |  (register      bridge        (OpenCores Ethernet MAC)   |
  |   access)    (ahb3lite_to_wb)      |                     |
  |                                    | DMA                 |
  |                                    v                     |
  |  AHB Master <-- WB-to-AHB <-- eth_top (master port)     |
  |  (DMA            bridge                                  |
  |   transfers)  (wb_to_ahb3lite)                           |
  |                                                          |
  |  MII <---------------------------> eth_top (PHY)         |
  |  int_o <--------------------------- eth_top (interrupt)  |
  +----------------------------------------------------------+
```

---

## Components

### 1. `ethmac_ahb` -- AHB-Lite Wrapper

**Source:** `src/rtl/generic/ethmac_ahb.v`

The top-level wrapper that replaces both WISHBONE interfaces on `eth_top` with
AHB-Lite equivalents.  All other interfaces (MII, MDIO, interrupt) are passed
through unchanged.

**AHB Slave Interface (Register Access)**

Allows a bus master (typically the CPU) to read and write the Ethernet MAC
control and status registers.  Directly maps AHB-Lite transactions to
WISHBONE slave cycles via the `ahb3lite_to_wb` bridge.

| Signal | Width | Direction | Description |
|---|---|---|---|
| `HSEL` | 1 | Input | Chip select |
| `HADDR` | 32 | Input | Address bus |
| `HWDATA` | 32 | Input | Write data |
| `HRDATA` | 32 | Output | Read data |
| `HWRITE` | 1 | Input | Write enable |
| `HTRANS` | 2 | Input | Transfer type |
| `HSIZE` | 3 | Input | Transfer size |
| `HBURST` | 3 | Input | Burst type |
| `HPROT` | 4 | Input | Protection control |
| `HREADYOUT` | 1 | Output | Transfer done |
| `HREADY` | 1 | Input | Previous transfer done |
| `HRESP` | 1 | Output | Transfer response (OK/ERROR) |

**AHB Master Interface (DMA)**

Used by the MAC to read transmit frame data from system memory and write
received frame data to system memory.  The MAC's WISHBONE master port is
translated to AHB-Lite via the `wb_to_ahb3lite` bridge.

| Signal | Width | Direction | Description |
|---|---|---|---|
| `HADDR` | 32 | Output | DMA address |
| `HWDATA` | 32 | Output | DMA write data |
| `HRDATA` | 32 | Input | DMA read data |
| `HWRITE` | 1 | Output | Write enable |
| `HTRANS` | 2 | Output | Transfer type (IDLE/NONSEQ/SEQ) |
| `HSIZE` | 3 | Output | Transfer size (always word) |
| `HBURST` | 3 | Output | Burst type (SINGLE or INCR4) |
| `HPROT` | 4 | Output | Protection (privileged data) |
| `HREADY` | 1 | Input | Transfer done |
| `HRESP` | 1 | Input | Transfer response |

**MII, MDIO, and Interrupt**

These signals connect directly to `eth_top` without any translation:

- **MII Transmit:** `mtx_clk_pad_i`, `mtxd_pad_o[3:0]`, `mtxen_pad_o`,
  `mtxerr_pad_o`
- **MII Receive:** `mrx_clk_pad_i`, `mrxd_pad_i[3:0]`, `mrxdv_pad_i`,
  `mrxerr_pad_i`
- **MII Common:** `mcoll_pad_i`, `mcrs_pad_i`
- **MDIO Management:** `md_pad_i`, `mdc_pad_o`, `md_pad_o`, `md_padoe_o`
- **Interrupt:** `int_o` (active-high)

---

### 2. `ahb3lite_to_wb` -- AHB Slave to WISHBONE Slave Bridge

**Source:** `src/rtl/ahb3lite_wb_bridge/ahb3lite_to_wb.v`
(git submodule from
[vfinotti/ahb3lite_wb_bridge](https://github.com/vfinotti/ahb3lite_wb_bridge))

Translates incoming AHB-Lite slave transactions into outgoing WISHBONE slave
cycles.  Used on the register-access path so that the CPU can configure the
MAC via AHB.

**Protocol mapping:**

| AHB-Lite | WISHBONE | Notes |
|---|---|---|
| `HSEL` | `wb_cyc_i` | Chip select maps to bus cycle |
| `HSEL & HTRANS` | `wb_stb_i` | Active transfer indicator |
| `HWRITE` | `wb_we_i` | Write enable |
| `HADDR` | `wb_adr` | Address (directly mapped) |
| `HWDATA` | `wb_dat_i` | Write data |
| `HRDATA` | `wb_dat_o` | Read data |
| `HREADYOUT` | `wb_ack_i` | Acknowledgement |
| `HRESP` | `wb_err_i` | Error response |

Byte selects are tied to `4'hF` (full 32-bit word access only), matching the
Ethernet MAC's register interface.  Burst transfers are not used on this path.

---

### 3. `wb_to_ahb3lite` -- WISHBONE Master to AHB Master Bridge

**Source:** `src/rtl/wb_to_ahb3lite.v`

Translates the MAC's outgoing WISHBONE B3 master DMA transactions into
AHB-Lite master transfers.  This is the more complex of the two bridges due to
burst support and the pipelined nature of AHB.

**Key behaviours:**

- **Single transfers:** WISHBONE classic cycles (CTI = `3'b000`) produce
  `HBURST = SINGLE` with a single `NONSEQ` beat.
- **4-beat incrementing bursts:** WISHBONE incrementing bursts (CTI = `3'b010`)
  produce `HBURST = INCR4` with one `NONSEQ` beat followed by three `SEQ`
  beats.
- **Pipelining:** AHB address and data phases are handled correctly; the bridge
  latches `HBURST` on the first beat and holds it stable for the duration of
  the burst.
- **Error handling:** A two-cycle `HRESP = ERROR` on the AHB side is
  translated back to `wb_err_o` on the WISHBONE side.
- **Transfer attributes:** `HPROT = 4'h3` (privileged data access),
  `HSIZE = 3'h2` (32-bit word).

---

### 4. `rmii_to_mii` -- RMII-to-MII Adapter

**Source:** `src/rtl/generic/rmii_to_mii.v`

Converts between the RMII (Reduced Media Independent Interface) and MII (Media
Independent Interface) signal conventions.  This allows the Ethernet MAC, which
natively uses 4-bit MII at 25 MHz, to work with PHYs that use the reduced
2-bit RMII at 50 MHz.

**Clock generation:**

- Divides the 50 MHz `rmii_ref_clk` by two to produce 25 MHz `mtx_clk` and
  `mrx_clk` signals for the MII side.

**Transmit path (MII to RMII):**

- Latches the 4-bit MII transmit data on the `mtx_clk` rising edge.
- Sends the low nibble (`mtxd[1:0]`) during the first 50 MHz phase and the
  high nibble (`mtxd[3:2]`) during the second phase.
- `rmii_tx_en` mirrors `mtxen` across both phases.

**Receive path (RMII to MII):**

- Collects two consecutive 2-bit RMII samples per MII clock cycle.
- Assembles a 4-bit MII nibble: `{rmii_rxd[n+1], rmii_rxd[n]}`.
- `rmii_crs_dv` is sampled in the first phase and presented as `mrxdv`.

**Collision and carrier sense:**

- `mcoll` is asserted when both `rmii_tx_en` and `rmii_crs_dv` are high
  simultaneously (half-duplex collision).
- `mcrs` mirrors `rmii_crs_dv`.

---

### 5. `ethmac_ahb_rmii` -- RMII Variant Wrapper

**Source:** `src/rtl/generic/ethmac_ahb_rmii.v`

A convenience wrapper that instantiates `ethmac_ahb` together with
`rmii_to_mii`, presenting a single module with AHB-Lite bus interfaces and an
RMII PHY interface.

```
  +----------------------------------------------------------+
  |                    ethmac_ahb_rmii                        |
  |                                                          |
  |  +----------------------------------------------------+  |
  |  |                   ethmac_ahb                        |  |
  |  |         (AHB slave, AHB master, MII)                |  |
  |  +------------------------+---------------------------+  |
  |                           | MII (internal)               |
  |                           v                              |
  |  RMII (external) <-- rmii_to_mii --> MII (internal)      |
  |  (2-bit, 50 MHz)       adapter       (4-bit, 25 MHz)    |
  +----------------------------------------------------------+
```

The RMII interface signals are:

| Signal | Width | Direction | Description |
|---|---|---|---|
| `rmii_ref_clk` | 1 | Input | 50 MHz reference clock |
| `rmii_txd` | 2 | Output | Transmit data |
| `rmii_tx_en` | 1 | Output | Transmit enable |
| `rmii_rxd` | 2 | Input | Receive data |
| `rmii_crs_dv` | 1 | Input | Carrier sense / data valid |

MDIO and interrupt signals pass through unchanged.

---

### 6. Patched OpenCores Files

**Source:** `src/rtl/ethmac_patches/`

Two files from the OpenCores release are patched for VCS (SystemVerilog)
compatibility.  The `do` port name in `eth_spram_256x32` is renamed to `do_o`
because `do` is a reserved keyword in SystemVerilog.

- `eth_spram_256x32.v` -- Port rename (`do` to `do_o`)
- `eth_wishbone.v` -- Updated instantiation to use `.do_o(ram_do)`

No functional changes are made.  See
[src/rtl/ethmac_patches/README.md](../src/rtl/ethmac_patches/README.md) for
details and RAM macro selection options.

---

## OpenCores Ethernet MAC Documentation

The Ethernet MAC IP core (`eth_top`) is an external dependency not included in
this repository.  Its documentation can be found in the `doc/` directory of the
OpenCores Ethernet MAC IP.

**For SoC Labs / University of Southampton users**, the IP is located at:

```
/research/AAA/ip_library/OpenCores-EthMAC
```

The following documents are included with the IP:

| Document | Filename | Description |
|---|---|---|
| Ethernet MAC Specification | `doc/eth_speci.pdf` | Full specification of the Ethernet MAC core including register map, buffer descriptors, and operation modes |
| Design Document | `doc/eth_design_document.pdf` | Internal design documentation describing the architecture and implementation of the MAC |
| Datasheet | `doc/ethernet_datasheet_OC_head.pdf` | Concise datasheet with key parameters and interface summary |
| Product Brief | `doc/ethernet_product_brief_OC_head.pdf` | High-level overview and feature list of the Ethernet MAC IP |

**For external users**, these documents can be obtained from the
[OpenCores ethmac project page](https://opencores.org/projects/ethmac)
(release 27).

For verification details, see the
[Verification Plan](../cocotb/VERIFICATION_PLAN.md).
