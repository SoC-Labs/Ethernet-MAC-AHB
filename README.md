# Ethernet MAC AHB

A wrapper for the OpenCores Ethernet MAC (`eth_top`) with AMBA bus interfaces, replacing the original WISHBONE interfaces. The wrapper provides an APB slave interface for register access and an AHB master interface for DMA transfers, making the Ethernet MAC suitable for integration into ARM-based SoC designs.

A joint work commissioned on behalf of SoC Labs, under Arm Academic Access license.

## Architecture

```
                        ethmac_ahb
  ┌──────────────────────────────────────────────────────────┐
  │                                                          │
  │  APB Slave ──► APB-to-WB ──► eth_top (register port)    │
  │  (register       bridge       (OpenCores Ethernet MAC)   │
  │   access)                          │                     │
  │                                    │ DMA                 │
  │                                    ▼                     │
  │  AHB Master ◄── WB-to-AHB ◄── eth_top (master port)     │
  │  (DMA              bridge                                │
  │   transfers)                                             │
  │                                                          │
  │  MII ◄──────────────────────► eth_top (PHY interface)    │
  │  (TX/RX/MDIO)                                            │
  │                                                          │
  │  int_o ◄───────────────────── eth_top (interrupt)        │
  │                                                          │
  └──────────────────────────────────────────────────────────┘
```

### Bus Interface Mapping

| Original (WISHBONE) | Replaced by | Purpose |
|----------------------|-------------|---------|
| WISHBONE slave | APB slave (`PSEL`, `PENABLE`, `PWRITE`, `PADDR`, `PWDATA`, `PRDATA`) | CPU register access (MAC configuration, status, MII management) |
| WISHBONE master | AHB master (`HADDR`, `HTRANS`, `HSIZE`, `HWDATA`, `HRDATA`) | DMA transfers between MAC and system memory |

### External Interfaces

| Interface | Signals | Description |
|-----------|---------|-------------|
| MII Transmit | `mtx_clk_pad_i`, `mtxd_pad_o[3:0]`, `mtxen_pad_o`, `mtxerr_pad_o` | Media Independent Interface transmit path to PHY |
| MII Receive | `mrx_clk_pad_i`, `mrxd_pad_i[3:0]`, `mrxdv_pad_i`, `mrxerr_pad_i` | Media Independent Interface receive path from PHY |
| MII Common | `mcoll_pad_i`, `mcrs_pad_i` | Collision detect and carrier sense |
| MII Management | `md_pad_i`, `mdc_pad_o`, `md_pad_o`, `md_padoe_o` | MDIO interface for PHY register access |
| Interrupt | `int_o` | Active-high interrupt output |

### Bridge Logic

The wrapper contains two protocol bridges:

- **APB-to-WISHBONE slave bridge**: Translates APB transactions into WISHBONE slave cycles for register access. `PSEL` maps to `wb_cyc_i`, `PSEL & PENABLE` maps to `wb_stb_i`, and byte selects are tied to `4'hF` (full 32-bit access).

- **WISHBONE master-to-AHB bridge**: Translates outgoing WISHBONE master DMA transactions into AHB master transfers. Currently uses single-beat transfers (`HTRANS=IDLE`, `HBURST=SINGLE`, `HSIZE=WORD`). This bridge is marked as a TODO for full implementation with proper AHB handshaking and burst support.

## Repository Structure

```
ethernet-mac-ahb/
├── src/
│   ├── rtl/                          # Synthesisable RTL
│   │   ├── generic/ethmac_ahb.v      # Top-level wrapper (APB/AHB + eth_top)
│   │   ├── asic/                     # ASIC-specific implementations
│   │   └── fpga/                     # FPGA-specific implementations
│   └── rdl/                          # Register Description Language definitions
├── python/                           # Python package (drivers, models)
│   └── ethernet_mac/
├── cocotb/                           # CocoTB simulation verification
├── flist/                            # File lists (simulation/synthesis)
├── formal/                           # Formal verification
├── lint/                             # RTL linting / static analysis
├── syn/                              # Synthesis flows
│   └── asic/
│       ├── design-compiler/
│       └── rtl-architect/
├── pynq/                             # PYNQ hardware test scripts
├── ci/                               # CI/CD automation
└── docs/                             # Documentation
```

## Dependencies

- **OpenCores Ethernet MAC** -- `eth_top` core (10/100 Mbps Ethernet MAC with MII interface).
- **CMSDK** -- ARM Cortex-M System Design Kit (for AHB/APB infrastructure components).

## Current Status

The wrapper is in early development. The APB-to-WISHBONE slave bridge has a basic implementation. The WISHBONE master-to-AHB bridge requires full implementation with proper AHB state machine, handshaking, and burst transfer support (see `TODO` markers in the RTL).

## Contributors

- David Mapstone (d.a.mapstone@soton.ac.uk)

## License

Copyright 2026, SoC Labs (www.soclabs.org). Released under Arm Academic Access license.
