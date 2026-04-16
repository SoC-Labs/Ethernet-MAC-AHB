///////////////////////////////////////////////////////////////////////////////
// top.sv — UVM TB top for the eth_rx_cksum block-level env.
///////////////////////////////////////////////////////////////////////////////

`timescale 1ns / 1ps

module top;

  import uvm_pkg::*;
  import eth_rx_cksum_pkg::*;
  `include "uvm_macros.svh"

  // Clocks: 50 MHz pclk, 25 MHz mrx_clk — asynchronous on purpose to
  // exercise the async FIFO and gray-code CDC paths inside the block.
  logic pclk    = 0;
  logic mrx_clk = 0;
  always #10 pclk    = ~pclk;   // 20 ns period
  always #20 mrx_clk = ~mrx_clk; // 40 ns period

  eth_rx_cksum_if intf (.pclk(pclk), .mrx_clk(mrx_clk));

  eth_rx_cksum #(
    .SNAPSHOT_FIFO_DEPTH (8)
  ) u_dut (
    .pclk        (pclk),
    .presetn     (intf.presetn),
    .mrx_clk_i   (mrx_clk),
    .mrx_rstn_i  (intf.mrx_rstn),
    .mrxd_i      (intf.mrxd),
    .mrxdv_i     (intf.mrxdv),
    .mrxerr_i    (intf.mrxerr),
    .psel        (intf.apb_psel),
    .penable     (intf.apb_penable),
    .paddr       (intf.apb_paddr),
    .pwrite      (intf.apb_pwrite),
    .pwdata      (intf.apb_pwdata),
    .pstrb       (intf.apb_pstrb),
    .prdata      (intf.apb_prdata),
    .pready      (intf.apb_pready),
    .pslverr     (intf.apb_pslverr),
    .cksum_int_o (intf.cksum_int_o)
  );

  initial begin
    uvm_config_db#(virtual eth_rx_cksum_if)::set(
      null, "*", "vif", intf);
    run_test();
  end

endmodule
