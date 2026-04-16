//-----------------------------------------------------------------------------
// tb_ethmac_subsystem_apb.v
//-----------------------------------------------------------------------------
// Cocotb testbench wrapper for ethmac_subsystem_apb.
//
// Provides:
//   - "apb_*" prefix for APB slave port (driven by cocotb APB master)
//   - "mst_*" prefix for AHB master port (responded to by AHBLiteSlaveRAM)
//   - MII TX/RX with inverted clocks for cocotbext-eth sampling
//   - RTC clock and output observability
//-----------------------------------------------------------------------------

`timescale 1ns / 1ps

module tb_ethmac_subsystem_apb;

  // -------------------------------------------------------
  // Clock and Reset
  // -------------------------------------------------------
  reg         pclk;
  reg         presetn = 0;
  reg         rtc_clk = 0;

  // -------------------------------------------------------
  // APB Slave Port — prefix "apb_"
  // -------------------------------------------------------
  reg         apb_psel;
  reg         apb_penable;
  reg  [31:0] apb_paddr;
  reg         apb_pwrite;
  reg  [31:0] apb_pwdata;
  reg   [3:0] apb_pstrb;
  wire [31:0] apb_prdata;
  wire        apb_pready;
  wire        apb_pslverr;

  // -------------------------------------------------------
  // AHB Master Port (DMA) — prefix "mst_"
  // -------------------------------------------------------
  wire [31:0] mst_haddr;
  wire  [1:0] mst_htrans;
  wire  [2:0] mst_hsize;
  wire  [2:0] mst_hburst;
  wire  [3:0] mst_hprot;
  wire        mst_hmastlock;
  wire        mst_hwrite;
  wire [31:0] mst_hwdata;
  reg  [31:0] mst_hrdata;
  reg         mst_hready;
  reg         mst_hresp;

  // -------------------------------------------------------
  // RTC Time Outputs
  // -------------------------------------------------------
  wire [31:0] rtc_time_ptp_ns;
  wire [47:0] rtc_time_ptp_sec;
  wire        rtc_time_one_pps;

  // -------------------------------------------------------
  // MII Transmit
  // -------------------------------------------------------
  reg         mtx_clk_pad_i = 0;
  wire  [3:0] mtxd_pad_o;
  wire        mtxen_pad_o;
  wire        mtxerr_pad_o;

  // -------------------------------------------------------
  // MII Receive
  // -------------------------------------------------------
  reg         mrx_clk_pad_i = 0;
  reg   [3:0] mrxd_pad_i;
  reg         mrxdv_pad_i;
  reg         mrxerr_pad_i;

  // -------------------------------------------------------
  // MII Common
  // -------------------------------------------------------
  reg         mcoll_pad_i;
  reg         mcrs_pad_i;

  // -------------------------------------------------------
  // MII Management (MDIO)
  // -------------------------------------------------------
  reg         md_pad_i;
  wire        mdc_pad_o;
  wire        md_pad_o;
  wire        md_padoe_o;

  // -------------------------------------------------------
  // Interrupt
  // -------------------------------------------------------
  wire        int_o;

  // -------------------------------------------------------
  // DUT Instantiation
  // -------------------------------------------------------
  ethmac_subsystem_apb u_dut (
    .pclk             (pclk),
    .presetn          (presetn),

    // AHB Master (DMA)
    .haddr            (mst_haddr),
    .htrans           (mst_htrans),
    .hsize            (mst_hsize),
    .hburst           (mst_hburst),
    .hprot            (mst_hprot),
    .hmastlock        (mst_hmastlock),
    .hwrite           (mst_hwrite),
    .hwdata           (mst_hwdata),
    .hrdata           (mst_hrdata),
    .hready           (mst_hready),
    .hresp            (mst_hresp),

    // APB Slave (Registers)
    .psel             (apb_psel),
    .penable          (apb_penable),
    .paddr            (apb_paddr),
    .pwrite           (apb_pwrite),
    .pwdata           (apb_pwdata),
    .pstrb            (apb_pstrb),
    .prdata           (apb_prdata),
    .pready           (apb_pready),
    .pslverr          (apb_pslverr),

    // RTC
    .rtc_clk          (rtc_clk),
    .rtc_time_ptp_ns  (rtc_time_ptp_ns),
    .rtc_time_ptp_sec (rtc_time_ptp_sec),
    .rtc_time_one_pps (rtc_time_one_pps),

    // MII Transmit
    .mtx_clk_pad_i    (mtx_clk_pad_i),
    .mtxd_pad_o       (mtxd_pad_o),
    .mtxen_pad_o      (mtxen_pad_o),
    .mtxerr_pad_o     (mtxerr_pad_o),

    // MII Receive
    .mrx_clk_pad_i    (mrx_clk_pad_i),
    .mrxd_pad_i       (mrxd_pad_i),
    .mrxdv_pad_i      (mrxdv_pad_i),
    .mrxerr_pad_i     (mrxerr_pad_i),

    // MII Common
    .mcoll_pad_i      (mcoll_pad_i),
    .mcrs_pad_i       (mcrs_pad_i),

    // MII Management
    .md_pad_i         (md_pad_i),
    .mdc_pad_o        (mdc_pad_o),
    .md_pad_o         (md_pad_o),
    .md_padoe_o       (md_padoe_o),

    // Interrupt
    .int_o            (int_o),
    .cksum_int_o      (cksum_int_o),

    // PTP Event Outputs
    .rx_ptp_event     (rx_ptp_event),
    .tx_ptp_event     (tx_ptp_event)
  );

  wire rx_ptp_event;
  wire tx_ptp_event;
  wire cksum_int_o;

  // -------------------------------------------------------
  // Waveform dump
  // -------------------------------------------------------
  initial begin
    $dumpfile("tb_ethmac_subsystem_apb.vcd");
    $dumpvars(0, tb_ethmac_subsystem_apb);
  end

  // -------------------------------------------------------
  // Initialise inputs
  // -------------------------------------------------------
  initial begin
    mcoll_pad_i = 0;
    mcrs_pad_i  = 0;
    md_pad_i    = 1;
    mrxd_pad_i  = 0;
    mrxdv_pad_i = 0;
    mrxerr_pad_i = 0;
  end

  // Inverted MII clocks for cocotbext-eth sampling
  wire mtx_clk_inv = ~mtx_clk_pad_i;
  wire mrx_clk_inv = ~mrx_clk_pad_i;

endmodule
