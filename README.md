# Ethernet MAC AHB

A wrapper for the OpenCores Ethernet MAC (`eth_top`) with AHB-Lite bus
interfaces, replacing the original WISHBONE interfaces.  The wrapper provides
an AHB-Lite slave interface for register access and an AHB-Lite master
interface for DMA transfers, making the Ethernet MAC suitable for integration
into ARM-based SoC designs.

An RMII variant (`ethmac_ahb_rmii`) is also provided, adding an RMII-to-MII
adapter for PHYs that use the reduced pin-count interface.

A joint work commissioned on behalf of SoC Labs, under Arm Academic Access
license.

## Prerequisites

### OpenCores Ethernet MAC IP

The wrapper depends on the OpenCores Ethernet MAC core (`eth_top`), which is
**not included** in this repository and must be obtained separately.

**For SoC Labs / University of Southampton users:**

The IP is available at:

```
/research/AAA/ip_library/OpenCores-EthMAC
```

**For external users:**

Download release 27 from the OpenCores project:

```
https://opencores.org/projects/ethmac
```

Place the contents so that `rtl/verilog/eth_top.v` is reachable from the
root of your copy (the same layout as the OpenCores release tarball).

### AHB3-Lite to WISHBONE Bridge

Included as a git submodule from
[vfinotti/ahb3lite_wb_bridge](https://github.com/vfinotti/ahb3lite_wb_bridge).
It is pulled automatically during the clone step below.

### Verification tools (for running tests)

| Tool | Purpose |
|---|---|
| VCS (Synopsys) | Verilog simulator (default, set `SIM=` in Makefile for alternatives) |
| Python 3 | Test runner |
| cocotb >= 1.6 | Verification framework |
| cocotbext-ahb >= 0.4 | AHB bus functional models |
| cocotbext-eth >= 0.1 | MII PHY model (needed for data-path tests only) |

Install the Python packages:

```bash
pip install cocotb cocotbext-ahb cocotbext-eth
```

## Getting Started

### 1. Clone the repository

```bash
git clone --recursive git@git.soton.ac.uk:soclabs/ethernet-mac-ahb.git
cd ethernet-mac-ahb
```

If you have already cloned without `--recursive`, pull the submodule
separately:

```bash
git submodule update --init --recursive
```

### 2. Set the environment

Edit `set_env.sh` if your Ethernet MAC IP is in a non-default location, then
source it:

```bash
source set_env.sh
```

This exports `ETHMAC_IP_DIR`, which the cocotb Makefiles use to locate the
ethmac RTL.

### 3. Run the verification tests

```bash
cd cocotb
./run_all.sh            # run all test suites
./run_all.sh rmii_to_mii   # run a single suite
```

Or run an individual suite directly:

```bash
cd cocotb/ahb3lite_to_wb
make
```

To run a single test case:

```bash
make TESTCASE=test_single_word_write
```

## Architecture

```
                        ethmac_ahb
  ┌──────────────────────────────────────────────────────────┐
  │                                                          │
  │  AHB Slave ──► AHB-to-WB ──► eth_top (register port)    │
  │  (register      bridge        (OpenCores Ethernet MAC)   │
  │   access)    (ahb3lite_to_wb)      │                     │
  │                                    │ DMA                 │
  │                                    ▼                     │
  │  AHB Master ◄── WB-to-AHB ◄── eth_top (master port)     │
  │  (DMA            bridge                                  │
  │   transfers)  (wb_to_ahb3lite)                           │
  │                                                          │
  │  MII ◄──────────────────────► eth_top (PHY interface)    │
  │  (TX/RX/MDIO)                                            │
  │                                                          │
  │  int_o ◄───────────────────── eth_top (interrupt)        │
  │                                                          │
  └──────────────────────────────────────────────────────────┘

                    ethmac_ahb_rmii (optional)
  ┌──────────────────────────────────────────────────────────┐
  │                                                          │
  │  ┌────────────────────────────────────────────────────┐  │
  │  │                   ethmac_ahb                       │  │
  │  │            (as shown above)                        │  │
  │  └────────────────┬───────────────────────────────────┘  │
  │                   │ MII                                  │
  │                   ▼                                      │
  │  RMII ◄──── rmii_to_mii ────► MII                       │
  │  (2-bit       adapter          (4-bit, 25 MHz)           │
  │   50 MHz)                                                │
  │                                                          │
  └──────────────────────────────────────────────────────────┘
```

### Bus Interface Mapping

| Original (WISHBONE) | Replaced by | Purpose |
|---|---|---|
| WISHBONE slave | AHB-Lite slave (`HSEL`, `HTRANS`, `HWRITE`, `HADDR`, `HWDATA`, `HRDATA`) | CPU register access (MAC configuration, status, MII management) |
| WISHBONE master | AHB-Lite master (`HADDR`, `HTRANS`, `HSIZE`, `HWDATA`, `HRDATA`) | DMA transfers between MAC and system memory |

### External Interfaces

| Interface | Signals | Description |
|---|---|---|
| MII Transmit | `mtx_clk_pad_i`, `mtxd_pad_o[3:0]`, `mtxen_pad_o`, `mtxerr_pad_o` | Transmit path to PHY |
| MII Receive | `mrx_clk_pad_i`, `mrxd_pad_i[3:0]`, `mrxdv_pad_i`, `mrxerr_pad_i` | Receive path from PHY |
| MII Common | `mcoll_pad_i`, `mcrs_pad_i` | Collision detect and carrier sense |
| MII Management | `md_pad_i`, `mdc_pad_o`, `md_pad_o`, `md_padoe_o` | MDIO interface for PHY register access |
| Interrupt | `int_o` | Active-high interrupt output |

### Bridge Logic

The wrapper contains two protocol bridges from the
[ahb3lite_wb_bridge](https://github.com/vfinotti/ahb3lite_wb_bridge) IP:

- **`ahb3lite_to_wb`** -- Translates AHB-Lite slave transactions into
  WISHBONE slave cycles for register access.  `HSEL` maps to `wb_cyc_i`,
  `HSEL & HTRANS` maps to `wb_stb_i`, and byte selects are tied to `4'hF`
  (full 32-bit access).

- **`wb_to_ahb3lite`** -- Translates outgoing WISHBONE master DMA
  transactions (with WISHBONE B3 CTI/BTE burst extensions) into AHB-Lite
  master transfers.

## Repository Structure

```
ethernet-mac-ahb/
├── src/
│   ├── rtl/
│   │   ├── generic/
│   │   │   ├── ethmac_ahb.v            # Top-level AHB wrapper
│   │   │   ├── ethmac_ahb_rmii.v       # RMII variant
│   │   │   └── rmii_to_mii.v           # RMII-to-MII adapter
│   │   ├── ahb3lite_wb_bridge/          # Git submodule (AHB↔WB bridges)
│   │   ├── ethmac_patches/             # Patched ethmac files for VCS compat
│   │   ├── asic/                        # ASIC-specific implementations
│   │   └── fpga/                        # FPGA-specific implementations
│   └── rdl/                             # Register Description Language
├── cocotb/                              # Cocotb verification
│   ├── run_all.sh                       # Run all test suites
│   ├── requirements.txt                 # Python dependencies
│   ├── ahb3lite_to_wb/                  # AHB→WB bridge unit tests
│   ├── wb_to_ahb3lite/                  # WB→AHB bridge unit tests
│   ├── rmii_to_mii/                     # RMII adapter unit tests
│   ├── ethmac_ahb/                      # Integrated wrapper tests
│   └── VERIFICATION_PLAN.md             # Test plan and feature matrix
├── python/ethernet_mac/                 # Python drivers / models
├── flist/                               # File lists (sim / synthesis)
├── formal/                              # Formal verification
├── lint/                                # RTL linting / static analysis
├── syn/asic/                            # Synthesis flows
├── pynq/                                # PYNQ hardware test scripts
├── ci/                                  # CI/CD automation
├── docs/                                # Documentation
├── set_env.sh                           # Environment setup
└── .gitlab-ci.yml                       # GitLab CI pipeline
```

## Verification

The cocotb test suites are organised in layers matching the design hierarchy.
See [cocotb/VERIFICATION_PLAN.md](cocotb/VERIFICATION_PLAN.md) for the full
feature matrix.

| Suite | Module under test | Tests |
|---|---|---|
| `ahb3lite_to_wb` | AHB→WB bridge | 7 (single R/W, back-to-back, wait states, errors, reset) |
| `wb_to_ahb3lite` | WB→AHB bridge | 6 (single R/W, back-to-back, wait states, errors, reset) |
| `rmii_to_mii` | RMII adapter | 7 (clock division, nibble serialisation, CRS, collision, reset) |
| `ethmac_ahb` | Integrated wrapper | 21 (register defaults, write/readback, DMA TX, interrupts, reset) |

### Patched ethmac files

Two files from the OpenCores ethmac IP are patched for VCS compatibility: the
`do` port name in `eth_spram_256x32` is renamed to `do_o` to avoid a clash
with the SystemVerilog `do` keyword.  These patched copies live in
`src/rtl/ethmac_patches/` and are used instead of the originals during
simulation.  See
[src/rtl/ethmac_patches/README.md](src/rtl/ethmac_patches/README.md) for
details including RAM selection options.

## CI Pipeline

The GitLab CI pipeline (`.gitlab-ci.yml`) runs all four cocotb test suites on
every push.  The three bridge/adapter suites must pass; the integrated wrapper
suite is allowed to fail while known issues are resolved.  Test results are
published as JUnit artifacts.

## Contributors

- David Mapstone (d.a.mapstone@soton.ac.uk)

## License

Copyright 2025, SoC Labs (www.soclabs.org). Released under Arm Academic Access license.
