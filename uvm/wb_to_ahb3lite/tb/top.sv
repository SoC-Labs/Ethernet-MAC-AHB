///////////////////////////////////////////////////////////////////////////////
// top.sv
///////////////////////////////////////////////////////////////////////////////
// Top-level UVM testbench for the wb_to_ahb3lite bridge.
//
// Instantiates the DUT, Wishbone interface, Synopsys VIP AHB interface,
// and wires the DUT's AHB master outputs to the VIP's slave/monitor ports.
///////////////////////////////////////////////////////////////////////////////

`timescale 1ns/1ps

`include "uvm_pkg.sv"
`include "svt_ahb.uvm.pkg"
`include "svt_ahb_if.svi"

// Wishbone interface (must be outside module)
`include "wb_master_if.sv"

// Testbench package (must be outside module)
`include "wb_ahb_bridge_pkg.sv"

module test_top;

  // ---------------------------------------------------------------
  // Clock and reset
  // ---------------------------------------------------------------
  parameter CLK_PERIOD = 10; // 100 MHz

  bit clk;
  logic rst_n;

  initial begin
    clk = 1'b0;
    forever #(CLK_PERIOD/2) clk = ~clk;
  end

  initial begin
    rst_n = 1'b0;
    repeat (10) @(posedge clk);
    rst_n = 1'b1;
  end

  // ---------------------------------------------------------------
  // Package imports
  // ---------------------------------------------------------------
  import uvm_pkg::*;
  import svt_uvm_pkg::*;
  import svt_ahb_uvm_pkg::*;
  import wb_ahb_bridge_pkg::*;

  // ---------------------------------------------------------------
  // Wishbone interface instance
  // ---------------------------------------------------------------
  wb_master_if wb_if(.clk(clk), .rst_n(rst_n));

  // ---------------------------------------------------------------
  // Synopsys VIP AHB interface instance
  // ---------------------------------------------------------------
  svt_ahb_if ahb_if();
  assign ahb_if.hclk    = clk;
  assign ahb_if.hresetn = rst_n;

  // ---------------------------------------------------------------
  // DUT instantiation
  // ---------------------------------------------------------------
  // Intermediate wires for AHB master outputs
  wire        dut_hsel;
  wire [2:0]  dut_hsize;
  wire        dut_hwrite;
  wire [2:0]  dut_hburst;
  wire [31:0] dut_haddr;
  wire [1:0]  dut_htrans;
  wire [31:0] dut_hwdata;
  wire [3:0]  dut_hprot;
  wire        dut_hreadyout;

  // AHB slave responses (from VIP back to DUT)
  wire [31:0] dut_hrdata;
  wire        dut_hresp;
  wire        dut_hready;

  wb_to_ahb3lite u_dut (
    .clk_i            (clk),
    .rst_n_i          (rst_n),

    // Wishbone master side
    .from_m_wb_adr_o  (wb_if.adr),
    .from_m_wb_sel_o  (wb_if.sel),
    .from_m_wb_we_o   (wb_if.we),
    .from_m_wb_dat_o  (wb_if.dat_o),
    .from_m_wb_cyc_o  (wb_if.cyc),
    .from_m_wb_stb_o  (wb_if.stb),
    .to_m_wb_ack_i    (wb_if.ack),
    .to_m_wb_err_i    (wb_if.err),
    .to_m_wb_dat_i    (wb_if.dat_i),
    .from_m_wb_cti_o  (wb_if.cti),
    .from_m_wb_bte_o  (wb_if.bte),

    // AHB3-Lite master side
    .mHSEL            (dut_hsel),
    .mHSIZE           (dut_hsize),
    .mHRDATA          (dut_hrdata),
    .mHRESP           (dut_hresp),
    .mHREADY          (dut_hready),
    .mHREADYOUT       (dut_hreadyout),
    .mHWRITE          (dut_hwrite),
    .mHBURST          (dut_hburst),
    .mHADDR           (dut_haddr),
    .mHTRANS          (dut_htrans),
    .mHWDATA          (dut_hwdata),
    .mHPROT           (dut_hprot)
  );

  // ---------------------------------------------------------------
  // Signal mapping: DUT AHB master outputs -> VIP slave interface
  //
  // With SVT_AHB_DISABLE_IMPLICIT_BUS_CONNECTION, we explicitly
  // connect the DUT (which is the AHB master) to the VIP's slave
  // port and passive master monitor.
  // ---------------------------------------------------------------

  // DUT master outputs -> VIP slave_if[0] inputs (what the slave sees)
  assign ahb_if.slave_if[0].haddr    = dut_haddr;
  assign ahb_if.slave_if[0].htrans   = dut_htrans;
  assign ahb_if.slave_if[0].hburst   = dut_hburst;
  assign ahb_if.slave_if[0].hsize    = dut_hsize;
  assign ahb_if.slave_if[0].hprot    = dut_hprot;
  assign ahb_if.slave_if[0].hwrite   = dut_hwrite;
  assign ahb_if.slave_if[0].hwdata   = dut_hwdata;
  assign ahb_if.slave_if[0].hsel     = dut_hsel;
  assign ahb_if.slave_if[0].hmaster  = 4'h0;
  assign ahb_if.slave_if[0].hmastlock = 1'b0;

  // VIP slave_if[0] hready feeds back to the slave's own hready_in
  assign ahb_if.slave_if[0].hready_in = ahb_if.slave_if[0].hready;

  // VIP slave outputs -> DUT AHB inputs
  assign dut_hrdata = ahb_if.slave_if[0].hrdata;
  assign dut_hresp  = ahb_if.slave_if[0].hresp[0]; // VIP hresp may be wider
  assign dut_hready = ahb_if.slave_if[0].hready;

  // DUT master outputs -> VIP master_if[0] (passive monitor)
  // Use force to override the VIP clocking block output drivers on
  // master_if signals, which cannot coexist with assign or always_comb.
  initial begin
    force ahb_if.master_if[0].haddr   = dut_haddr;
    force ahb_if.master_if[0].htrans  = dut_htrans;
    force ahb_if.master_if[0].hburst  = dut_hburst;
    force ahb_if.master_if[0].hsize   = dut_hsize;
    force ahb_if.master_if[0].hprot   = dut_hprot;
    force ahb_if.master_if[0].hwrite  = dut_hwrite;
    force ahb_if.master_if[0].hwdata  = dut_hwdata;
    force ahb_if.master_if[0].hlock   = 1'b0;  // AHB-Lite: no lock
    force ahb_if.master_if[0].hgrant  = 1'b1;  // AHB-Lite: always granted
    force ahb_if.master_if[0].hready  = dut_hready;
    force ahb_if.master_if[0].hresp   = ahb_if.slave_if[0].hresp;
    force ahb_if.master_if[0].hrdata  = dut_hrdata;
  end

  // ---------------------------------------------------------------
  // SVA property binding
  // ---------------------------------------------------------------
  wb_to_ahb3lite_props u_props (
    .clk            (clk),
    .rst_n          (rst_n),
    .htrans         (dut_htrans),
    .hburst         (dut_hburst),
    .haddr          (dut_haddr),
    .hwrite         (dut_hwrite),
    .hsize          (dut_hsize),
    .hprot          (dut_hprot),
    .hwdata         (dut_hwdata),
    .hready         (dut_hready),
    .hresp          (dut_hresp),
    .hrdata         (dut_hrdata),
    .wb_cyc         (wb_if.cyc),
    .wb_stb         (wb_if.stb),
    .wb_ack         (wb_if.ack),
    .wb_err         (wb_if.err),
    .wb_cti         (wb_if.cti),
    .state          (u_dut.state)
  );

  // ---------------------------------------------------------------
  // Debug: print AHB write data timing (strobe = after all updates)
  // ---------------------------------------------------------------
  always @(posedge clk) begin
    if (rst_n && $time >= 230 && $time <= 360)
      $strobe("DBG T=%0t ST=%0d HTRANS=%b HADDR=%h DUT_HWDATA=%h WB_ADR=%h WB_DAT_O=%h HSEL=%b CYC=%b STB=%b ACK=%b",
               $time, u_dut.state, dut_htrans, dut_haddr, dut_hwdata, wb_if.adr, wb_if.dat_o, dut_hsel, wb_if.cyc, wb_if.stb, wb_if.ack);
  end

  // ---------------------------------------------------------------
  // Waveform dumping
  // ---------------------------------------------------------------
