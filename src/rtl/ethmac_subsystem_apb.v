//-----------------------------------------------------------------------------
// ethmac_subsystem_apb.v
//-----------------------------------------------------------------------------
// Combined Ethernet MAC + IEEE 1588 PTP timestamping subsystem.
//
// Provides a single APB slave port for register access to both peripherals,
// address-decoded via a CMSDK APB slave mux, and a single AHB master port
// for the Ethernet MAC's DMA engine.
//
// Address map (from APB slave port):
//   0x0000 - 0x0FFF   Ethernet MAC registers & buffer descriptors (Port 0)
//   0x1000 - 0x1FFF   HA1588 PTP registers                       (Port 1)
//
// Architecture:
//                                ┌─ apb_to_wb ─── eth_top (regs)
//   APB Slave ─► apb_slave_mux ─┤
//                                └─ apb_to_wb ─── wb_slv_wrapper ─── ha1588
//
//   AHB Master ◄── wb_to_ahb3lite ◄── eth_top (DMA)
//
//   MII ◄────────► eth_top (PHY interface)
//   GMII monitor ─► ha1588 (timestamping)
//   RTC outputs  ◄─ ha1588
//   int_o        ◄─ eth_top
//-----------------------------------------------------------------------------

module ethmac_subsystem_apb #(
  // Propagates to wb_to_ahb3lite on the DMA master path. Set to 1 when
  // the host CPU is little-endian so in-memory frame bytes match on-wire
  // byte order (required for PicoTCP and similar stacks that read the
  // RX buffer byte-by-byte). Default 0 preserves legacy behaviour for
  // the cocotb regression suites under ../cocotb/ethmac_subsystem_apb/.
  parameter SWAP_DMA_BYTES = 1'b0
)(
  // Clock and Reset
  input  wire        pclk,
  input  wire        presetn,

  // AHB Master Interface (DMA)
  output wire [31:0] haddr,
  output wire  [1:0] htrans,
  output wire  [2:0] hsize,
  output wire  [2:0] hburst,
  output wire  [3:0] hprot,
  output wire        hmastlock,
  output wire        hwrite,
  output wire [31:0] hwdata,
  input  wire [31:0] hrdata,
  input  wire        hready,
  input  wire        hresp,

  // APB Slave Interface (Register Access — shared)
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

  // MII Transmit
  input  wire        mtx_clk_pad_i,
  output wire  [3:0] mtxd_pad_o,
  output wire        mtxen_pad_o,
  output wire        mtxerr_pad_o,

  // MII Receive
  input  wire        mrx_clk_pad_i,
  input  wire  [3:0] mrxd_pad_i,
  input  wire        mrxdv_pad_i,
  input  wire        mrxerr_pad_i,

  // MII Common
  input  wire        mcoll_pad_i,
  input  wire        mcrs_pad_i,

  // MII Management Interface
  input  wire        md_pad_i,
  output wire        mdc_pad_o,
  output wire        md_pad_o,
  output wire        md_padoe_o,

  // Interrupt
  output wire        int_o,

  // RX Checksum Calculator Interrupt — separate level-sensitive line
  // from the eth_rx_cksum block. Integrators choose to OR with int_o
  // at the SoC top, route to its own NVIC line, or leave dangling.
  output wire        cksum_int_o,

  // PTP Event Outputs (synchronized to pclk)
  output wire        rx_ptp_event,
  output wire        tx_ptp_event,

  // HA1588 Hardware Servo — Control Inputs (from PHC registers)
  input  wire        ha1588_servo_en,
  input  wire [29:0] ha1588_sync_interval,

  // HA1588 Hardware Servo — PHC Capture Readback (from PHC hw_cap outputs)
  input  wire [47:0] phc_seconds,
  input  wire [29:0] phc_nanoseconds,
  input  wire [47:0] phc_hw_cap_seconds,
  input  wire [29:0] phc_hw_cap_nanoseconds,
  input  wire [31:0] phc_hw_cap_sub_nanoseconds,

  // HA1588 Hardware Servo — Outputs (to PHC servo source 1)
  output wire        ha1588_hw_capture,
  output wire        ha1588_hw_set_time,
  output wire [47:0] ha1588_hw_set_seconds,
  output wire [29:0] ha1588_hw_set_nanoseconds,
  output wire        ha1588_hw_adj_valid,
  output wire [31:0] ha1588_hw_adj_ns_incr_frac,

  // HA1588 Hardware Servo — Status Outputs
  output wire        ha1588_servo_locked,
  output wire        ha1588_servo_phase_step_active
);

  // =================================================================
  // APB Slave Mux — address decode
  // =================================================================
  // DECODE4BIT = paddr[15:12] selects between the peripherals:
  //   0 → Port 0 (Ethernet MAC,         0x0000-0x0FFF)
  //   1 → Port 1 (HA1588 PTP,           0x1000-0x1FFF)
  //   2 → Port 2 (RX Checksum Calc,     0x2000-0x2FFF)

  wire        psel_eth;
  wire [31:0] prdata_eth;
  wire        pready_eth;
  wire        pslverr_eth;

  wire        psel_ptp;
  wire [31:0] prdata_ptp;
  wire        pready_ptp;
  wire        pslverr_ptp;

  wire        psel_cksum;
  wire [31:0] prdata_cksum;
  wire        pready_cksum;
  wire        pslverr_cksum;

  cmsdk_apb_slave_mux #(
    .PORT0_ENABLE  (1),
    .PORT1_ENABLE  (1),
    .PORT2_ENABLE  (1),
    .PORT3_ENABLE  (0),
    .PORT4_ENABLE  (0),
    .PORT5_ENABLE  (0),
    .PORT6_ENABLE  (0),
    .PORT7_ENABLE  (0),
    .PORT8_ENABLE  (0),
    .PORT9_ENABLE  (0),
    .PORT10_ENABLE (0),
    .PORT11_ENABLE (0),
    .PORT12_ENABLE (0),
    .PORT13_ENABLE (0),
    .PORT14_ENABLE (0),
    .PORT15_ENABLE (0)
  ) u_apb_mux (
    .DECODE4BIT (paddr[15:12]),
    .PSEL       (psel),

    // Port 0 — Ethernet MAC
    .PSEL0      (psel_eth),
    .PREADY0    (pready_eth),
    .PRDATA0    (prdata_eth),
    .PSLVERR0   (pslverr_eth),

    // Port 1 — HA1588 PTP
    .PSEL1      (psel_ptp),
    .PREADY1    (pready_ptp),
    .PRDATA1    (prdata_ptp),
    .PSLVERR1   (pslverr_ptp),

    // Port 2 — RX Checksum Calculator
    .PSEL2      (psel_cksum),
    .PREADY2    (pready_cksum),
    .PRDATA2    (prdata_cksum),
    .PSLVERR2   (pslverr_cksum),

    // Unused ports — tie off inputs
    .PSEL3      (), .PREADY3  (1'b1), .PRDATA3  (32'h0), .PSLVERR3  (1'b0),
    .PSEL4      (), .PREADY4  (1'b1), .PRDATA4  (32'h0), .PSLVERR4  (1'b0),
    .PSEL5      (), .PREADY5  (1'b1), .PRDATA5  (32'h0), .PSLVERR5  (1'b0),
    .PSEL6      (), .PREADY6  (1'b1), .PRDATA6  (32'h0), .PSLVERR6  (1'b0),
    .PSEL7      (), .PREADY7  (1'b1), .PRDATA7  (32'h0), .PSLVERR7  (1'b0),
    .PSEL8      (), .PREADY8  (1'b1), .PRDATA8  (32'h0), .PSLVERR8  (1'b0),
    .PSEL9      (), .PREADY9  (1'b1), .PRDATA9  (32'h0), .PSLVERR9  (1'b0),
    .PSEL10     (), .PREADY10 (1'b1), .PRDATA10 (32'h0), .PSLVERR10 (1'b0),
    .PSEL11     (), .PREADY11 (1'b1), .PRDATA11 (32'h0), .PSLVERR11 (1'b0),
    .PSEL12     (), .PREADY12 (1'b1), .PRDATA12 (32'h0), .PSLVERR12 (1'b0),
    .PSEL13     (), .PREADY13 (1'b1), .PRDATA13 (32'h0), .PSLVERR13 (1'b0),
    .PSEL14     (), .PREADY14 (1'b1), .PRDATA14 (32'h0), .PSLVERR14 (1'b0),
    .PSEL15     (), .PREADY15 (1'b1), .PRDATA15 (32'h0), .PSLVERR15 (1'b0),

    // Muxed outputs
    .PREADY     (pready),
    .PRDATA     (prdata),
    .PSLVERR    (pslverr)
  );

  // =================================================================
  // Port 0 — Ethernet MAC (APB register access + AHB DMA master)
  // =================================================================

  //---------------------------------------------------
  // Ethernet MAC: APB → WB bridge (register access)
  //---------------------------------------------------
  wire [31:0] eth_wb_adr;
  wire [31:0] eth_wb_wdat;
  wire  [3:0] eth_wb_sel;
  wire        eth_wb_we;
  wire        eth_wb_cyc;
  wire        eth_wb_stb;
  wire [31:0] eth_wb_rdat;
  wire        eth_wb_ack;
  wire        eth_wb_err;

  apb_to_wb u_eth_apb_to_wb (
    .pclk       (pclk),
    .presetn    (presetn),

    .psel       (psel_eth),
    .penable    (penable),
    .paddr      (paddr),
    .pwrite     (pwrite),
    .pwdata     (pwdata),
    .pstrb      (pstrb),
    .prdata     (prdata_eth),
    .pready     (pready_eth),
    .pslverr    (pslverr_eth),

    .wb_adr_o   (eth_wb_adr),
    .wb_dat_o   (eth_wb_wdat),
    .wb_sel_o   (eth_wb_sel),
    .wb_we_o    (eth_wb_we),
    .wb_cyc_o   (eth_wb_cyc),
    .wb_stb_o   (eth_wb_stb),
    .wb_dat_i   (eth_wb_rdat),
    .wb_ack_i   (eth_wb_ack),
    .wb_err_i   (eth_wb_err)
  );

  //---------------------------------------------------
  // Ethernet MAC: WB master → AHB master bridge (DMA)
  //---------------------------------------------------
  wire [31:0] m_wb_adr_o;
  wire  [3:0] m_wb_sel_o;
  wire        m_wb_we_o;
  wire [31:0] m_wb_dat_o;
  wire [31:0] m_wb_dat_i;
  wire        m_wb_cyc_o;
  wire        m_wb_stb_o;
  wire        m_wb_ack_i;
  wire        m_wb_err_i;
  wire  [2:0] m_wb_cti_o;
  wire  [1:0] m_wb_bte_o;

  wb_to_ahb3lite #(
    .SWAP_DMA_BYTES (SWAP_DMA_BYTES)
  ) u_wb_to_ahb3lite (
    .clk_i              (pclk),
    .rst_n_i            (presetn),

    .from_m_wb_adr_o    (m_wb_adr_o),
    .from_m_wb_sel_o    (m_wb_sel_o),
    .from_m_wb_we_o     (m_wb_we_o),
    .from_m_wb_dat_o    (m_wb_dat_o),
    .from_m_wb_cyc_o    (m_wb_cyc_o),
    .from_m_wb_stb_o    (m_wb_stb_o),
    .to_m_wb_ack_i      (m_wb_ack_i),
    .to_m_wb_err_i      (m_wb_err_i),
    .to_m_wb_dat_i      (m_wb_dat_i),
    .from_m_wb_cti_o    (m_wb_cti_o),
    .from_m_wb_bte_o    (m_wb_bte_o),

    .mHSEL              (hmastlock),
    .mHSIZE             (hsize),
    .mHRDATA            (hrdata),
    .mHRESP             (hresp),
    .mHREADY            (hready),
    .mHREADYOUT         (),
    .mHWRITE            (hwrite),
    .mHBURST            (hburst),
    .mHADDR             (haddr),
    .mHTRANS            (htrans),
    .mHWDATA            (hwdata),
    .mHPROT             (hprot)
  );

  //---------------------------------------------------
  // Ethernet MAC Core
  //---------------------------------------------------
  eth_top u_eth_top (
    // WISHBONE common
    .wb_clk_i       (pclk),
    .wb_rst_i       (~presetn),
    .wb_dat_i       (eth_wb_wdat),
    .wb_dat_o       (eth_wb_rdat),

    // WISHBONE slave (register access from APB)
    .wb_adr_i       (eth_wb_adr[11:2]),
    .wb_sel_i       (eth_wb_sel),
    .wb_we_i        (eth_wb_we),
    .wb_cyc_i       (eth_wb_cyc),
    .wb_stb_i       (eth_wb_stb),
    .wb_ack_o       (eth_wb_ack),
    .wb_err_o       (eth_wb_err),

    // WISHBONE master (DMA → AHB)
    .m_wb_adr_o     (m_wb_adr_o),
    .m_wb_sel_o     (m_wb_sel_o),
    .m_wb_we_o      (m_wb_we_o),
    .m_wb_dat_o     (m_wb_dat_o),
    .m_wb_dat_i     (m_wb_dat_i),
    .m_wb_cyc_o     (m_wb_cyc_o),
    .m_wb_stb_o     (m_wb_stb_o),
    .m_wb_ack_i     (m_wb_ack_i),
    .m_wb_err_i     (m_wb_err_i),

`ifdef ETH_WISHBONE_B3
    .m_wb_cti_o     (m_wb_cti_o),
    .m_wb_bte_o     (m_wb_bte_o),
`endif

    // MII Transmit
    .mtx_clk_pad_i  (mtx_clk_pad_i),
    .mtxd_pad_o     (mtxd_pad_o),
    .mtxen_pad_o    (mtxen_pad_o),
    .mtxerr_pad_o   (mtxerr_pad_o),

    // MII Receive
    .mrx_clk_pad_i  (mrx_clk_pad_i),
    .mrxd_pad_i     (mrxd_pad_i),
    .mrxdv_pad_i    (mrxdv_pad_i),
    .mrxerr_pad_i   (mrxerr_pad_i),

    // MII Common
    .mcoll_pad_i    (mcoll_pad_i),
    .mcrs_pad_i     (mcrs_pad_i),

    // MII Management
    .md_pad_i       (md_pad_i),
    .mdc_pad_o      (mdc_pad_o),
    .md_pad_o       (md_pad_o),
    .md_padoe_o     (md_padoe_o),

    // Interrupt
    .int_o          (int_o)
  );

  // =================================================================
  // Port 1 — HA1588 PTP Timestamping Unit (APB register access only)
  // =================================================================

  //---------------------------------------------------
  // HA1588: APB → WB bridge
  //---------------------------------------------------
  wire [31:0] ptp_wb_adr;
  wire [31:0] ptp_wb_wdat;
  wire  [3:0] ptp_wb_sel;
  wire        ptp_wb_we;
  wire        ptp_wb_cyc;
  wire        ptp_wb_stb;
  wire [31:0] ptp_wb_rdat;
  wire        ptp_wb_ack;
  wire        ptp_wb_err;

  apb_to_wb u_ptp_apb_to_wb (
    .pclk       (pclk),
    .presetn    (presetn),

    .psel       (psel_ptp),
    .penable    (penable),
    .paddr      (paddr),
    .pwrite     (pwrite),
    .pwdata     (pwdata),
    .pstrb      (pstrb),
    .prdata     (prdata_ptp),
    .pready     (pready_ptp),
    .pslverr    (pslverr_ptp),

    .wb_adr_o   (ptp_wb_adr),
    .wb_dat_o   (ptp_wb_wdat),
    .wb_sel_o   (ptp_wb_sel),
    .wb_we_o    (ptp_wb_we),
    .wb_cyc_o   (ptp_wb_cyc),
    .wb_stb_o   (ptp_wb_stb),
    .wb_dat_i   (ptp_wb_rdat),
    .wb_ack_i   (ptp_wb_ack),
    .wb_err_i   (ptp_wb_err)
  );

  assign ptp_wb_err = 1'b0;

  //---------------------------------------------------
  // HA1588: WB → Simple Bus Adapter
  //---------------------------------------------------
  wire        ha_rst;
  wire        ha_clk;
  wire        ha_wr;
  wire        ha_rd;
  wire  [7:0] ha_addr;
  wire [31:0] ha_wdata;
  wire [31:0] ha_rdata;

  wb_slv_wrapper u_wb_slv_wrapper (
    .rst_i      (~presetn),
    .clk_i      (pclk),
    .stb_i      (ptp_wb_cyc & ptp_wb_stb),
    .we_i       (ptp_wb_we),
    .ack_o      (ptp_wb_ack),
    .adr_i      (ptp_wb_adr),
    .dat_i      (ptp_wb_wdat),
    .dat_o      (ptp_wb_rdat),

    .rst        (ha_rst),
    .clk        (ha_clk),
    .wr_out     (ha_wr),
    .rd_out     (ha_rd),
    .addr_out   (ha_addr),
    .data_out   (ha_wdata),
    .data_in    (ha_rdata)
  );

  //---------------------------------------------------
  // HA1588 PTP Core
  //---------------------------------------------------
  ha1588 u_ha1588 (
    .rst            (ha_rst),
    .clk            (ha_clk),
    .wr_in          (ha_wr),
    .rd_in          (ha_rd),
    .addr_in        (ha_addr),
    .data_in        (ha_wdata),
    .data_out       (ha_rdata),

    .rtc_clk        (rtc_clk),

    .rtc_time_ptp_ns  (rtc_time_ptp_ns),
    .rtc_time_ptp_sec (rtc_time_ptp_sec),
    .rtc_time_one_pps (rtc_time_one_pps),

    // GMII RX monitoring — tapped from MII RX signals
    // MII is 4-bit, so upper nibble is zero and giga_mode=0
    .rx_gmii_clk    (mrx_clk_pad_i),
    .rx_gmii_ctrl   (mrxdv_pad_i),
    .rx_gmii_data   ({4'b0, mrxd_pad_i}),
    .rx_giga_mode   (1'b0),

    // GMII TX monitoring — tapped from MII TX signals
    .tx_gmii_clk    (mtx_clk_pad_i),
    .tx_gmii_ctrl   (mtxen_pad_o),
    .tx_gmii_data   ({4'b0, mtxd_pad_o}),
    .tx_giga_mode   (1'b0)
  );

  // =================================================================
  // Port 2 — RX Checksum Calculator (passive MII RX snoop)
  // =================================================================
  // Native APB slave (no apb_to_wb bridge). Snoops the same MII RX
  // nibble stream HA1588 already taps. Dual-clock internally —
  // accumulators on mrx_clk_pad_i, register file on pclk.

  // -----------------------------------------------------------------
  // ASIC sign-off bug 6: mrx/mtx-domain reset bridges (RDC fix)
  // -----------------------------------------------------------------
  // `presetn` is the hclk/pclk-domain system reset. Feeding it directly
  // as the async reset of mrx_clk_pad_i / mtx_clk_pad_i flops (the cksum
  // block, the two ptp_event_detectors, and the toggle-CDC source flops)
  // is a reset-domain crossing: it ASSERTS fine (async) but its
  // DEASSERTION is asynchronous to the MII clocks → recovery/removal
  // timing violation, so e.g. eth_rx_cksum's gray FIFO write pointer can
  // leave reset metastable/skewed and break the Gray-code invariant.
  // Standard 2-FF reset bridge: async-assert on presetn (so power-on
  // still forces reset immediately — no double-reset, assertion path
  // unchanged), sync-deassert onto each MII clock. If the PHY RX/TX
  // clock is absent (link down at boot) the bridge stays in reset — the
  // safe state (block held until a clock exists).
  reg mrx_rstn_meta, mrx_rstn_sync;
  always @(posedge mrx_clk_pad_i or negedge presetn) begin
    if (!presetn) begin
      mrx_rstn_meta <= 1'b0;
      mrx_rstn_sync <= 1'b0;
    end else begin
      mrx_rstn_meta <= 1'b1;
      mrx_rstn_sync <= mrx_rstn_meta;
    end
  end

  reg mtx_rstn_meta, mtx_rstn_sync;
  always @(posedge mtx_clk_pad_i or negedge presetn) begin
    if (!presetn) begin
      mtx_rstn_meta <= 1'b0;
      mtx_rstn_sync <= 1'b0;
    end else begin
      mtx_rstn_meta <= 1'b1;
      mtx_rstn_sync <= mtx_rstn_meta;
    end
  end

  eth_rx_cksum #(
    .SNAPSHOT_FIFO_DEPTH (2)
  ) u_eth_rx_cksum (
    .pclk        (pclk),
    .presetn     (presetn),

    .mrx_clk_i   (mrx_clk_pad_i),
    .mrx_rstn_i  (mrx_rstn_sync),   // bug 6: mrx-domain bridged reset (was presetn)
    .mrxd_i      (mrxd_pad_i),
    .mrxdv_i     (mrxdv_pad_i),
    .mrxerr_i    (mrxerr_pad_i),

    .psel        (psel_cksum),
    .penable     (penable),
    .paddr       (paddr),
    .pwrite      (pwrite),
    .pwdata      (pwdata),
    .pstrb       (pstrb),
    .prdata      (prdata_cksum),
    .pready      (pready_cksum),
    .pslverr     (pslverr_cksum),

    .cksum_int_o (cksum_int_o)
  );

  // =================================================================
  // PTP Event Detectors — lightweight PTP frame detection on MII
  // =================================================================
  // Monitors the same MII signals already tapped for HA1588 and generates
  // single-cycle pulses when PTP frames (EtherType 0x88F7) are detected.
  // These events are used to trigger PHC timestamp capture externally.

  wire rx_ptp_event_raw;  // In mrx_clk domain
  wire tx_ptp_event_raw;  // In mtx_clk domain

  ptp_event_detector u_rx_ptp_det (
    .clk       (mrx_clk_pad_i),
    .resetn    (mrx_rstn_sync),   // bug 6: mrx-domain bridged reset (was presetn)
    .mii_dv    (mrxdv_pad_i),
    .mii_data  (mrxd_pad_i),
    .ptp_event (rx_ptp_event_raw)
  );

  ptp_event_detector u_tx_ptp_det (
    .clk       (mtx_clk_pad_i),
    .resetn    (mtx_rstn_sync),   // bug 6: mtx-domain bridged reset (was presetn)
    .mii_dv    (mtxen_pad_o),
    .mii_data  (mtxd_pad_o),
    .ptp_event (tx_ptp_event_raw)
  );

  // -----------------------------------------------------------------
  // CDC: Toggle-based synchronisation (MII clock → pclk)
  // -----------------------------------------------------------------
  // A narrow single-cycle pulse in the 25 MHz MII domain could be missed
  // by a simple 2-FF synchronizer if pclk is faster. Toggle-CDC converts
  // the pulse to a level change, synchronizes the level, then edge-detects.

  // RX path (mrx_clk → pclk)
  reg rx_toggle_src;
  always @(posedge mrx_clk_pad_i or negedge mrx_rstn_sync) begin   // bug 6
    if (!mrx_rstn_sync)
      rx_toggle_src <= 1'b0;
    else if (rx_ptp_event_raw)
      rx_toggle_src <= ~rx_toggle_src;
  end

  reg [2:0] rx_toggle_sync;
  always @(posedge pclk or negedge presetn) begin
    if (!presetn)
      rx_toggle_sync <= 3'b0;
    else
      rx_toggle_sync <= {rx_toggle_sync[1:0], rx_toggle_src};
  end

  assign rx_ptp_event = rx_toggle_sync[2] ^ rx_toggle_sync[1];

  // TX path (mtx_clk → pclk)
  reg tx_toggle_src;
  always @(posedge mtx_clk_pad_i or negedge mtx_rstn_sync) begin   // bug 6
    if (!mtx_rstn_sync)
      tx_toggle_src <= 1'b0;
    else if (tx_ptp_event_raw)
      tx_toggle_src <= ~tx_toggle_src;
  end

  reg [2:0] tx_toggle_sync;
  always @(posedge pclk or negedge presetn) begin
    if (!presetn)
      tx_toggle_sync <= 3'b0;
    else
      tx_toggle_sync <= {tx_toggle_sync[1:0], tx_toggle_src};
  end

  assign tx_ptp_event = tx_toggle_sync[2] ^ tx_toggle_sync[1];

  // =================================================================
  // HA1588 Hardware Servo
  // =================================================================
  // Periodically compares the HA1588 software-corrected RTC time to
  // the PHC timestamp and generates servo corrections (phase step or
  // frequency adjustment) to discipline the PHC.

  ha1588_servo #(
    .SYS_DATA_W (32)
  ) u_ha1588_servo (
    .clk                    (pclk),
    .resetn                 (presetn),

    // Control (from PHC SERVO_CTRL register via top-level ports)
    .enable                 (ha1588_servo_en),
    .sync_interval          (ha1588_sync_interval),

    // HA1588 RTC inputs (rtc_clk domain)
    .rtc_clk                (rtc_clk),
    .rtc_time_ptp_ns        (rtc_time_ptp_ns),
    .rtc_time_ptp_sec       (rtc_time_ptp_sec),

    // PHC current time (for interval timer, from PHC via top-level ports)
    .phc_seconds            (phc_seconds),
    .phc_nanoseconds        (phc_nanoseconds),

    // PHC hw_capture interface (capture readback from PHC via top-level ports)
    .hw_capture             (ha1588_hw_capture),
    .hw_cap_seconds         (phc_hw_cap_seconds),
    .hw_cap_nanoseconds     (phc_hw_cap_nanoseconds),
    .hw_cap_sub_nanoseconds (phc_hw_cap_sub_nanoseconds),

    // Servo outputs (to PHC servo source 1)
    .hw_set_time            (ha1588_hw_set_time),
    .hw_set_seconds         (ha1588_hw_set_seconds),
    .hw_set_nanoseconds     (ha1588_hw_set_nanoseconds),
    .hw_adj_valid           (ha1588_hw_adj_valid),
    .hw_adj_ns_incr_frac    (ha1588_hw_adj_ns_incr_frac),

    // Status
    .locked                 (ha1588_servo_locked),
    .phase_step_active      (ha1588_servo_phase_step_active)
  );

endmodule
