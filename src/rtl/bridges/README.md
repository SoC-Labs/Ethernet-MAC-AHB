# AHB3-Lite / Wishbone Protocol Bridges

## Original Source

These bridge modules were originally authored by **Vitor Finotti** and published
under the MIT licence at:

<https://github.com/vfinotti/ahb3lite_wb_bridge>

The design was inspired by the bridges described at:

<https://www.valpont.com/ahb-to-wishbone-and-wishbone-to-ahb-bridges-in-verilog/pst/>

The files were previously included in this repository as a git submodule. They
have been extracted into this directory for direct source management so that
local modifications can be tracked alongside the rest of the project.

## Files

| File | Direction | Description |
|---|---|---|
| `ahb3lite_to_wb.v` | AHB3-Lite slave &rarr; Wishbone master | Used on the register-access path so the CPU can configure the Ethernet MAC via AHB. |
| `wb_to_ahb3lite.v` | Wishbone master &rarr; AHB3-Lite master | Used on the DMA path so the MAC can perform bus-master transfers over AHB. |

## Changes to `ahb3lite_to_wb`

The following modifications were made to `ahb3lite_to_wb.v` by SoCLabs:

### AHB two-cycle error response (bug fix)

The original design did not implement the AHB-mandated two-cycle error response
protocol. When the Wishbone slave asserted `err`, the bridge set `HRESP = 1` but
held `HREADYOUT` low indefinitely (it was driven by `from_wb_ack_o`, which is
never asserted during an error). This stalled the AHB bus and violated the
protocol.

The fix adds an `err_resp_pending` register that implements the required
two-cycle sequence:

| Cycle | `HRESP` | `HREADYOUT` | Wishbone bus |
|---|---|---|---|
| 1 (error detected) | 1 | 0 | `cyc`/`stb` deasserted |
| 2 (error complete) | 1 | 1 | idle |

### Read-data latching

A `rdata_latch` register was added so that `HRDATA` remains stable after the
Wishbone `ack` is deasserted, preventing the AHB master from sampling stale or
undefined data.

## Changes to `wb_to_ahb3lite`

No functional changes have been made to `wb_to_ahb3lite.v`. It was extracted
from the submodule without modification.
