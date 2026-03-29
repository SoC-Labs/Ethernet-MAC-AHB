// HAL rule configuration for Ethernet MAC AHB bridge lint flow
//
// Waive rules that conflict with AHB/AMBA/Wishbone naming conventions or are
// style-only and not relevant to design correctness.

// ── Naming convention waivers ─────────────────────────────────────
// AHB signal names (hclk, hresetn, hsel, htrans, etc.) and Wishbone
// signal names (wb_cyc, wb_stb, etc.) are defined by their respective
// specs and cannot follow HAL's default suffixes.
-nocheck INPTNM
-nocheck OUTPNM
-nocheck CLKSNM
-nocheck RSTNAM
-nocheck MODLNM
-nocheck RGOPNM
-nocheck IDLENG
// Uppercase variable names — AHB signals use mixed case (sHADDR, mHTRANS)
-nocheck LCVARN

// ── Style waivers ─────────────────────────────────────────────────
// Numeric literals in port widths (e.g. [31:0]) are standard practice
-nocheck STYVAL
// Line length — 120 chars is acceptable for modern editors
-nocheck MAXLEN
// Per-port and per-signal comments are overkill for clear code
-nocheck COMIOP
-nocheck COMDEC
-nocheck COMEND
// Always-block comments — not required for well-structured code
-nocheck COMBLK
// Parameter base/width — defaults are fine for simple integer params
-nocheck PRMVAL
-nocheck PRMBSE
// Compiler directives (`ifdef/`endif) — used for ETH_WISHBONE_B3 etc.
-nocheck CDWARN
-nocheck COMDIR
// Block labels — meaningful code structure over mandatory labelling
-nocheck NOBLKN
// Missing begin/end in single-statement if/always — acceptable style
-nocheck NBGEND
// Empty default case statements — intentional no-op for completeness
-nocheck EMPSTM
// Numeric suffix in identifiers — by design
-nocheck NUMSUF
// Separate line for each signal declaration — acceptable grouping
-nocheck SEPLIN

// ── Structural waivers ───────────────────────────────────────────
// Tied outputs are by design:
//   - mHREADYOUT=1 (bridge never inserts wait states)
//   - mHSIZE=3'b010, mHPROT=4'b0011 (fixed AHB transfer parameters)
//   - sHREADYOUT tied to ack (zero-wait-state AHB slave)
-nocheck TIELOG
// Feedthrough paths are intentional:
//   - from_m_wb_dat_o→mHWDATA, mHRDATA→to_m_wb_dat_i (data pass-through)
//   - sHWDATA→to_wb_dat_i, from_wb_dat_o→sHRDATA (AHB-to-WB data path)
-nocheck FDTHRU
// Mixed sync/async is expected with async active-low reset (rst_n_i/hresetn)
-nocheck SYNASN
// Combinational paths crossing hierarchy — expected in a hierarchical
// design where bridges connect combinational outputs to registered logic
-nocheck CBPAHI
// Combinational outputs at top level — AHB/WB protocols are comb by design
-nocheck TPOUNR
// Combinational (async) output ports — same reason
-nocheck SYNPRT
// Large operand arithmetic — inherent to address calculation
-nocheck LRGOPR
// Potential overflow — intentional wrapping for burst beat counters
-nocheck POIASG
// Multiple non-blocking assigns — set/clear pattern
-nocheck MULNBA
// Parameters in port expressions
-nocheck PRMEXP
-nocheck IPRTEX
// FSM modelling style — HAL expects specific patterns, ours is valid
-nocheck BADFSM
-nocheck EXTFSM
-nocheck TRNMBT
-nocheck STMCNM
// Typedef not in package — module-local typedefs are acceptable
-nocheck TDOPKG
// Lowercase type names
-nocheck UCCONN
// Clock/reset renamed across hierarchy (clk_i→hclk, rst_n_i→hresetn)
-nocheck DIFCLK
-nocheck DIFRST
// Aliased wires — bridge pass-through by design
-nocheck DALIAS
// FF with constant data — acceptable for control logic
-nocheck FFCSTD
// FF without synchronous reset — async reset is sufficient
-nocheck FFWNSR
// Mixed driver types
-nocheck DFDRVS
// Unused port bits — WB sel/bte unused in wb_to_ahb3lite (word-only transfers),
// AHB htrans[0] etc. Protocol-inherent unused bits.
-nocheck USEPRT
// Unconnected output naming — mHREADYOUT not connected at top level by design
-nocheck UCOPNM
// Unconnected output ports
-nocheck UNCONO
// Unread local registers
-nocheck URDREG
// Glue logic at top level — expected for address/clock wiring
-nocheck ATLGLC
// Combinational always-block outputs read via continuous assign — standard
// Verilog pattern for separating comb logic from output wiring
-nocheck REVROP
// Combinational input-to-output paths — bridges are pass-through by design
-nocheck IOCOMB
// Extraneous logic in FSM sequential block — address/burst latching is
// intentionally co-located with the state register for clarity
-nocheck EXTSEQ
// Clock signal drives data pin — inherent to RMII clock-divider design
// where phase counters are derived from the reference clock
-nocheck CDFDAT
// Clock does not drive data for some FFs — mrxerr is only reset, never
// toggled by data in the current design (RMII error not yet wired)
-nocheck CLKNED
// Empty begin/end block — third-party bridge (ahb3lite_to_wb submodule)
-nocheck EMPBLK
// Control character in source — third-party bridge
-nocheck CTLCHR
// Constant left-padded — width mismatch in third-party bridge
-nocheck PADMSB
// Old-style always blocks — Verilog-2001 style used in third-party bridges
-nocheck OLDALW
// Logic operators on multi-bit operands
-nocheck LOGNEG
-nocheck LOGAND
// Bit-width mismatches — third-party IP style
-nocheck BOUINC
// Memory naming
-nocheck MEMRNM
// Micro-architectural warnings
-nocheck MICAWS
// Black-boxed signal warnings
-nocheck BBXSIG
