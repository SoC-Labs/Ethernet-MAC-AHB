//-----------------------------------------------------------------------------
// tb_top.sv — Integration testbench for Ethernet MAC + PHC synchronisation
//
// Instantiates both ethmac_subsystem_apb and phc, wires the PTP event
// outputs from the Ethernet subsystem to the PHC Ethernet capture inputs,
// and exposes all interfaces for cocotb control.
//-----------------------------------------------------------------------------

`timescale 1ns / 1ps

module tb_top;

  // -------------------------------------------------------
  // Parameters
  // -------------------------------------------------------
  parameter SYS_DATA_W = 32;
  parameter APB_ADDR_W = 12;

  // -------------------------------------------------------
  // Clocks and Reset
  // -------------------------------------------------------
  reg         pclk = 0;
  reg         presetn = 0;
  reg         rtc_clk = 0;
  reg         mrx_clk_pad_i = 0;
  reg         mtx_clk_pad_i = 0;

  // -------------------------------------------------------
  // Ethernet APB Slave Port
  // -------------------------------------------------------
  reg         eth_psel;
  reg         eth_penable;
  reg  [31:0] eth_paddr;
  reg         eth_pwrite;
  reg  [31:0] eth_pwdata;
  reg   [3:0] eth_pstrb;
  wire [31:0] eth_prdata;
  wire        eth_pready;
  wire        eth_pslverr;

  // -------------------------------------------------------
  // AHB Master Port (DMA) — stubbed with ready tie-off
  // -------------------------------------------------------
  wire [31:0] mst_haddr;
  wire  [1:0] mst_htrans;
  wire  [2:0] mst_hsize;
  wire  [2:0] mst_hburst;
  wire  [3:0] mst_hprot;
  wire        mst_hmastlock;
  wire        mst_hwrite;
  wire [31:0] mst_hwdata;
  reg  [31:0] mst_hrdata = 0;
  reg         mst_hready = 1;
  reg         mst_hresp  = 0;

  // -------------------------------------------------------
  // RTC Time Outputs (from HA1588)
  // -------------------------------------------------------
  wire [31:0] rtc_time_ptp_ns;
  wire [47:0] rtc_time_ptp_sec;
  wire        rtc_time_one_pps;

  // -------------------------------------------------------
  // MII Receive (driven by cocotb to inject frames)
  // -------------------------------------------------------
  reg   [3:0] mrxd_pad_i = 0;
  reg         mrxdv_pad_i = 0;
  reg         mrxerr_pad_i = 0;

  // -------------------------------------------------------
  // MII Transmit (monitored)
  // -------------------------------------------------------
  wire  [3:0] mtxd_pad_o;
  wire        mtxen_pad_o;
  wire        mtxerr_pad_o;

  // -------------------------------------------------------
  // MII Common
  // -------------------------------------------------------
  reg         mcoll_pad_i = 0;
  reg         mcrs_pad_i  = 0;

  // -------------------------------------------------------
  // MDIO
  // -------------------------------------------------------
  reg         md_pad_i = 1;
  wire        mdc_pad_o;
  wire        md_pad_o;
  wire        md_padoe_o;

  // -------------------------------------------------------
  // Interrupt
  // -------------------------------------------------------
  wire        int_o;

  // -------------------------------------------------------
  // PTP Event signals (ethmac → PHC)
  // -------------------------------------------------------
  wire        rx_ptp_event;
  wire        tx_ptp_event;

  // -------------------------------------------------------
  // PHC APB Slave Port
  // -------------------------------------------------------
  reg         phc_psel;
  reg         phc_penable;
  reg  [APB_ADDR_W-1:0] phc_paddr;
  reg         phc_pwrite;
  reg  [SYS_DATA_W-1:0] phc_pwdata;
  wire [SYS_DATA_W-1:0] phc_prdata;
  wire        phc_pready;
  wire        phc_pslverr;

  // -------------------------------------------------------
  // PHC additional signals
  // -------------------------------------------------------
  reg         hw_capture = 0;  // TideLink (not used in this test)
  wire        pps_irq;
  wire        alarm_irq;
  wire        pps_out;

  // -------------------------------------------------------
  // Ethernet MAC Subsystem DUT
  // -------------------------------------------------------
  ethmac_subsystem_apb u_ethmac (
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

    // APB Slave
    .psel             (eth_psel),
    .penable          (eth_penable),
    .paddr            (eth_paddr),
    .pwrite           (eth_pwrite),
    .pwdata           (eth_pwdata),
    .pstrb            (eth_pstrb),
    .prdata           (eth_prdata),
    .pready           (eth_pready),
    .pslverr          (eth_pslverr),

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

    // PTP Event Outputs → PHC
    .rx_ptp_event     (rx_ptp_event),
    .tx_ptp_event     (tx_ptp_event)
  );

  // -------------------------------------------------------
  // PHC DUT
  // -------------------------------------------------------
  phc #(
    .SYS_DATA_W      (SYS_DATA_W),
    .APB_ADDR_W      (APB_ADDR_W),
    .DEFAULT_NS_INCR (8'd4)   // 4 ns for 250 MHz
  ) u_phc (
    .clk             (pclk),
    .resetn          (presetn),

    // APB Slave
    .psel            (phc_psel),
    .penable         (phc_penable),
    .pwrite          (phc_pwrite),
    .paddr           (phc_paddr),
    .pwdata          (phc_pwdata),
    .prdata          (phc_prdata),
    .pready          (phc_pready),
    .pslverr         (phc_pslverr),

    // Hardware capture (TideLink — tied off)
    .hw_capture      (hw_capture),

    // Hardware capture outputs (not used in this test)
    .hw_cap_seconds_o        (),
    .hw_cap_nanoseconds_o    (),
    .hw_cap_sub_nanoseconds_o(),

    // Hardware servo adjustment (tied off — not used in this test)
    .hw_set_time_i       (1'b0),
    .hw_set_seconds_i    (48'b0),
    .hw_set_nanoseconds_i(30'b0),
    .hw_adj_valid_i      (1'b0),
    .hw_adj_ns_incr_frac_i(32'b0),

    // Ethernet PTP capture ← from ethmac subsystem
    .eth_rx_capture  (rx_ptp_event),
    .eth_tx_capture  (tx_ptp_event),

    // Interrupts
    .pps_irq         (pps_irq),
    .alarm_irq       (alarm_irq),

    // PPS
    .pps_out         (pps_out)
  );

  // -------------------------------------------------------
  // Waveform dump
  // -------------------------------------------------------
  initial begin
    $dumpfile("waves.vcd");
    $dumpvars(0, tb_top);
  end

endmodule
