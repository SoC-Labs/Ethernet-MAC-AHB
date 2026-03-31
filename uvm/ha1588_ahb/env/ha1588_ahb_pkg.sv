///////////////////////////////////////////////////////////////////////////////
// ha1588_ahb_pkg.sv
///////////////////////////////////////////////////////////////////////////////
// Package containing all UVM testbench components for the ha1588_ahb
// verification environment.
///////////////////////////////////////////////////////////////////////////////

`ifndef GUARD_HA1588_AHB_PKG_SV
`define GUARD_HA1588_AHB_PKG_SV

package ha1588_ahb_pkg;

  import uvm_pkg::*;
  `include "uvm_macros.svh"

  import svt_uvm_pkg::*;
  import svt_ahb_uvm_pkg::*;

  // ---------------------------------------------------------------
  // Environment
  // ---------------------------------------------------------------
  `include "ha1588_ahb_config.sv"
  `include "ha1588_ahb_scoreboard.sv"
  `include "ha1588_ahb_env.sv"

  // ---------------------------------------------------------------
  // Sequences
  // ---------------------------------------------------------------
  `include "ahb_single_write_sequence.sv"
  `include "ahb_single_read_sequence.sv"
  `include "ahb_write_read_sequence.sv"
  `include "ahb_mixed_sequence.sv"

  // ---------------------------------------------------------------
  // Tests
  // ---------------------------------------------------------------
  `include "ha1588_ahb_base_test.sv"
  `include "ha1588_ahb_single_test.sv"
  `include "ha1588_ahb_random_test.sv"

endpackage

`endif // GUARD_HA1588_AHB_PKG_SV
