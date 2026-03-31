//-----------------------------------------------------------------------------
// tb_ha1588_ahb.v
//-----------------------------------------------------------------------------
// Cocotb testbench wrapper for ha1588_ahb.
//
// Provides signal prefix remapping so that cocotbext-ahb bus models can bind:
//   - "slv_*" prefix  -> AHB slave port (register access, driven by AHBLiteMaster)
//
// RTC and GMII monitoring signals keep their original names.
//-----------------------------------------------------------------------------

`timescale 1ns / 1ps

module tb_ha1588_ahb;

  // -------------------------------------------------------
  // Clock and Reset
  // -------------------------------------------------------
  reg         hclk;
  reg         hresetn = 0;

  // -------------------------------------------------------
  // AHB Slave Port (Register Access) - prefix "slv_"
  // Inputs to DUT (reg), outputs from DUT (wire)
  // -------------------------------------------------------
  reg         slv_hsel;
  reg  [31:0] slv_haddr;
  reg   [1:0] slv_htrans;
  reg   [2:0] slv_hsize;
  reg   [2:0] slv_hburst;
  reg   [3:0] slv_hprot;
  reg         slv_hwrite;
  reg  [31:0] slv_hwdata;
  wire [31:0] slv_hrdata_raw;
  wire [31:0] slv_hrdata;
  wire        slv_hready;

  // Ensure hrdata is always resolvable (replace X with 0)
  assign slv_hrdata = (^slv_hrdata_raw === 1'bx) ? 32'h0 : slv_hrdata_raw;

  // In a single-slave system, hready_in = hreadyout (feedback)
  wire        slv_hready_mux;
  assign slv_hready_mux = slv_hready;
  wire        slv_hresp;

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
  ha1588_ahb u_dut (
    // Clock and Reset
    .hclk             (hclk),
    .hresetn          (hresetn),

    // AHB Slave Port (Register Access)
    .hsel_s           (slv_hsel),
    .haddr_s          (slv_haddr),
    .htrans_s         (slv_htrans),
    .hsize_s          (slv_hsize),
    .hburst_s         (slv_hburst),
    .hprot_s          (slv_hprot),
    .hwrite_s         (slv_hwrite),
    .hwdata_s         (slv_hwdata),
    .hready_s         (slv_hready_mux),
    .hrdata_s         (slv_hrdata_raw),
    .hreadyout_s      (slv_hready),
    .hresp_s          (slv_hresp),

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
    $dumpfile("tb_ha1588_ahb.vcd");
    $dumpvars(0, tb_ha1588_ahb);
  end

endmodule
