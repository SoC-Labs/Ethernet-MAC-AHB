//-----------------------------------------------------------------------------
// tb_ethmac_ahb.v
//-----------------------------------------------------------------------------
// Cocotb testbench wrapper for ethmac_ahb.
//
// Provides signal prefix remapping so that cocotbext-ahb bus models can bind:
//   - "slv_*" prefix  -> AHB slave port  (register access, driven by AHBLiteMaster)
//   - "mst_*" prefix  -> AHB master port (DMA, responded to by AHBLiteSlaveRAM)
//
// MII and control signals keep their original names.
//-----------------------------------------------------------------------------

`timescale 1ns / 1ps

module tb_ethmac_ahb_swap;

  // -------------------------------------------------------
  // Clock and Reset
  // -------------------------------------------------------
  reg         hclk;
  reg         hresetn = 0;

  // -------------------------------------------------------
  // AHB Master Port (DMA) — prefix "mst_"
  // Outputs from DUT (wire), inputs to DUT (reg)
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
  // AHB Slave Port (Register Access) — prefix "slv_"
  // Inputs to DUT (reg), outputs from DUT (wire)
  // -------------------------------------------------------
  reg         slv_hsel;
  reg  [31:0] slv_haddr;
  reg   [1:0] slv_htrans;
  reg   [2:0] slv_hsize;
  reg   [2:0] slv_hburst;
  reg   [3:0] slv_hprot;
  reg         slv_hwrite;
  reg  [31:0] slv_hwdata;
  wire [31:0] slv_hrdata_raw;
  wire [31:0] slv_hrdata;
  wire        slv_hready;

  // Ensure hrdata is always resolvable (replace X with 0)
  assign slv_hrdata = (^slv_hrdata_raw === 1'bx) ? 32'h0 : slv_hrdata_raw;

  // In a single-slave system, hready_in = hreadyout (feedback)
  // Not exposed to cocotb to avoid driver conflicts
  wire        slv_hready_mux;
  assign slv_hready_mux = slv_hready;
  wire        slv_hresp;

  // -------------------------------------------------------
  // MII Transmit (outputs from DUT, tx_clk input from PHY)
  // -------------------------------------------------------
  reg         mtx_clk_pad_i = 0;
  wire  [3:0] mtxd_pad_o;
  wire        mtxen_pad_o;
  wire        mtxerr_pad_o;

  // -------------------------------------------------------
  // MII Receive (inputs to DUT from PHY)
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
  ethmac_ahb #(.SWAP_DMA_BYTES(1'b1)) u_dut (
    // Clock and Reset
    .hclk             (hclk),
    .hresetn          (hresetn),

    // AHB Master Port (DMA)
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

    // AHB Slave Port (Register Access)
    .hsel_s           (slv_hsel),
    .haddr_s          (slv_haddr),
    .htrans_s         (slv_htrans),
    .hsize_s          (slv_hsize),
    .hburst_s         (slv_hburst),
    .hprot_s          (slv_hprot),
    .hwrite_s         (slv_hwrite),
    .hwdata_s         (slv_hwdata),
    .hready_s         (slv_hready_mux),
    .hrdata_s         (slv_hrdata_raw),
    .hreadyout_s      (slv_hready),
    .hresp_s          (slv_hresp),

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
    .int_o            (int_o)
  );

  // -------------------------------------------------------
  // Dump waveforms (VCD)
  // -------------------------------------------------------
  initial begin
    $dumpfile("tb_ethmac_ahb_swap.vcd");
    $dumpvars(0, tb_ethmac_ahb_swap);
  end

  // -------------------------------------------------------
  // Initialise MII common inputs to avoid X during reset
  // -------------------------------------------------------
  initial begin
    mcoll_pad_i = 0;
    mcrs_pad_i  = 0;
    md_pad_i    = 1;   // MDIO idle high
  end

  // MII clocks (mtx_clk_pad_i, mrx_clk_pad_i) are driven by cocotb.
  // Inverted TX clock: MiiSink samples on rising edge of this = falling
  // edge of mtx_clk_pad_i, so MAC NBA outputs have settled.
  wire mtx_clk_inv = ~mtx_clk_pad_i;

  // Inverted RX clock: MiiSource drives data on rising edge of this =
  // falling edge of mrx_clk_pad_i, giving setup time before next posedge.
  wire mrx_clk_inv = ~mrx_clk_pad_i;

endmodule
