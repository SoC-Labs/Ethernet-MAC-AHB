//-----------------------------------------------------------------------------
// SoCLabs Ethernet MAC SRAM Wrapper (ASIC variant)
// - Instantiates the rf_08k compiled register file macro (TSMC 65nm).
// - The rf_08k is a 2048x32 macro; only 256 words are used by the
//   ethernet MAC buffer descriptors. Upper address bits are tied to 0.
// - Maps the ethmac_sram interface to the rf_08k port convention:
//     * Active-low CEN  (chip enable)  <- inverted from active-high CS
//     * Active-low WEN  (per-bit)      <- expanded & inverted from WREN byte enables
//     * Active-low GWEN (global write) <- low when any write is active
//     * EMA/EMAW/RET1N  tied to default (normal operation, no retention)
//
// For ASIC: swap this file into the filelist via flist/ethmac_ahb_asic.flist.
// The interface is identical to the FPGA and generic variants - only the
// internal implementation changes.
//
// A joint work commissioned on behalf of SoC Labs, under Arm Academic Access license.
//
// Contributors
//
// David Mapstone (d.a.mapstone@soton.ac.uk)
//
// Copyright 2026, SoC Labs (www.soclabs.org)
//-----------------------------------------------------------------------------

module ethmac_sram #(
    parameter AW = 10
)(
    input  wire          CLK,
    input  wire [AW-1:2] ADDR,
    input  wire [31:0]   WDATA,
    input  wire [3:0]    WREN,
    input  wire          CS,
    output wire [31:0]   RDATA
);

    // ── Interface adaptation ─────────────────────────────────────────────

    // Chip enable: rf_08k CEN is active-low
    wire cen = ~CS;

    // Global write enable: active-low, asserted when any byte lane writes
    wire gwen = ~(|WREN);

    // Per-bit write enables: expand 4-bit byte enables to 32-bit, then invert
    // (rf_08k WEN is active-low, per-bit granularity)
    wire [31:0] wen = ~{{8{WREN[3]}}, {8{WREN[2]}}, {8{WREN[1]}}, {8{WREN[0]}}};

    // ── rf_08k macro instantiation ───────────────────────────────────────
    // rf_08k is 2048x32 (11-bit address). Pad the 8-bit word address from
    // eth_spram_256x32 with leading zeros to fill the upper address bits.

    rf_08k u_rf (
        .CLK   (CLK),
        .CEN   (cen),
        .A     ({3'b000, ADDR[AW-1:2]}),  // 11-bit address, upper 3 bits tied low
        .D     (WDATA),
        .GWEN  (gwen),
        .WEN   (wen),
        .Q     (RDATA),
        .EMA   (3'b000),
        .EMAW  (2'b00),
        .RET1N (1'b1)
    );

endmodule
