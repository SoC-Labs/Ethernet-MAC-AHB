//-----------------------------------------------------------------------------
// ethmac_ahb.v
//-----------------------------------------------------------------------------
// Wrapper for OpenCores Ethernet MAC (eth_top) with AHB master and AHB slave
// interfaces, replacing the original WISHBONE interfaces.
//
// Uses bridge IP (originally from github.com/vfinotti/ahb3lite_wb_bridge) for protocol conversion:
// - AHB slave  -> WB slave  (register access) via ahb3lite_to_wb
// - WB master  -> AHB master (DMA transfers)  via wb_to_ahb3lite
//-----------------------------------------------------------------------------

module ethmac_ahb #(
  // Byte-swap the MAC's DMA data path so in-memory frame bytes match
  // the on-wire byte order when paired with a little-endian CPU. The
  // OpenCores ethmac stores bytes big-endian within each 32-bit word
  // (first wire byte in bits [31:24]); a LE CPU reading that memory
  // sees every word reversed, mangling every field past the dst MAC.
  //
  // Default 0 (swap disabled) keeps the historical byte layout that
  // the cocotb DMA tests under this repo were written against — they
  // compensate for the reversal in software with an explicit word
  // un-swap ([w[3],w[2],w[1],w[0]]). Firmware that expects in-memory
  // bytes in wire order (e.g. the PicoTCP stack in the PYNQ Ethernet
  // subsystem) should override to 1 at instantiation:
  //     ethmac_ahb #(.SWAP_DMA_BYTES(1'b1)) u_eth ( ... );
  parameter SWAP_DMA_BYTES = 1'b0
)(
  // Clock and Reset
  input  wire        hclk,
  input  wire        hresetn,

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

  //---------------------------------------------------
  // WISHBONE Master to AHB Master Bridge (DMA)
  //---------------------------------------------------
  wb_to_ahb3lite #(
    .SWAP_DMA_BYTES (SWAP_DMA_BYTES)
  ) u_wb_to_ahb3lite (
    .clk_i              (hclk),
    .rst_n_i            (hresetn),

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
  // Ethernet MAC Core Instance
  //---------------------------------------------------
  eth_top u_eth_top (
    // WISHBONE common
    .wb_clk_i       (hclk),
    .wb_rst_i       (~hresetn),
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
