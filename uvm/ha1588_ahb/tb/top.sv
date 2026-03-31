///////////////////////////////////////////////////////////////////////////////
// top.sv
///////////////////////////////////////////////////////////////////////////////
// Top-level UVM testbench for the ha1588_ahb IEEE 1588 PTP wrapper.
//
// The DUT is an AHB slave (register access only, no DMA master).
// VIP active master drives AHB stimulus; a register-model scoreboard
// verifies read/write correctness.
///////////////////////////////////////////////////////////////////////////////

`timescale 1ns/1ps

`include "uvm_pkg.sv"
`include "svt_ahb.uvm.pkg"
`include "svt_ahb_if.svi"

// Testbench package
`include "ha1588_ahb_pkg.sv"

module test_top;

  // ---------------------------------------------------------------
  // Clock and reset
  // ---------------------------------------------------------------
  parameter CLK_PERIOD     = 10; // 100 MHz (hclk)
  parameter RTC_CLK_PERIOD = 8;  // 125 MHz (rtc_clk)

  bit   clk;
  bit   rtc_clk;
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
  import ha1588_ahb_pkg::*;

  // ---------------------------------------------------------------
  // Synopsys VIP AHB interface instance
  // ---------------------------------------------------------------
  svt_ahb_if ahb_if();
  assign ahb_if.hclk    = clk;
  assign ahb_if.hresetn = rst_n;

  // ---------------------------------------------------------------
  // DUT AHB slave side signals
  // ---------------------------------------------------------------
  wire        dut_hreadyout;
  wire [31:0] dut_hrdata;
  wire        dut_hresp;

  // ---------------------------------------------------------------
  // DUT instantiation
  // ---------------------------------------------------------------
  ha1588_ahb u_dut (
    .hclk             (clk),
    .hresetn          (rst_n),

    // AHB Slave (VIP master drives these)
    .hsel_s           (1'b1),
    .haddr_s          (ahb_if.master_if[0].haddr),
    .htrans_s         (ahb_if.master_if[0].htrans),
    .hsize_s          (ahb_if.master_if[0].hsize),
    .hburst_s         (ahb_if.master_if[0].hburst),
    .hprot_s          (ahb_if.master_if[0].hprot),
    .hwrite_s         (ahb_if.master_if[0].hwrite),
    .hwdata_s         (ahb_if.master_if[0].hwdata[31:0]),
    .hready_s         (ahb_if.master_if[0].hready),
    .hrdata_s         (dut_hrdata),
    .hreadyout_s      (dut_hreadyout),
    .hresp_s          (dut_hresp),

    // RTC clock
    .rtc_clk          (rtc_clk),

    // RTC outputs (directly observable)
    .rtc_time_ptp_ns  (),
    .rtc_time_ptp_sec (),
    .rtc_time_one_pps (),

    // GMII monitoring (tied off for register-level tests)
    .rx_gmii_clk      (1'b0),
    .rx_gmii_ctrl     (1'b0),
    .rx_gmii_data     (8'h0),
    .rx_giga_mode     (1'b0),
    .tx_gmii_clk      (1'b0),
    .tx_gmii_ctrl     (1'b0),
    .tx_gmii_data     (8'h0),
    .tx_giga_mode     (1'b0)
  );

  // ---------------------------------------------------------------
  // Signal mapping: DUT AHB slave outputs -> VIP for handshaking
  // ---------------------------------------------------------------
  assign ahb_if.slave_if[0].haddr     = ahb_if.master_if[0].haddr;
  assign ahb_if.slave_if[0].htrans    = ahb_if.master_if[0].htrans;
  assign ahb_if.slave_if[0].hburst    = ahb_if.master_if[0].hburst;
  assign ahb_if.slave_if[0].hsize     = ahb_if.master_if[0].hsize;
  assign ahb_if.slave_if[0].hprot     = ahb_if.master_if[0].hprot;
  assign ahb_if.slave_if[0].hwrite    = ahb_if.master_if[0].hwrite;
  assign ahb_if.slave_if[0].hwdata    = ahb_if.master_if[0].hwdata;
  assign ahb_if.slave_if[0].hmaster   = 4'h0;
  assign ahb_if.slave_if[0].hmastlock = 1'b0;
  assign ahb_if.slave_if[0].hready_in = dut_hreadyout;

  // Force DUT slave responses onto master_if for proper VIP handshaking
  initial begin
    force ahb_if.master_if[0].hready = dut_hreadyout;
    force ahb_if.master_if[0].hresp  = {1'b0, dut_hresp};
    force ahb_if.master_if[0].hrdata = dut_hrdata;
    force ahb_if.master_if[0].hgrant = 1'b1;

    force ahb_if.slave_if[0].hsel    = 1'b1;
    force ahb_if.slave_if[0].hready  = dut_hreadyout;
    force ahb_if.slave_if[0].hrdata  = dut_hrdata;
    force ahb_if.slave_if[0].hresp   = {1'b0, dut_hresp};
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

    // Pass clock for test reset synchronisation
    uvm_config_db#(virtual svt_ahb_if)::set(uvm_root::get(),
      "uvm_test_top", "ahb_vif", ahb_if);

    run_test();
  end

endmodule
