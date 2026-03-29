//-----------------------------------------------------------------------------
// ahb3lite_to_wb_tb.v
//-----------------------------------------------------------------------------
// Cocotb testbench wrapper for ahb3lite_to_wb bridge.
// Exposes signals with naming conventions expected by cocotbext-ahb
// (AHBLiteMaster) and cocotbext-wishbone (WishboneSlave).
//-----------------------------------------------------------------------------

`timescale 1ns/1ps

module ahb3lite_to_wb_tb (
  input  wire        hclk,
  input  wire        hresetn,

  // AHB Slave signals (driven by cocotbext-ahb AHBLiteMaster)
  input  wire [31:0] haddr,
  input  wire [31:0] hwdata,
  input  wire        hwrite,
  input  wire  [2:0] hsize,
  input  wire  [2:0] hburst,
  input  wire        hsel,
  input  wire  [1:0] htrans,
  input  wire        hready,
  input  wire  [3:0] hprot,
  output wire        hreadyout,
  output wire [31:0] hrdata,
  output wire        hresp,

  // WB Slave signals (driven by cocotbext-wishbone WishboneSlave)
  output wire        wb_cyc,
  output wire        wb_stb,
  output wire        wb_we,
  output wire [31:0] wb_adr,
  output wire [31:0] wb_datwr,
  output wire  [3:0] wb_sel,
  input  wire [31:0] wb_datrd,
  input  wire        wb_ack,
  input  wire        wb_err
);

  // Map hreadyout back to hready for AHBBus (the slave drives hready)
  // The cocotbext-ahb master reads hready as its input.
  // In a real system, a mux selects hreadyout from the active slave.
  // Here we wire hreadyout directly.

  ahb3lite_to_wb u_dut (
    .clk_i          (hclk),
    .rst_n_i        (hresetn),

    // AHB slave side
    .sHADDR         (haddr),
    .sHWDATA        (hwdata),
    .sHWRITE        (hwrite),
    .sHREADYOUT     (hreadyout),
    .sHSIZE         (hsize),
    .sHBURST        (hburst),
    .sHSEL          (hsel),
    .sHTRANS        (htrans),
    .sHRDATA        (hrdata),
    .sHRESP         (hresp),
    .sHREADY        (hready),
    .sHPROT         (hprot),

    // WB slave side
    .to_wb_dat_i    (wb_datwr),
    .to_wb_adr_i    (wb_adr),
    .to_wb_sel_i    (wb_sel),
    .to_wb_we_i     (wb_we),
    .to_wb_cyc_i    (wb_cyc),
    .to_wb_stb_i    (wb_stb),
    .from_wb_dat_o  (wb_datrd),
    .from_wb_ack_o  (wb_ack),
    .from_wb_err_o  (wb_err)
  );

  // VCD dump for waveform debugging
  initial begin
    $dumpfile("ahb3lite_to_wb_tb.vcd");
    $dumpvars(0, ahb3lite_to_wb_tb);
  end

endmodule
