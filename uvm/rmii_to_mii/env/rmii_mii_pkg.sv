///////////////////////////////////////////////////////////////////////////////
// rmii_mii_pkg.sv
///////////////////////////////////////////////////////////////////////////////
// Package containing all UVM testbench components for the rmii_to_mii
// adapter verification environment.
///////////////////////////////////////////////////////////////////////////////

`ifndef GUARD_RMII_MII_PKG_SV
`define GUARD_RMII_MII_PKG_SV

package rmii_mii_pkg;

  import uvm_pkg::*;
  `include "uvm_macros.svh"

  // ---------------------------------------------------------------
  // Shared transaction
  // ---------------------------------------------------------------
  `include "nibble_transaction.sv"

  // ---------------------------------------------------------------
  // MII agent
  // ---------------------------------------------------------------
  `include "mii_tx_driver.sv"
  `include "mii_rx_monitor.sv"
  `include "mii_agent.sv"

  // ---------------------------------------------------------------
  // RMII agent
  // ---------------------------------------------------------------
  `include "rmii_rx_driver.sv"
  `include "rmii_tx_monitor.sv"
  `include "rmii_agent.sv"

  // ---------------------------------------------------------------
  // Environment
  // ---------------------------------------------------------------
  `include "rmii_mii_config.sv"
  `include "rmii_mii_scoreboard.sv"
  `include "rmii_mii_env.sv"

  // ---------------------------------------------------------------
  // Sequences
  // ---------------------------------------------------------------
  `include "mii_tx_frame_sequence.sv"
  `include "mii_tx_random_sequence.sv"
  `include "rmii_rx_frame_sequence.sv"
  `include "rmii_rx_random_sequence.sv"

  // ---------------------------------------------------------------
  // Tests
  // ---------------------------------------------------------------
  `include "rmii_mii_base_test.sv"
  `include "rmii_mii_tx_test.sv"
  `include "rmii_mii_rx_test.sv"
  `include "rmii_mii_collision_test.sv"
  `include "rmii_mii_random_test.sv"

endpackage

`endif // GUARD_RMII_MII_PKG_SV
