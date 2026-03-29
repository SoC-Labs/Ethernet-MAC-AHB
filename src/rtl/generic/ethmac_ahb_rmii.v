//-----------------------------------------------------------------------------
// ethmac_ahb_rmii.v
//-----------------------------------------------------------------------------
// Top-level wrapper that combines ethmac_ahb with an RMII-to-MII adapter.
// Exposes AHB master, AHB slave, MIIM, and RMII interfaces externally.
//
// RMII (Reduced MII) uses:
//   - A single 50 MHz reference clock (instead of separate TX/RX clocks)
//   - 2-bit data paths (instead of 4-bit)
//   - CRS_DV multiplexed signal (instead of separate CRS and RxDV)
//-----------------------------------------------------------------------------

module ethmac_ahb_rmii (
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

  // RMII Interface
  input  wire        rmii_ref_clk,    // 50 MHz reference clock
  output wire  [1:0] rmii_txd,        // Transmit data (2-bit)
  output wire        rmii_tx_en,      // Transmit enable
  input  wire  [1:0] rmii_rxd,        // Receive data (2-bit)
  input  wire        rmii_crs_dv,     // Carrier sense / receive data valid

  // MII Management Interface (directly exposed)
  input  wire        md_pad_i,
  output wire        mdc_pad_o,
  output wire        md_pad_o,
  output wire        md_padoe_o,

  // Interrupt
  output wire        int_o
);

  //---------------------------------------------------
  // Internal MII wires (adapter <-> ethmac_ahb)
  //---------------------------------------------------
  wire        mtx_clk;
  wire  [3:0] mtxd;
  wire        mtxen;
  wire        mtxerr;

  wire        mrx_clk;
  wire  [3:0] mrxd;
  wire        mrxdv;
  wire        mrxerr;

  wire        mcoll;
  wire        mcrs;

  //---------------------------------------------------
  // RMII to MII Adapter
  //---------------------------------------------------
  rmii_to_mii u_rmii_to_mii (
    .RESETn         (HRESETn),

    // RMII side
    .rmii_ref_clk   (rmii_ref_clk),
    .rmii_txd       (rmii_txd),
    .rmii_tx_en     (rmii_tx_en),
    .rmii_rxd       (rmii_rxd),
    .rmii_crs_dv    (rmii_crs_dv),

    // MII side
    .mtx_clk        (mtx_clk),
    .mtxd           (mtxd),
    .mtxen          (mtxen),
    .mtxerr         (mtxerr),

    .mrx_clk        (mrx_clk),
    .mrxd           (mrxd),
    .mrxdv          (mrxdv),
    .mrxerr         (mrxerr),

    .mcoll          (mcoll),
    .mcrs           (mcrs)
  );

  //---------------------------------------------------
  // Ethernet MAC with AHB interfaces
  //---------------------------------------------------
  ethmac_ahb u_ethmac_ahb (
    // Clock and Reset
    .HCLK           (HCLK),
    .HRESETn        (HRESETn),

    // AHB Master
    .HADDR          (HADDR),
    .HTRANS         (HTRANS),
    .HSIZE          (HSIZE),
    .HBURST         (HBURST),
    .HPROT          (HPROT),
    .HMASTLOCK      (HMASTLOCK),
    .HWRITE         (HWRITE),
    .HWDATA         (HWDATA),
    .HRDATA         (HRDATA),
    .HREADY         (HREADY),
    .HRESP          (HRESP),

    // AHB Slave
    .HSEL_S         (HSEL_S),
    .HADDR_S        (HADDR_S),
    .HTRANS_S       (HTRANS_S),
    .HSIZE_S        (HSIZE_S),
    .HBURST_S       (HBURST_S),
    .HPROT_S        (HPROT_S),
    .HWRITE_S       (HWRITE_S),
    .HWDATA_S       (HWDATA_S),
    .HREADY_S       (HREADY_S),
    .HRDATA_S       (HRDATA_S),
    .HREADYOUT_S    (HREADYOUT_S),
    .HRESP_S        (HRESP_S),

    // MII Transmit
    .mtx_clk_pad_i  (mtx_clk),
    .mtxd_pad_o     (mtxd),
    .mtxen_pad_o    (mtxen),
    .mtxerr_pad_o   (mtxerr),

    // MII Receive
    .mrx_clk_pad_i  (mrx_clk),
    .mrxd_pad_i     (mrxd),
    .mrxdv_pad_i    (mrxdv),
    .mrxerr_pad_i   (mrxerr),

    // MII Common
    .mcoll_pad_i    (mcoll),
    .mcrs_pad_i     (mcrs),

    // MII Management
    .md_pad_i       (md_pad_i),
    .mdc_pad_o      (mdc_pad_o),
    .md_pad_o       (md_pad_o),
    .md_padoe_o     (md_padoe_o),

    // Interrupt
    .int_o          (int_o)
  );

endmodule
