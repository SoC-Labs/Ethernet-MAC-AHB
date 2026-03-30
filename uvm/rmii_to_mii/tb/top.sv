///////////////////////////////////////////////////////////////////////////////
// top.sv
///////////////////////////////////////////////////////////////////////////////
// Top-level UVM testbench for the rmii_to_mii adapter.
//
// Instantiates the DUT, MII interface, RMII interface, generates the
// 50 MHz RMII reference clock and reset, and wires everything together.
///////////////////////////////////////////////////////////////////////////////

`timescale 1ns/1ps

`include "uvm_pkg.sv"

// Interfaces (must be outside module)
`include "mii_if.sv"
`include "rmii_if.sv"

// Testbench package (must be outside module)
`include "rmii_mii_pkg.sv"

module test_top;

  // ---------------------------------------------------------------
  // Clock and reset
  // ---------------------------------------------------------------
  parameter REF_CLK_PERIOD = 20; // 50 MHz = 20 ns

  bit   ref_clk;
  logic rst_n;

  initial begin
    ref_clk = 1'b0;
    forever #(REF_CLK_PERIOD/2) ref_clk = ~ref_clk;
  end

  initial begin
    rst_n = 1'b0;
    repeat (10) @(posedge ref_clk);
    rst_n = 1'b1;
  end

  // ---------------------------------------------------------------
  // Package imports
  // ---------------------------------------------------------------
  import uvm_pkg::*;
  import rmii_mii_pkg::*;

  // ---------------------------------------------------------------
  // DUT output wires for MII clocks
  // ---------------------------------------------------------------
  wire mtx_clk_w;
  wire mrx_clk_w;

  // ---------------------------------------------------------------
  // Interface instances
  // ---------------------------------------------------------------
  mii_if  mii_vif  (.mtx_clk(mtx_clk_w), .mrx_clk(mrx_clk_w), .rst_n(rst_n));
  rmii_if rmii_vif (.rmii_ref_clk(ref_clk), .rst_n(rst_n), .phase_ref(mrx_clk_w));

  // ---------------------------------------------------------------
  // DUT instantiation
  // ---------------------------------------------------------------
  rmii_to_mii u_dut (
    .RESETn       (rst_n),

    // RMII side
    .rmii_ref_clk (ref_clk),
    .rmii_txd     (rmii_vif.rmii_txd),
    .rmii_tx_en   (rmii_vif.rmii_tx_en),
    .rmii_rxd     (rmii_vif.rmii_rxd),
    .rmii_crs_dv  (rmii_vif.rmii_crs_dv),

    // MII side
    .mtx_clk      (mtx_clk_w),
    .mtxd         (mii_vif.mtxd),
    .mtxen        (mii_vif.mtxen),
    .mtxerr       (mii_vif.mtxerr),
    .mrx_clk      (mrx_clk_w),
    .mrxd         (mii_vif.mrxd),
    .mrxdv        (mii_vif.mrxdv),
    .mrxerr       (mii_vif.mrxerr),
    .mcoll        (mii_vif.mcoll),
    .mcrs         (mii_vif.mcrs)
  );

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
  // Debug: monitor DUT internals
  // ---------------------------------------------------------------
`ifdef DEBUG_RX
  initial begin
    @(posedge rst_n);
    repeat (30) begin
      @(posedge ref_clk);
      #1;
      $display("T=%0t rx_phase=%0b clk_div2=%0b rmii_rxd=%02b crs_dv=%0b | mrxd=%04b mrxdv=%0b | rxd_low=%02b dv_held=%0b",
        $time, u_dut.rx_phase, u_dut.clk_div2, u_dut.rmii_rxd, u_dut.rmii_crs_dv,
        u_dut.mrxd, u_dut.mrxdv, u_dut.rx_data_low, u_dut.rx_dv_held);
    end
  end
`endif

  // ---------------------------------------------------------------
  // UVM configuration and test launch
  // ---------------------------------------------------------------
  initial begin
    // MII interface for TX driver
    uvm_config_db#(virtual mii_if.tx_driver)::set(uvm_root::get(),
      "uvm_test_top.env.mii_agt.tx_driver", "vif", mii_vif.tx_driver);

    // MII interface for RX monitor
    uvm_config_db#(virtual mii_if.rx_monitor)::set(uvm_root::get(),
      "uvm_test_top.env.mii_agt.rx_monitor", "vif", mii_vif.rx_monitor);

    // RMII interface for TX monitor
    uvm_config_db#(virtual rmii_if.tx_monitor)::set(uvm_root::get(),
      "uvm_test_top.env.rmii_agt.tx_monitor", "vif", rmii_vif.tx_monitor);

    // RMII interface for RX driver
    uvm_config_db#(virtual rmii_if.rx_driver)::set(uvm_root::get(),
      "uvm_test_top.env.rmii_agt.rx_driver", "vif", rmii_vif.rx_driver);

    // Plain RMII interface for clock/reset access in tests
    uvm_config_db#(virtual rmii_if)::set(uvm_root::get(),
      "uvm_test_top", "rmii_vif", rmii_vif);

    // MII RX monitor interface for collision test
    uvm_config_db#(virtual mii_if.rx_monitor)::set(uvm_root::get(),
      "uvm_test_top", "mii_rx_vif", mii_vif.rx_monitor);

    run_test();
  end

endmodule
