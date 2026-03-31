//-----------------------------------------------------------------------------
// ha1588_apb.v
//-----------------------------------------------------------------------------
// Wrapper for OpenCores HA1588 IEEE 1588 PTP IP (ha1588) with an APB
// slave interface, replacing the original generic bus interface.
//
// Architecture:
//   APB Slave -> apb_to_wb -> wb_slv_wrapper -> ha1588
//
// The HA1588 IP is slave-only (register access), so APB is a better fit
// than AHB — no pipelining or burst support is needed.
//
// Uses the apb_to_wb bridge from the amba_wb_bridges repository.
//-----------------------------------------------------------------------------

module ha1588_apb (
  // Clock and Reset
  input  wire        pclk,
  input  wire        presetn,

  // APB Slave Interface (Register Access)
  input  wire        psel,
  input  wire        penable,
  input  wire [31:0] paddr,
  input  wire        pwrite,
  input  wire [31:0] pwdata,
  input  wire  [3:0] pstrb,
  output wire [31:0] prdata,
  output wire        pready,
  output wire        pslverr,

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
  // APB Slave to WISHBONE Slave Bridge (Register Access)
  //---------------------------------------------------
  apb_to_wb u_apb_to_wb (
    .pclk           (pclk),
    .presetn        (presetn),

    // APB slave side
    .psel           (psel),
    .penable        (penable),
    .paddr          (paddr),
    .pwrite         (pwrite),
    .pwdata         (pwdata),
    .pstrb          (pstrb),
    .prdata         (prdata),
    .pready         (pready),
    .pslverr        (pslverr),

    // WISHBONE master side
    .wb_adr_o       (wb_adr_i),
    .wb_dat_o       (wb_dat_i),
    .wb_sel_o       (wb_sel_i),
    .wb_we_o        (wb_we_i),
    .wb_cyc_o       (wb_cyc_i),
    .wb_stb_o       (wb_stb_i),
    .wb_dat_i       (wb_dat_o),
    .wb_ack_i       (wb_ack_o),
    .wb_err_i       (wb_err_o)
  );

  // No error responses from the simple register interface
  assign wb_err_o = 1'b0;

  //---------------------------------------------------
  // WISHBONE to Simple Bus Adapter
  //---------------------------------------------------
  wb_slv_wrapper u_wb_slv_wrapper (
    // WISHBONE side
    .rst_i          (~presetn),
    .clk_i          (pclk),
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
