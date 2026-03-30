///////////////////////////////////////////////////////////////////////////////
// wb_ahb_bridge_pkg.sv
///////////////////////////////////////////////////////////////////////////////
// Package containing all UVM testbench components for the wb_to_ahb3lite
// bridge verification environment.
///////////////////////////////////////////////////////////////////////////////

`ifndef GUARD_WB_AHB_BRIDGE_PKG_SV
`define GUARD_WB_AHB_BRIDGE_PKG_SV

package wb_ahb_bridge_pkg;

  import uvm_pkg::*;
  `include "uvm_macros.svh"

  import svt_uvm_pkg::*;
  import svt_ahb_uvm_pkg::*;

  // ---------------------------------------------------------------
  // Wishbone agent
  // ---------------------------------------------------------------
  `include "wb_master_transaction.sv"
  `include "wb_master_driver.sv"
  `include "wb_master_monitor.sv"
  `include "wb_master_sequencer.sv"
  `include "wb_master_agent.sv"

  // ---------------------------------------------------------------
  // Environment
  // ---------------------------------------------------------------
  `include "wb_ahb_bridge_config.sv"
  `include "wb_ahb_bridge_scoreboard.sv"
  `include "wb_ahb_bridge_env.sv"

  // ---------------------------------------------------------------
  // Sequences
  // ---------------------------------------------------------------
  `include "wb_base_sequence.sv"
  `include "wb_single_write_sequence.sv"
  `include "wb_single_read_sequence.sv"
  `include "wb_burst_write_sequence.sv"
  `include "wb_burst_read_sequence.sv"
  `include "wb_write_read_sequence.sv"
  `include "wb_back_to_back_sequence.sv"
  `include "wb_mixed_sequence.sv"
  `include "wb_gapping_sequence.sv"
  `include "ahb_slave_response_sequence.sv"
  `include "ahb_slave_error_sequence.sv"
  `include "ahb_slave_wait_state_sequence.sv"

  // ---------------------------------------------------------------
  // Tests
  // ---------------------------------------------------------------
  `include "wb_ahb_bridge_base_test.sv"
  `include "wb_ahb_bridge_single_test.sv"
  `include "wb_ahb_bridge_burst_test.sv"
  `include "wb_ahb_bridge_error_test.sv"
  `include "wb_ahb_bridge_wait_state_test.sv"
  `include "wb_ahb_bridge_random_test.sv"
  `include "wb_ahb_bridge_gapping_test.sv"

endpackage

`endif // GUARD_WB_AHB_BRIDGE_PKG_SV
