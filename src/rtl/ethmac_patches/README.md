# OpenCores ethmac Patched Files

These two files are patched copies of source files from the OpenCores Ethernet
MAC IP (`ethmac/tags/rel_27/rtl/verilog/`).

## What changed

1. The port name `do` in `eth_spram_256x32.v` was renamed to `do_o`, and the
   corresponding instantiation in `eth_wishbone.v` was updated to match.

   ```
   eth_spram_256x32.v:  output [31:0] do;    -->  output [31:0] do_o;
   eth_wishbone.v:      .do(ram_do)          -->  .do_o(ram_do)
   ```

2. `eth_spram_256x32.v` was refactored to instantiate a swappable
   `ethmac_sram` wrapper module instead of containing `ifdef`-selected RAM
   implementations inline. The BIST ports were also removed. The SRAM
   implementation is now selected by choosing the appropriate filelist:

   | Filelist variant | SRAM file included | Implementation |
   |---|---|---|
   | `ethmac_ahb.flist` (default) | `fpga/ethmac_sram.v` | Wraps `cmsdk_fpga_sram` |
   | `ethmac_ahb_generic.flist` | `generic/ethmac_sram.v` | Register-based for simulation |
   | `ethmac_ahb_asic.flist` | `asic/ethmac_sram.v` | Compiled SRAM macro (`rf_sp_256x32`) |

3. `eth_wishbone.v` BIST `ifdef` removed from the `bd_ram` instantiation to
   match the simplified `eth_spram_256x32` interface.

No other changes were made. All remaining ethmac source files are used
unmodified from the external `$ETHMAC_IP_DIR`.

## Why

- `do` is a reserved keyword in SystemVerilog (used for `do...while` loops).
  VCS compiles with `-sverilog` enabled (required by cocotb) and rejects `do`
  as a port/signal identifier. Renaming to `do_o` resolves the clash.
- The swappable SRAM wrapper follows the same pattern used by TideLink,
  allowing clean substitution between generic/FPGA/ASIC implementations
  via filelists rather than compile-time `ifdef` defines.

## How they are used

The filelists in `flist/` source most ethmac RTL from `$ETHMAC_IP_DIR` but
override `eth_spram_256x32.v` and `eth_wishbone.v` with these patched copies,
and include the appropriate `ethmac_sram` variant:

- `flist/ethmac_ahb.flist` — FPGA (default, includes `cmsdk_fpga_sram`)
- `flist/ethmac_ahb_generic.flist` — Simulation (register-based)
- `flist/ethmac_ahb_asic.flist` — ASIC (compiled SRAM macro)

## SRAM wrapper architecture

```
eth_wishbone
  └── eth_spram_256x32  (patched, thin wrapper)
        └── ethmac_sram  (swapped via filelist)
              ├── generic/ethmac_sram.v  — reg-based storage
              ├── fpga/ethmac_sram.v     — wraps cmsdk_fpga_sram
              └── asic/ethmac_sram.v     — compiled SRAM macro
```

The `ethmac_sram` module has an identical interface across all three variants:

```verilog
module ethmac_sram #(parameter AW = 10) (
    input  wire          CLK,
    input  wire [AW-1:2] ADDR,
    input  wire [31:0]   WDATA,
    input  wire [3:0]    WREN,
    input  wire          CS,
    output wire [31:0]   RDATA
);
```

For the ASIC variant, the macro name `rf_sp_256x32` should be updated to
match the actual compiled memory available in your target technology library.
