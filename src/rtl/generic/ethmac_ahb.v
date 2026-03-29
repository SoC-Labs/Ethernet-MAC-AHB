//-----------------------------------------------------------------------------
// ethmac_ahb.v
//-----------------------------------------------------------------------------
// Wrapper for OpenCores Ethernet MAC (eth_top) with AHB master and AHB slave
// interfaces, replacing the original WISHBONE interfaces.
//
// Uses ahb3lite_wb_bridge IP for protocol conversion:
// - AHB slave  -> WB slave  (register access) via ahb3lite_to_wb
// - WB master  -> AHB master (DMA transfers)  via wb_to_ahb3lite
//-----------------------------------------------------------------------------

module ethmac_ahb (
  // Clock and Reset
  input  wire        HCLK,
  input  wire        HRESETn,

  // AHB Master Interface (DMA)
  output wire [31:0] HADDR,
  output wire  [1:0] HTRANS,
  output wire  [2:0] HSIZE,
  output wire  [2:0] HBURST,
  output wire  [3:0] HPROT,
  output wire        HMASTLOCK,
  output wire        HWRITE,
  output wire [31:0] HWDATA,
  input  wire [31:0] HRDATA,
  input  wire        HREADY,
  input  wire        HRESP,

  // AHB Slave Interface (Register Access)
  input  wire        HSEL_S,
  input  wire [31:0] HADDR_S,
  input  wire  [1:0] HTRANS_S,
  input  wire  [2:0] HSIZE_S,
  input  wire  [2:0] HBURST_S,
  input  wire  [3:0] HPROT_S,
  input  wire        HWRITE_S,
  input  wire [31:0] HWDATA_S,
  input  wire        HREADY_S,
  output wire [31:0] HRDATA_S,
  output wire        HREADYOUT_S,
  output wire        HRESP_S,

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
  output wire        int_o
);

  //---------------------------------------------------
  // Internal wires: WISHBONE slave (bridge <-> eth_top)
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
  // Internal wires: WISHBONE master (eth_top <-> bridge)
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

  //---------------------------------------------------
  // AHB Slave to WISHBONE Slave Bridge (Register Access)
  //---------------------------------------------------
  ahb3lite_to_wb u_ahb3lite_to_wb (
    .clk_i          (HCLK),
    .rst_n_i        (HRESETn),

    // AHB slave side
    .sHADDR         (HADDR_S),
    .sHWDATA        (HWDATA_S),
    .sHWRITE        (HWRITE_S),
    .sHREADYOUT     (HREADYOUT_S),
    .sHSIZE         (HSIZE_S),
    .sHBURST        (HBURST_S),
    .sHSEL          (HSEL_S),
    .sHTRANS        (HTRANS_S),
    .sHRDATA        (HRDATA_S),
    .sHRESP         (HRESP_S),
    .sHREADY        (HREADY_S),
    .sHPROT         (HPROT_S),

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

  //---------------------------------------------------
  // WISHBONE Master to AHB Master Bridge (DMA)
  //---------------------------------------------------
  wb_to_ahb3lite u_wb_to_ahb3lite (
    .clk_i              (HCLK),
    .rst_n_i            (HRESETn),

    // WISHBONE master side
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

    // AHB master side
    .mHSEL              (HMASTLOCK),
    .mHSIZE             (HSIZE),
    .mHRDATA            (HRDATA),
    .mHRESP             (HRESP),
    .mHREADY            (HREADY),
    .mHREADYOUT         (),
    .mHWRITE            (HWRITE),
    .mHBURST            (HBURST),
    .mHADDR             (HADDR),
    .mHTRANS            (HTRANS),
    .mHWDATA            (HWDATA),
    .mHPROT             (HPROT)
  );

  //---------------------------------------------------
  // Ethernet MAC Core Instance
  //---------------------------------------------------
  eth_top u_eth_top (
    // WISHBONE common
    .wb_clk_i       (HCLK),
    .wb_rst_i       (~HRESETn),
    .wb_dat_i       (wb_dat_i),
    .wb_dat_o       (wb_dat_o),

    // WISHBONE slave
    .wb_adr_i       (wb_adr_i[11:2]),
    .wb_sel_i       (wb_sel_i),
    .wb_we_i        (wb_we_i),
    .wb_cyc_i       (wb_cyc_i),
    .wb_stb_i       (wb_stb_i),
    .wb_ack_o       (wb_ack_o),
    .wb_err_o       (wb_err_o),

    // WISHBONE master
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

endmodule
