# OpenCores ethmac Patched Files

These two files are patched copies of source files from the OpenCores Ethernet
MAC IP (`ethmac/tags/rel_27/rtl/verilog/`).

## What changed

The port name `do` in `eth_spram_256x32.v` was renamed to `do_o`, and the
corresponding instantiation in `eth_wishbone.v` was updated to match.

```
eth_spram_256x32.v:  output [31:0] do;    -->  output [31:0] do_o;
eth_wishbone.v:      .do(ram_do)          -->  .do_o(ram_do)
```

No other changes were made. All remaining ethmac source files are used
unmodified from the external `$ETHMAC_IP_DIR`.

## Why

`do` is a reserved keyword in SystemVerilog (used for `do...while` loops).
VCS compiles with `-sverilog` enabled (required by cocotb) and rejects `do`
as a port/signal identifier. Renaming to `do_o` resolves the clash.

## How they are used

The cocotb Makefiles source most ethmac RTL from `$ETHMAC_IP_DIR` but override
`eth_spram_256x32.v` and `eth_wishbone.v` with these patched copies:

```makefile
ETHMAC_RTL     = $(ETHMAC_IP_DIR)/rtl/verilog   # unmodified sources
ETHMAC_PATCHES = $(PWD)/../../src/rtl/ethmac_patches  # these 2 files

VERILOG_SOURCES += $(ETHMAC_RTL)/eth_top.v       # from external repo
VERILOG_SOURCES += $(ETHMAC_RTL)/eth_fifo.v      # from external repo
# ... all other unmodified files ...
VERILOG_SOURCES += $(ETHMAC_PATCHES)/eth_spram_256x32.v  # patched
VERILOG_SOURCES += $(ETHMAC_PATCHES)/eth_wishbone.v      # patched
```

## RAM selection and substitution

`eth_spram_256x32` is the buffer descriptor SRAM used by the Ethernet MAC.
The original source contains four implementations selected by compile-time
defines.  `eth_fifo.v` similarly selects between a generic FIFO and a Xilinx
distributed RAM.

All defines are controlled in `eth_defines.v` (sourced from `$ETHMAC_IP_DIR`
via `+incdir+`).  By default every define is **commented out**, which selects
the **generic behavioural RAM** — a plain `reg`-based model suitable for
simulation.

### Available RAM options

| Define | Affects | Implementation |
|---|---|---|
| *(none, default)* | BD SPRAM + FIFOs | Generic `reg`-array RAM — **use for simulation** |
| `ETH_XILINX_RAMB4` | BD SPRAM | Xilinx RAMB4 block RAM primitives |
| `ETH_VIRTUAL_SILICON_RAM` | BD SPRAM | Virtual Silicon ASIC RAM |
| `ETH_ARTISAN_RAM` | BD SPRAM | Artisan ASIC RAM |
| `ETH_FIFO_XILINX` | TX/RX FIFOs | Xilinx distributed RAM (`xilinx_dist_ram_16x32`) |
| `ETH_BIST` | BD SPRAM | Adds MBIST scan chain ports (combine with a RAM define above) |

### How to select a RAM for synthesis or FPGA

Pass the define through the Makefile's `COMPILE_ARGS`:

```makefile
# Example: target Xilinx FPGA
COMPILE_ARGS += +define+ETH_XILINX_RAMB4
COMPILE_ARGS += +define+ETH_FIFO_XILINX
```

Or for ASIC flows, uncomment the relevant line in `eth_defines.v` in your
local `$ETHMAC_IP_DIR` checkout.

### Important notes

- Only **one** BD SPRAM define should be active at a time.  If none is set,
  the generic `reg`-based RAM is used (the final `else` branch).
- The `do` → `do_o` rename in this patched copy applies to **all** RAM
  variants (Xilinx, VS, Artisan, and generic).  The patched file is a
  drop-in replacement regardless of which define is active.
- For simulation / cocotb tests, leave all RAM defines unset (the default).
  The generic RAM is fully functional and does not require external models.
