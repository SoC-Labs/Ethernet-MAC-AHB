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

  // RMII Interface
  input  wire        rmii_ref_clk,    // 50 MHz reference clock
  output wire  [1:0] rmii_txd,        // Transmit data (2-bit)
  output wire        rmii_tx_en,      // Transmit enable
  input  wire  [1:0] rmii_rxd,        // Receive data (2-bit)
  input  wire        rmii_crs_dv,     // Carrier sense / receive data valid

  // Link speed select (quasi-static). 1 = 100 Mbps, 0 = 10 Mbps.
  // Tie high when the PHY only ever runs at 100 Mbps.
  input  wire        mode_speed,

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
    .RESETn         (hresetn),
    .mode_speed     (mode_speed),

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
    .hclk           (hclk),
    .hresetn        (hresetn),

    // AHB Master
    .haddr          (haddr),
    .htrans         (htrans),
    .hsize          (hsize),
    .hburst         (hburst),
    .hprot          (hprot),
    .hmastlock      (hmastlock),
    .hwrite         (hwrite),
    .hwdata         (hwdata),
    .hrdata         (hrdata),
    .hready         (hready),
    .hresp          (hresp),

    // AHB Slave
    .hsel_s         (hsel_s),
    .haddr_s        (haddr_s),
    .htrans_s       (htrans_s),
    .hsize_s        (hsize_s),
    .hburst_s       (hburst_s),
    .hprot_s        (hprot_s),
    .hwrite_s       (hwrite_s),
    .hwdata_s       (hwdata_s),
    .hready_s       (hready_s),
    .hrdata_s       (hrdata_s),
    .hreadyout_s    (hreadyout_s),
    .hresp_s        (hresp_s),

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
