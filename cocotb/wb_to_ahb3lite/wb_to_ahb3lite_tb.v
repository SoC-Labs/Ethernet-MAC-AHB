//-----------------------------------------------------------------------------
// wb_to_ahb3lite_tb.v
//-----------------------------------------------------------------------------
// Cocotb testbench wrapper for wb_to_ahb3lite bridge.
// Exposes signals with naming conventions expected by cocotbext-wishbone
// (WishboneMaster) and cocotbext-ahb (AHBLiteSlaveRAM).
//-----------------------------------------------------------------------------

`timescale 1ns/1ps

module wb_to_ahb3lite_tb (
  input  wire        hclk,
  input  wire        hresetn,

  // WB Master signals (driven by cocotbext-wishbone WishboneMaster)
  input  wire [31:0] wb_adr,
  input  wire  [3:0] wb_sel,
  input  wire        wb_we,
  input  wire [31:0] wb_datwr,
  input  wire        wb_cyc,
  input  wire        wb_stb,
  output wire        wb_ack,
  output wire        wb_err,
  output wire [31:0] wb_datrd,
  input  wire  [2:0] wb_cti,
  input  wire  [1:0] wb_bte,

  // AHB Master signals (responded to by cocotbext-ahb AHBLiteSlaveRAM)
  output wire        hsel,
  output wire [31:0] haddr,
  output wire  [1:0] htrans,
  output wire  [2:0] hsize,
  output wire  [2:0] hburst,
  output wire  [3:0] hprot,
  output wire        hwrite,
  output wire [31:0] hwdata,
  input  wire [31:0] hrdata,
  input  wire        hready,
  input  wire        hresp
);

  wire hreadyout;

  wb_to_ahb3lite u_dut (
    .clk_i              (hclk),
    .rst_n_i            (hresetn),

    // WB master side
    .from_m_wb_adr_o    (wb_adr),
    .from_m_wb_sel_o    (wb_sel),
    .from_m_wb_we_o     (wb_we),
    .from_m_wb_dat_o    (wb_datwr),
    .from_m_wb_cyc_o    (wb_cyc),
    .from_m_wb_stb_o    (wb_stb),
    .to_m_wb_ack_i      (wb_ack),
    .to_m_wb_err_i      (wb_err),
    .to_m_wb_dat_i      (wb_datrd),
    .from_m_wb_cti_o    (wb_cti),
    .from_m_wb_bte_o    (wb_bte),

    // AHB master side
    .mHSEL              (hsel),
    .mHSIZE             (hsize),
    .mHRDATA            (hrdata),
    .mHRESP             (hresp),
    .mHREADY            (hready),
    .mHREADYOUT         (hreadyout),
    .mHWRITE            (hwrite),
    .mHBURST            (hburst),
    .mHADDR             (haddr),
    .mHTRANS            (htrans),
    .mHWDATA            (hwdata),
    .mHPROT             (hprot)
  );

  // VCD dump for waveform debugging
  initial begin
    $dumpfile("wb_to_ahb3lite_tb.vcd");
    $dumpvars(0, wb_to_ahb3lite_tb);
  end

endmodule
