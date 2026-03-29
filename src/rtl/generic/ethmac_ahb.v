//-----------------------------------------------------------------------------
// ethmac_ahb.v
//-----------------------------------------------------------------------------
// Wrapper for OpenCores Ethernet MAC (eth_top) with AHB master and APB slave
// interfaces, replacing the original WISHBONE interfaces.
//
// - APB slave:  Register access (replaces WISHBONE slave)
// - AHB master: DMA transfers  (replaces WISHBONE master)
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
  output wire        HWRITE,
  output wire [31:0] HWDATA,
  input  wire [31:0] HRDATA,
  input  wire        HREADY,
  input  wire  [1:0] HRESP,

  // APB Slave Interface (Register Access)
  input  wire        PSEL,
  input  wire        PENABLE,
  input  wire        PWRITE,
  input  wire [11:2] PADDR,
  input  wire [31:0] PWDATA,
  output wire [31:0] PRDATA,
  output wire        PREADY,
  output wire        PSLVERR,

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
  // Internal wires: WISHBONE slave (APB <-> eth_top)
  //---------------------------------------------------
  wire        wb_cyc_i;
  wire        wb_stb_i;
  wire        wb_we_i;
  wire [31:0] wb_dat_i;
  wire [31:0] wb_dat_o;
  wire        wb_ack_o;
  wire        wb_err_o;
  wire  [3:0] wb_sel_i;

  //---------------------------------------------------
  // Internal wires: WISHBONE master (eth_top <-> AHB)
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

  //---------------------------------------------------
  // APB Slave to WISHBONE Slave Bridge
  //---------------------------------------------------
  // TODO: Implement APB to WISHBONE bridge logic
  assign wb_cyc_i = PSEL;
  assign wb_stb_i = PSEL & PENABLE;
  assign wb_we_i  = PWRITE;
  assign wb_dat_i = PWDATA;
  assign wb_sel_i = 4'hF;

  assign PRDATA   = wb_dat_o;
  assign PREADY   = wb_ack_o;
  assign PSLVERR  = wb_err_o;

  //---------------------------------------------------
  // WISHBONE Master to AHB Master Bridge
  //---------------------------------------------------
  // TODO: Implement WISHBONE to AHB bridge logic
  assign HADDR    = m_wb_adr_o;
  assign HTRANS   = 2'b00;
  assign HSIZE    = 3'b010;
  assign HBURST   = 3'b000;
  assign HPROT    = 4'b0011;
  assign HWRITE   = m_wb_we_o;
  assign HWDATA   = m_wb_dat_o;

  assign m_wb_dat_i = HRDATA;
  assign m_wb_ack_i = HREADY;
  assign m_wb_err_i = HRESP[0];

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
    .wb_adr_i       (PADDR),
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
