///////////////////////////////////////////////////////////////////////////////
// top.sv
///////////////////////////////////////////////////////////////////////////////
// Top-level UVM testbench for the ahb3lite_to_wb bridge.
//
// Instantiates the DUT, Wishbone slave interface, Synopsys VIP AHB interface,
// and wires the DUT's AHB slave inputs from the VIP's master port and
// DUT's WB master outputs to the custom WB slave agent.
///////////////////////////////////////////////////////////////////////////////

`timescale 1ns/1ps

`include "uvm_pkg.sv"
`include "svt_ahb.uvm.pkg"
`include "svt_ahb_if.svi"

// Wishbone slave interface (must be outside module)
`include "wb_slave_if.sv"

// Testbench package (must be outside module)
`include "ahb_wb_bridge_pkg.sv"

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
  import ahb_wb_bridge_pkg::*;

  // ---------------------------------------------------------------
  // Wishbone slave interface instance
  // ---------------------------------------------------------------
  wb_slave_if wb_if(.clk(clk), .rst_n(rst_n));

  // ---------------------------------------------------------------
  // Synopsys VIP AHB interface instance
  // ---------------------------------------------------------------
  svt_ahb_if ahb_if();
  assign ahb_if.hclk    = clk;
  assign ahb_if.hresetn = rst_n;

  // ---------------------------------------------------------------
  // DUT instantiation
  // ---------------------------------------------------------------
  // DUT AHB slave side signals
  wire        dut_hreadyout;
  wire [31:0] dut_hrdata;
  wire        dut_hresp;

  // DUT Wishbone master side signals
  wire [31:0] dut_wb_dat_o;
  wire [31:0] dut_wb_adr;
  wire [3:0]  dut_wb_sel;
  wire        dut_wb_we;
  wire        dut_wb_cyc;
  wire        dut_wb_stb;

  ahb3lite_to_wb u_dut (
    .clk_i            (clk),
    .rst_n_i          (rst_n),

    // AHB3-Lite slave side (VIP master drives these)
    .sHADDR           (ahb_if.master_if[0].haddr),
    .sHWDATA          (ahb_if.master_if[0].hwdata),
    .sHWRITE          (ahb_if.master_if[0].hwrite),
    .sHSIZE           (ahb_if.master_if[0].hsize),
    .sHBURST          (ahb_if.master_if[0].hburst),
    .sHSEL            (ahb_if.master_if[0].hsel),
    .sHTRANS          (ahb_if.master_if[0].htrans),
    .sHREADY          (ahb_if.master_if[0].hready),
    .sHPROT           (ahb_if.master_if[0].hprot),
    .sHREADYOUT       (dut_hreadyout),
    .sHRDATA          (dut_hrdata),
    .sHRESP           (dut_hresp),

    // Wishbone master side (DUT drives these)
    .to_wb_dat_i      (dut_wb_dat_o),
    .to_wb_adr_i      (dut_wb_adr),
    .to_wb_sel_i      (dut_wb_sel),
    .to_wb_we_i       (dut_wb_we),
    .to_wb_cyc_i      (dut_wb_cyc),
    .to_wb_stb_i      (dut_wb_stb),
    .from_wb_dat_o    (wb_if.dat_i),
    .from_wb_ack_o    (wb_if.ack),
    .from_wb_err_o    (wb_if.err)
  );

  // ---------------------------------------------------------------
  // Signal mapping: DUT WB master outputs -> WB slave interface
  // ---------------------------------------------------------------
  assign wb_if.adr   = dut_wb_adr;
  assign wb_if.dat_o = dut_wb_dat_o;
  assign wb_if.sel   = dut_wb_sel;
  assign wb_if.we    = dut_wb_we;
  assign wb_if.cyc   = dut_wb_cyc;
  assign wb_if.stb   = dut_wb_stb;

  // ---------------------------------------------------------------
  // Signal mapping: DUT AHB slave outputs -> VIP slave_if[0] (passive monitor)
  // and back to VIP master as hready/hresp/hrdata
  // ---------------------------------------------------------------

  // DUT slave outputs -> VIP slave_if (passive monitor observes)
  assign ahb_if.slave_if[0].haddr     = ahb_if.master_if[0].haddr;
  assign ahb_if.slave_if[0].htrans    = ahb_if.master_if[0].htrans;
  assign ahb_if.slave_if[0].hburst    = ahb_if.master_if[0].hburst;
  assign ahb_if.slave_if[0].hsize     = ahb_if.master_if[0].hsize;
  assign ahb_if.slave_if[0].hprot     = ahb_if.master_if[0].hprot;
  assign ahb_if.slave_if[0].hwrite    = ahb_if.master_if[0].hwrite;
  assign ahb_if.slave_if[0].hwdata    = ahb_if.master_if[0].hwdata;
  assign ahb_if.slave_if[0].hsel      = 1'b1;
  assign ahb_if.slave_if[0].hmaster   = 4'h0;
  assign ahb_if.slave_if[0].hmastlock = 1'b0;

  // DUT HREADYOUT feeds back as slave_if hready
  assign ahb_if.slave_if[0].hready    = dut_hreadyout;
  assign ahb_if.slave_if[0].hready_in = dut_hreadyout;

  // Force DUT slave responses onto master_if for proper VIP master handshaking
  initial begin
    force ahb_if.master_if[0].hready = dut_hreadyout;
    force ahb_if.master_if[0].hresp  = {1'b0, dut_hresp};
    force ahb_if.master_if[0].hrdata = dut_hrdata;
    force ahb_if.master_if[0].hgrant = 1'b1;  // AHB-Lite: always granted
  end

  // Force slave_if response signals for passive slave monitor
  initial begin
    force ahb_if.slave_if[0].hrdata = dut_hrdata;
    force ahb_if.slave_if[0].hresp  = {1'b0, dut_hresp};
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

    // Set WB interface for slave driver and monitor
    uvm_config_db#(virtual wb_slave_if.driver)::set(uvm_root::get(),
      "uvm_test_top.env.wb_agt.driver", "vif", wb_if.driver);
    uvm_config_db#(virtual wb_slave_if.monitor)::set(uvm_root::get(),
      "uvm_test_top.env.wb_agt.monitor", "vif", wb_if.monitor);

    // Plain virtual interface for clock/reset access in tests
    uvm_config_db#(virtual wb_slave_if)::set(uvm_root::get(),
      "uvm_test_top", "vif", wb_if);

    run_test();
  end

endmodule
