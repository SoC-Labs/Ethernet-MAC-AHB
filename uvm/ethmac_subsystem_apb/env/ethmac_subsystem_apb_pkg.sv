///////////////////////////////////////////////////////////////////////////////
// ethmac_subsystem_apb_pkg.sv — UVM package for subsystem testbench
///////////////////////////////////////////////////////////////////////////////

`ifndef GUARD_ETHMAC_SUBSYSTEM_APB_PKG_SV
`define GUARD_ETHMAC_SUBSYSTEM_APB_PKG_SV

package ethmac_subsystem_apb_pkg;

  import uvm_pkg::*;
  `include "uvm_macros.svh"

  import svt_uvm_pkg::*;
  import svt_apb_uvm_pkg::*;
  import svt_ahb_uvm_pkg::*;

  // Environment
  `include "subsystem_config.sv"
  `include "subsystem_scoreboard.sv"
  `include "subsystem_coverage.sv"
  `include "subsystem_env.sv"

  // Sequences
  `include "apb_write_sequence.sv"
  `include "apb_read_sequence.sv"
  `include "apb_write_read_sequence.sv"
  `include "apb_mixed_sequence.sv"

  // Tests
  `include "subsystem_base_test.sv"
  `include "subsystem_register_test.sv"
  `include "subsystem_random_test.sv"
  `include "subsystem_reset_test.sv"

endpackage

`endif
