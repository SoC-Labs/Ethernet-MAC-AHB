//-----------------------------------------------------------------------------
// tb_ha1588_apb.v
//-----------------------------------------------------------------------------
// Cocotb testbench wrapper for ha1588_apb.
//
// Provides signal naming so that cocotbext-apb bus models can bind:
//   - APB slave port (register access, driven by ApbMaster)
//
// RTC and GMII monitoring signals keep their original names.
//-----------------------------------------------------------------------------

`timescale 1ns / 1ps

module tb_ha1588_apb;

  // -------------------------------------------------------
  // Clock and Reset
  // -------------------------------------------------------
  reg         pclk;
  reg         presetn = 0;

  // -------------------------------------------------------
  // APB Slave Port (Register Access)
  // -------------------------------------------------------
  reg         psel;
  reg         penable;
  reg  [31:0] paddr;
  reg         pwrite;
  reg  [31:0] pwdata;
  reg   [3:0] pstrb;
  wire [31:0] prdata_raw;
  wire [31:0] prdata;
  wire        pready;
  wire        pslverr;

  // Ensure prdata is always resolvable (replace X with 0)
  assign prdata = (^prdata_raw === 1'bx) ? 32'h0 : prdata_raw;

  // -------------------------------------------------------
  // RTC Clock
  // -------------------------------------------------------
  reg         rtc_clk = 0;

  // -------------------------------------------------------
  // RTC Time Outputs
  // -------------------------------------------------------
  wire [31:0] rtc_time_ptp_ns;
  wire [47:0] rtc_time_ptp_sec;
  wire        rtc_time_one_pps;

  // -------------------------------------------------------
  // GMII RX Monitoring
  // -------------------------------------------------------
  reg         rx_gmii_clk  = 0;
  reg         rx_gmii_ctrl = 0;
  reg   [7:0] rx_gmii_data = 0;
  reg         rx_giga_mode = 0;

  // -------------------------------------------------------
  // GMII TX Monitoring
  // -------------------------------------------------------
  reg         tx_gmii_clk  = 0;
  reg         tx_gmii_ctrl = 0;
  reg   [7:0] tx_gmii_data = 0;
  reg         tx_giga_mode = 0;

  // -------------------------------------------------------
  // DUT Instantiation
  // -------------------------------------------------------
  ha1588_apb u_dut (
    // Clock and Reset
    .pclk             (pclk),
    .presetn          (presetn),

    // APB Slave Port (Register Access)
    .psel             (psel),
    .penable          (penable),
    .paddr            (paddr),
    .pwrite           (pwrite),
    .pwdata           (pwdata),
    .pstrb            (pstrb),
    .prdata           (prdata_raw),
    .pready           (pready),
    .pslverr          (pslverr),

    // RTC Clock
    .rtc_clk          (rtc_clk),

    // RTC Time Outputs
    .rtc_time_ptp_ns  (rtc_time_ptp_ns),
    .rtc_time_ptp_sec (rtc_time_ptp_sec),
    .rtc_time_one_pps (rtc_time_one_pps),

    // GMII RX Monitoring
    .rx_gmii_clk      (rx_gmii_clk),
    .rx_gmii_ctrl     (rx_gmii_ctrl),
    .rx_gmii_data     (rx_gmii_data),
    .rx_giga_mode     (rx_giga_mode),

    // GMII TX Monitoring
    .tx_gmii_clk      (tx_gmii_clk),
    .tx_gmii_ctrl     (tx_gmii_ctrl),
    .tx_gmii_data     (tx_gmii_data),
    .tx_giga_mode     (tx_giga_mode)
  );

  // -------------------------------------------------------
  // Dump waveforms (VCD)
  // -------------------------------------------------------
  initial begin
    $dumpfile("tb_ha1588_apb.vcd");
    $dumpvars(0, tb_ha1588_apb);
  end

endmodule
