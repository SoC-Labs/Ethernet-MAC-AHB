//-----------------------------------------------------------------------------
// ha1588_ahb.v
//-----------------------------------------------------------------------------
// Wrapper for OpenCores HA1588 IEEE 1588 PTP IP (ha1588) with an AHB-Lite
// slave interface, replacing the original generic bus interface.
//
// Architecture:
//   AHB Slave -> ahb3lite_to_wb -> wb_slv_wrapper -> ha1588
//
// The HA1588 IP is slave-only (register access), so no AHB master interface
// is needed (unlike the Ethernet MAC wrapper which also has a DMA master).
//
// Uses the same ahb3lite_to_wb bridge as the ethmac_ahb wrapper for
// consistency across the SoC integration.
//-----------------------------------------------------------------------------

module ha1588_ahb (
  // Clock and Reset
  input  wire        hclk,
  input  wire        hresetn,

  // AHB Slave Interface (Register Access)
  input  wire        hsel_s,
  input  wire [31:0] haddr_s,
  input  wire  [1:0] htrans_s,
  input  wire  [2:0] hsize_s,
  input  wire  [2:0] hburst_s,
  input  wire  [3:0] hprot_s,
  input  wire        hwrite_s,
  input  wire [31:0] hwdata_s,
  input  wire        hready_s,
  output wire [31:0] hrdata_s,
  output wire        hreadyout_s,
  output wire        hresp_s,

  // RTC Clock
  input  wire        rtc_clk,

  // RTC Time Outputs
  output wire [31:0] rtc_time_ptp_ns,
  output wire [47:0] rtc_time_ptp_sec,
  output wire        rtc_time_one_pps,

  // GMII RX Monitoring
  input  wire        rx_gmii_clk,
  input  wire        rx_gmii_ctrl,
  input  wire  [7:0] rx_gmii_data,
  input  wire        rx_giga_mode,

  // GMII TX Monitoring
  input  wire        tx_gmii_clk,
  input  wire        tx_gmii_ctrl,
  input  wire  [7:0] tx_gmii_data,
  input  wire        tx_giga_mode
);

  //---------------------------------------------------
  // Internal wires: WISHBONE slave (bridge <-> wb_slv_wrapper)
  //---------------------------------------------------
  wire [31:0] wb_adr_i;
  wire [31:0] wb_dat_i;
  wire  [3:0] wb_sel_i;
  wire        wb_we_i;
  wire        wb_cyc_i;
  wire        wb_stb_i;
  wire [31:0] wb_dat_o;
  wire        wb_ack_o;
  wire        wb_err_o;

  //---------------------------------------------------
  // Internal wires: simple bus (wb_slv_wrapper <-> ha1588)
  //---------------------------------------------------
  wire        ha_rst;
  wire        ha_clk;
  wire        ha_wr;
  wire        ha_rd;
  wire  [7:0] ha_addr;
  wire [31:0] ha_wdata;
  wire [31:0] ha_rdata;

  //---------------------------------------------------
  // AHB Slave to WISHBONE Slave Bridge (Register Access)
  //---------------------------------------------------
  ahb3lite_to_wb u_ahb3lite_to_wb (
    .clk_i          (hclk),
    .rst_n_i        (hresetn),

    // AHB slave side
    .sHADDR         (haddr_s),
    .sHWDATA        (hwdata_s),
    .sHWRITE        (hwrite_s),
    .sHREADYOUT     (hreadyout_s),
    .sHSIZE         (hsize_s),
    .sHBURST        (hburst_s),
    .sHSEL          (hsel_s),
    .sHTRANS        (htrans_s),
    .sHRDATA        (hrdata_s),
    .sHRESP         (hresp_s),
    .sHREADY        (hready_s),
    .sHPROT         (hprot_s),

    // WISHBONE slave side
    .to_wb_dat_i    (wb_dat_i),
    .to_wb_adr_i    (wb_adr_i),
    .to_wb_sel_i    (wb_sel_i),
    .to_wb_we_i     (wb_we_i),
    .to_wb_cyc_i    (wb_cyc_i),
    .to_wb_stb_i    (wb_stb_i),
    .from_wb_dat_o  (wb_dat_o),
    .from_wb_ack_o  (wb_ack_o),
    .from_wb_err_o  (wb_err_o)
  );

  // No error responses from the simple register interface
  assign wb_err_o = 1'b0;

  //---------------------------------------------------
  // WISHBONE to Simple Bus Adapter
  //---------------------------------------------------
  wb_slv_wrapper u_wb_slv_wrapper (
    // WISHBONE side
    .rst_i          (~hresetn),
    .clk_i          (hclk),
    .stb_i          (wb_cyc_i & wb_stb_i),
    .we_i           (wb_we_i),
    .ack_o          (wb_ack_o),
    .adr_i          (wb_adr_i),
    .dat_i          (wb_dat_i),
    .dat_o          (wb_dat_o),

    // Simple bus side
    .rst            (ha_rst),
    .clk            (ha_clk),
    .wr_out         (ha_wr),
    .rd_out         (ha_rd),
    .addr_out       (ha_addr),
    .data_out       (ha_wdata),
    .data_in        (ha_rdata)
  );

  //---------------------------------------------------
  // HA1588 IEEE 1588 PTP Core Instance
  //---------------------------------------------------
  ha1588 u_ha1588 (
    // Generic bus interface
    .rst            (ha_rst),
    .clk            (ha_clk),
    .wr_in          (ha_wr),
    .rd_in          (ha_rd),
    .addr_in        (ha_addr),
    .data_in        (ha_wdata),
    .data_out       (ha_rdata),

    // RTC clock
    .rtc_clk        (rtc_clk),

    // RTC time outputs
    .rtc_time_ptp_ns  (rtc_time_ptp_ns),
    .rtc_time_ptp_sec (rtc_time_ptp_sec),
    .rtc_time_one_pps (rtc_time_one_pps),

    // GMII RX monitoring
    .rx_gmii_clk    (rx_gmii_clk),
    .rx_gmii_ctrl   (rx_gmii_ctrl),
    .rx_gmii_data   (rx_gmii_data),
    .rx_giga_mode   (rx_giga_mode),

    // GMII TX monitoring
    .tx_gmii_clk    (tx_gmii_clk),
    .tx_gmii_ctrl   (tx_gmii_ctrl),
    .tx_gmii_data   (tx_gmii_data),
    .tx_giga_mode   (tx_giga_mode)
  );

endmodule
