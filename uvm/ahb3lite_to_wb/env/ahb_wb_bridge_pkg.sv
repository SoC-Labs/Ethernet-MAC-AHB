///////////////////////////////////////////////////////////////////////////////
// ahb_wb_bridge_pkg.sv
///////////////////////////////////////////////////////////////////////////////
// Package containing all UVM testbench components for the ahb3lite_to_wb
// bridge verification environment.
///////////////////////////////////////////////////////////////////////////////

`ifndef GUARD_AHB_WB_BRIDGE_PKG_SV
`define GUARD_AHB_WB_BRIDGE_PKG_SV

package ahb_wb_bridge_pkg;

  import uvm_pkg::*;
  `include "uvm_macros.svh"

  import svt_uvm_pkg::*;
  import svt_ahb_uvm_pkg::*;

  // ---------------------------------------------------------------
  // Wishbone slave agent
  // ---------------------------------------------------------------
  `include "wb_slave_transaction.sv"
  `include "wb_slave_driver.sv"
  `include "wb_slave_monitor.sv"
  `include "wb_slave_agent.sv"

  // ---------------------------------------------------------------
  // Environment
  // ---------------------------------------------------------------
  `include "ahb_wb_bridge_config.sv"
  `include "ahb_wb_bridge_scoreboard.sv"
  `include "ahb_wb_bridge_env.sv"

  // ---------------------------------------------------------------
  // Sequences
  // ---------------------------------------------------------------
  `include "ahb_single_write_sequence.sv"
  `include "ahb_single_read_sequence.sv"
  `include "ahb_write_read_sequence.sv"
  `include "ahb_back_to_back_sequence.sv"
  `include "ahb_mixed_sequence.sv"
  `include "ahb_gapping_sequence.sv"

  // ---------------------------------------------------------------
  // Tests
  // ---------------------------------------------------------------
  `include "ahb_wb_bridge_base_test.sv"
  `include "ahb_wb_bridge_single_test.sv"
  `include "ahb_wb_bridge_error_test.sv"
  `include "ahb_wb_bridge_wait_state_test.sv"
  `include "ahb_wb_bridge_gapping_test.sv"
  `include "ahb_wb_bridge_random_test.sv"

endpackage

`endif // GUARD_AHB_WB_BRIDGE_PKG_SV
