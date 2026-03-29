//-----------------------------------------------------------------------------
// SoCLabs Ethernet MAC SRAM Wrapper (FPGA variant)
// - Wraps cmsdk_fpga_sram with an ethmac-owned module name so the SRAM
//   implementation can be substituted for ASIC flows by replacing this
//   single file in the filelist.
//
// For ASIC: replace this file with the ASIC variant via flist/ethmac_ahb_asic.flist.
// The interface is identical - only the internal implementation changes.
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

    cmsdk_fpga_sram #(
        .AW (AW)
    ) u_sram (
        .CLK   (CLK),
        .ADDR  (ADDR),
        .WDATA (WDATA),
        .WREN  (WREN),
        .CS    (CS),
        .RDATA (RDATA)
    );

endmodule
