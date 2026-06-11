# OpenCores HA1588 Patched Files

These files are patched copies of source files from the OpenCores HA1588
PTP timestamping IP (Copyright (c) 2012, BABY&HW, LGPL v2.1).

Baseline: the vendored snapshot at `$HA1588_IP_DIR`
(`/research/AAA/ip_library/OpenCores-HA1588`). The upstream project ships no
version tag; the vendored tree is the reference. To see exactly what changed:

```sh
for f in ha1588:top ptp_parser:tsu ptp_queue:tsu reg:reg rtc:rtc tsu:tsu; do
  n=${f%%:*}; d=${f##*:}
  diff -u "$HA1588_IP_DIR/rtl/$d/$n.v" "$n.v"
done
```

## Why patched copies exist at all

`$HA1588_IP_DIR` is read-only, lab-shared IP collateral. All fixes are made
as full-file local overrides here, selected by the filelists in `flist/`
(`ha1588_ahb.flist`, `ha1588_apb.flist`, `ethmac_subsystem_apb*.flist`).
Every ha1588 RTL file used by this project comes from this directory except
`rtl/bus/wishbone/wb_slv_wrapper.v`, which is used unmodified from upstream.

## What changed, per file

| File | Upstream defect | Fix |
|---|---|---|
| `rtc.v` | Reset branch contains literal self-assignments (`period_fix <= period_fix;` — the zero-assignments are commented out), so both registers retain X forever. | Reset `period_fix` / `time_adj` to `40'd0`. |
| `reg.v` | Register file (`rgs`) has no resets at all: X-state in simulation, undefined power-on state in silicon. | Synchronous reset added to all register blocks, CDC synchronizer flops, and edge-detector pipeline regs. |
| `ha1588.v` | The RTC had no system-reset path (only the software `rtc_rst` register bit) and queue/RTC resets OR-ed combinationally into async-reset pins (lint GLTASR). | 2-FF async-assert / sync-deassert reset bridge into `rtc_clk`; glitch-free registered reset combines for the RTC and both packet queues. |
| `ptp_parser.v` | All flops are clocked by the gmii/MII clock but async-reset deasserted in the sys-clock domain — reset-domain-crossing recovery/removal violation (SpyGlass `Ac_unsync02`). | Standard reset-deassertion bridge (`rst_g`) into the `clk` domain feeding all sequential logic. |
| `ptp_queue.v` | Empty shell requiring vendor FIFO IP (Altera `dcfifo` / Xilinx) under `ifdef`s — unsynthesizable in this flow. | Full rewrite: generic gray-code dual-clock FIFO, identical ports (128-bit x 16). |
| `tsu.v` | RMII gearbox nibble-pairing phase is set by when `gmii_ctrl` first rises, not by frame content, so a one-nibble offset splits the SFD byte and RX frames are never timestamped (the silicon t2=0 PTP failure). | Nibble-level SFD anchor: one-nibble data skid + SFD-anchored `int_sop` re-issue, keeping the byte-emit grid untouched. Plus reset hygiene matching the other files. |

See the header comment in each file for the full analysis (the `tsu.v` and
`ptp_parser.v` headers carry detailed root-cause write-ups).

## Ground rules for future edits

- Never modify files under `$HA1588_IP_DIR` — copy the file here, fix it,
  repoint the flists, and document the change in this README.
- Keep diffs vs. upstream as small as the fix allows (`ptp_queue.v` is the
  one sanctioned rewrite, because there was no portable upstream
  implementation to patch).
- Do not commit work-in-progress copies (`*.wip`, `*.bak`) to this directory.
