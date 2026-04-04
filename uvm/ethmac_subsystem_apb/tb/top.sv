///////////////////////////////////////////////////////////////////////////////
// top.sv
///////////////////////////////////////////////////////////////////////////////
// Top-level UVM testbench for ethmac_subsystem_apb.
//
// Uses SVT APB VIP (active master) for register access and SVT AHB VIP
// (active slave) for DMA response. GMII/MII signals are tied off for
// register-level tests; data-path tests drive them via force/release.
///////////////////////////////////////////////////////////////////////////////

`timescale 1ns/1ps

`include "uvm_pkg.sv"
`include "svt_apb.uvm.pkg"
`include "svt_apb_if.svi"
`include "svt_ahb.uvm.pkg"
`include "svt_ahb_if.svi"

`include "subsystem_dut_if.sv"
`include "ethmac_subsystem_apb_pkg.sv"

module test_top;

  // ---------------------------------------------------------------
  // Clock and reset
  // ---------------------------------------------------------------
  parameter CLK_PERIOD     = 10;  // 100 MHz
  parameter RTC_CLK_PERIOD = 8;   // 125 MHz
  parameter MII_CLK_PERIOD = 40;  // 25 MHz

  bit   clk;
  bit   rtc_clk;
  bit   mtx_clk, mrx_clk;
  logic rst_n;

  initial begin
    clk = 1'b0;
    forever #(CLK_PERIOD/2) clk = ~clk;
  end

  initial begin
    rtc_clk = 1'b0;
    forever #(RTC_CLK_PERIOD/2) rtc_clk = ~rtc_clk;
  end

  initial begin
    mtx_clk = 1'b0;
    mrx_clk = 1'b0;
    forever begin
      #(MII_CLK_PERIOD/2);
      mtx_clk = ~mtx_clk;
      mrx_clk = ~mrx_clk;
    end
  end

  initial begin
    rst_n = 1'b0;
    repeat (10) @(posedge clk);
    rst_n = 1'b1;
  end

  // ---------------------------------------------------------------
  // Imports
  // ---------------------------------------------------------------
  import uvm_pkg::*;
  import svt_uvm_pkg::*;
  import svt_apb_uvm_pkg::*;
  import svt_ahb_uvm_pkg::*;
  import ethmac_subsystem_apb_pkg::*;

  // ---------------------------------------------------------------
  // SVT APB interface (master drives DUT's APB slave port)
  // ---------------------------------------------------------------
  svt_apb_if apb_if();
  assign apb_if.pclk    = clk;
  assign apb_if.presetn = rst_n;

  // ---------------------------------------------------------------
  // SVT AHB interface (slave responds to DUT's AHB DMA master)
  // ---------------------------------------------------------------
  svt_ahb_if ahb_if();
  assign ahb_if.hclk    = clk;
  assign ahb_if.hresetn = rst_n;

  // ---------------------------------------------------------------
  // DUT signals
  // ---------------------------------------------------------------
  wire        dut_pready, dut_pslverr;
  wire [31:0] dut_prdata;

  wire [31:0] dut_haddr;
  wire  [1:0] dut_htrans;
  wire  [2:0] dut_hsize, dut_hburst;
  wire  [3:0] dut_hprot;
  wire        dut_hmastlock, dut_hwrite;
  wire [31:0] dut_hwdata;

  wire [31:0] rtc_time_ptp_ns;
  wire [47:0] rtc_time_ptp_sec;
  wire        rtc_time_one_pps;

  wire  [3:0] mtxd_pad_o;
  wire        mtxen_pad_o, mtxerr_pad_o;
  wire        mdc_pad_o, md_pad_o, md_padoe_o;
  wire        int_o;

  // ---------------------------------------------------------------
  // DUT instantiation
  // ---------------------------------------------------------------
  ethmac_subsystem_apb u_dut (
    .pclk             (clk),
    .presetn          (rst_n),

    // AHB Master (DMA)
    .haddr            (dut_haddr),
    .htrans           (dut_htrans),
    .hsize            (dut_hsize),
    .hburst           (dut_hburst),
    .hprot            (dut_hprot),
    .hmastlock        (dut_hmastlock),
    .hwrite           (dut_hwrite),
    .hwdata           (dut_hwdata),
    .hrdata           (ahb_if.slave_if[0].hrdata),
    .hready           (ahb_if.slave_if[0].hready),
    .hresp            (ahb_if.slave_if[0].hresp[0]),

    // APB Slave (Registers)
    .psel             (apb_if.psel[0]),
    .penable          (apb_if.penable),
    .paddr            (apb_if.paddr),
    .pwrite           (apb_if.pwrite),
    .pwdata           (apb_if.pwdata),
    .pstrb            (apb_if.pstrb),
    .prdata           (dut_prdata),
    .pready           (dut_pready),
    .pslverr          (dut_pslverr),

    // RTC
    .rtc_clk          (rtc_clk),
    .rtc_time_ptp_ns  (rtc_time_ptp_ns),
    .rtc_time_ptp_sec (rtc_time_ptp_sec),
    .rtc_time_one_pps (rtc_time_one_pps),

    // MII TX
    .mtx_clk_pad_i    (mtx_clk),
    .mtxd_pad_o       (mtxd_pad_o),
    .mtxen_pad_o      (mtxen_pad_o),
    .mtxerr_pad_o     (mtxerr_pad_o),

    // MII RX (tied off for register tests)
    .mrx_clk_pad_i    (mrx_clk),
    .mrxd_pad_i       (4'h0),
    .mrxdv_pad_i      (1'b0),
    .mrxerr_pad_i     (1'b0),

    // MII Common
    .mcoll_pad_i      (1'b0),
    .mcrs_pad_i       (1'b0),

    // MDIO
    .md_pad_i         (1'b1),
    .mdc_pad_o        (mdc_pad_o),
    .md_pad_o         (md_pad_o),
    .md_padoe_o       (md_padoe_o),

    // Interrupt
    .int_o            (int_o)
  );

  // ---------------------------------------------------------------
  // APB VIP: force DUT responses onto slave sub-interface for VIP
  // (VIP master reads from slave_if[0], not the top-level arrays)
  // ---------------------------------------------------------------
  initial begin
    force apb_if.slave_if[0].pready  = dut_pready;
    force apb_if.slave_if[0].prdata  = dut_prdata;
    force apb_if.slave_if[0].pslverr = dut_pslverr;
  end

  // ---------------------------------------------------------------
  // AHB VIP: DUT master outputs → VIP slave_if and passive master_if
  // Under xprop, idle AHB master outputs can be X (DMA path
  // uninitialised). Present IDLE bus state when signals are unknown.
  // ---------------------------------------------------------------
  wire ahb_valid = rst_n & ~(^dut_htrans === 1'bx);

  assign ahb_if.slave_if[0].haddr     = ahb_valid ? dut_haddr     : 32'h0;
  assign ahb_if.slave_if[0].htrans    = ahb_valid ? dut_htrans    : 2'b00;
  assign ahb_if.slave_if[0].hburst    = ahb_valid ? dut_hburst    : 3'b000;
  assign ahb_if.slave_if[0].hsize     = ahb_valid ? dut_hsize     : 3'b010;
  assign ahb_if.slave_if[0].hprot     = ahb_valid ? dut_hprot     : 4'h0;
  assign ahb_if.slave_if[0].hwrite    = ahb_valid ? dut_hwrite    : 1'b0;
  assign ahb_if.slave_if[0].hwdata    = ahb_valid ? dut_hwdata    : 32'h0;
  assign ahb_if.slave_if[0].hmaster   = 4'h0;
  assign ahb_if.slave_if[0].hmastlock = ahb_valid ? dut_hmastlock : 1'b0;
  assign ahb_if.slave_if[0].hready_in = ahb_if.slave_if[0].hready;

  initial begin
    // Mirror gated DUT master outputs onto passive master_if for monitoring
    force ahb_if.master_if[0].haddr     = ahb_if.slave_if[0].haddr;
    force ahb_if.master_if[0].htrans    = ahb_if.slave_if[0].htrans;
    force ahb_if.master_if[0].hburst    = ahb_if.slave_if[0].hburst;
    force ahb_if.master_if[0].hsize     = ahb_if.slave_if[0].hsize;
    force ahb_if.master_if[0].hprot     = ahb_if.slave_if[0].hprot;
    force ahb_if.master_if[0].hwrite    = ahb_if.slave_if[0].hwrite;
    force ahb_if.master_if[0].hwdata    = ahb_if.slave_if[0].hwdata;
    force ahb_if.master_if[0].hlock     = ahb_if.slave_if[0].hmastlock;

    // Slave responses → passive master (gate hrdata to avoid X from uninitialised memory)
    force ahb_if.master_if[0].hready = ahb_if.slave_if[0].hready;
    force ahb_if.master_if[0].hresp  = ahb_if.slave_if[0].hresp;
    force ahb_if.master_if[0].hrdata = (^ahb_if.slave_if[0].hrdata === 1'bx) ? 32'h0 : ahb_if.slave_if[0].hrdata;
    force ahb_if.master_if[0].hgrant = 1'b1;

    force ahb_if.slave_if[0].hsel = ahb_valid & |dut_htrans;
  end

  // ---------------------------------------------------------------
  // DUT observability interface (package-safe access for tests)
  // ---------------------------------------------------------------
  subsystem_dut_if dut_if (
    .clk             (clk),
    .rst_n           (rst_n),
    .int_o           (int_o),
    .htrans          (dut_htrans),
    .rtc_time_ptp_ns (rtc_time_ptp_ns)
  );

  // ---------------------------------------------------------------
  // Waveform dumping
  // ---------------------------------------------------------------
`ifdef WAVES_VCD
  initial begin
    $dumpfile("test_top.vcd");
    $dumpvars(0, test_top);
  end
`endif

  // ---------------------------------------------------------------
  // UVM configuration and test launch
  // ---------------------------------------------------------------
  initial begin
    uvm_config_db#(svt_apb_vif)::set(uvm_root::get(),
      "uvm_test_top.env.apb_sys_env", "vif", apb_if);

    uvm_config_db#(svt_ahb_vif)::set(uvm_root::get(),
      "uvm_test_top.env.ahb_sys_env", "vif", ahb_if);

    uvm_config_db#(virtual svt_apb_if)::set(uvm_root::get(),
      "uvm_test_top", "apb_vif", apb_if);

    uvm_config_db#(virtual svt_ahb_if)::set(uvm_root::get(),
      "uvm_test_top", "ahb_vif", ahb_if);

    uvm_config_db#(virtual subsystem_dut_if)::set(uvm_root::get(),
      "uvm_test_top", "dut_if", dut_if);

    run_test();
  end

endmodule