`ifdef WAVES_FSDB
  initial begin
    $fsdbDumpfile("test_top");
    $fsdbDumpvars;
  end
`elsif WAVES_VCD
  initial begin
    $dumpfile("test_top.vcd");
    $dumpvars(0, test_top);
  end
`elsif WAVES
  initial begin
    $vcdpluson;
  end
`endif

  // ---------------------------------------------------------------
  // UVM configuration and test launch
  // ---------------------------------------------------------------
  initial begin
    // Set VIP AHB interface
    uvm_config_db#(svt_ahb_vif)::set(uvm_root::get(),
      "uvm_test_top.env.ahb_sys_env", "vif", ahb_if);

    // Set WB interface for driver and monitor
    uvm_config_db#(virtual wb_master_if.driver)::set(uvm_root::get(),
      "uvm_test_top.env.wb_agt.driver", "vif", wb_if.driver);
    uvm_config_db#(virtual wb_master_if.monitor)::set(uvm_root::get(),
      "uvm_test_top.env.wb_agt.monitor", "vif", wb_if.monitor);

    // Plain virtual interface for clock/reset access in tests
    uvm_config_db#(virtual wb_master_if)::set(uvm_root::get(),
      "uvm_test_top", "vif", wb_if);

    run_test();
  end

endmodule
