//-----------------------------------------------------------------------------
// tb_eth_rx_cksum.v
//-----------------------------------------------------------------------------
// Cocotb testbench wrapper for eth_rx_cksum (standalone unit-level TB).
//
// Provides:
//   - "apb_*" prefix for APB slave port (driven by a manual APB master
//     in test_eth_rx_cksum.py — same style as the rest of this repo)
//   - 50 MHz pclk (APB / register clock)
//   - 25 MHz mrx_clk (MII RX clock — asynchronous to pclk on purpose,
//     so Stage 0 already exercises the dual-domain wiring even though
//     the parser is not yet implemented)
//   - Direct access to mrxd / mrxdv / mrxerr from cocotb (used by the
//     scapy-driven MII stimulus generator from Stage 1 onwards).
//-----------------------------------------------------------------------------

`timescale 1ns / 1ps

module tb_eth_rx_cksum;

  // -------------------------------------------------------
  // Clocks and resets
  // -------------------------------------------------------
  reg         pclk        = 0;
  reg         presetn     = 0;
  reg         mrx_clk_i   = 0;
  reg         mrx_rstn_i  = 0;

  // -------------------------------------------------------
  // APB slave port — prefix "apb_"
  // -------------------------------------------------------
  reg         apb_psel    = 0;
  reg         apb_penable = 0;
  reg  [31:0] apb_paddr   = 0;
  reg         apb_pwrite  = 0;
  reg  [31:0] apb_pwdata  = 0;
  reg   [3:0] apb_pstrb   = 4'hF;
  wire [31:0] apb_prdata;
  wire        apb_pready;
  wire        apb_pslverr;

  // -------------------------------------------------------
  // MII RX snoop
  // -------------------------------------------------------
  reg   [3:0] mrxd_i      = 0;
  reg         mrxdv_i     = 0;
  reg         mrxerr_i    = 0;

  // -------------------------------------------------------
  // Interrupt
  // -------------------------------------------------------
  wire        cksum_int_o;

  // -------------------------------------------------------
  // DUT
  // -------------------------------------------------------
  eth_rx_cksum #(
    .SNAPSHOT_FIFO_DEPTH (2)
  ) u_dut (
    .pclk        (pclk),
    .presetn     (presetn),

    .mrx_clk_i   (mrx_clk_i),
    .mrx_rstn_i  (mrx_rstn_i),
    .mrxd_i      (mrxd_i),
    .mrxdv_i     (mrxdv_i),
    .mrxerr_i    (mrxerr_i),

    .psel        (apb_psel),
    .penable     (apb_penable),
    .paddr       (apb_paddr),
    .pwrite      (apb_pwrite),
    .pwdata      (apb_pwdata),
    .pstrb       (apb_pstrb),
    .prdata      (apb_prdata),
    .pready      (apb_pready),
    .pslverr     (apb_pslverr),

    .cksum_int_o (cksum_int_o)
  );

  // -------------------------------------------------------
  // Wave dump
  // -------------------------------------------------------
  initial begin
    if ($test$plusargs("dump")) begin
      $dumpfile("eth_rx_cksum.vcd");
      $dumpvars(0, tb_eth_rx_cksum);
    end
  end

endmodule
