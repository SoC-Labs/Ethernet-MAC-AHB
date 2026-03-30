///////////////////////////////////////////////////////////////////////////////
// rmii_mii_base_test.sv
///////////////////////////////////////////////////////////////////////////////
// Base test for the rmii_to_mii UVM testbench.
// Builds the environment and waits for reset deassertion.
///////////////////////////////////////////////////////////////////////////////

`ifndef GUARD_RMII_MII_BASE_TEST_SV
`define GUARD_RMII_MII_BASE_TEST_SV

class rmii_mii_base_test extends uvm_test;

  `uvm_component_utils(rmii_mii_base_test)

  rmii_mii_env    env;
  rmii_mii_config cfg;

  // Virtual interfaces for clock/reset access
  virtual rmii_if rmii_vif;

  function new(string name = "rmii_mii_base_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    `uvm_info("build_phase", "Building base test...", UVM_LOW)

    if (!uvm_config_db#(virtual rmii_if)::get(this, "", "rmii_vif", rmii_vif))
      `uvm_fatal("NOVIF", "RMII virtual interface not set for base test")

    cfg = rmii_mii_config::type_id::create("cfg");
    uvm_config_db#(rmii_mii_config)::set(this, "env", "cfg", cfg);

    env = rmii_mii_env::type_id::create("env", this);

    `uvm_info("build_phase", "Build complete.", UVM_LOW)
  endfunction

  function void end_of_elaboration_phase(uvm_phase phase);
    uvm_root root = uvm_root::get();
    `uvm_info("end_of_elaboration_phase", "Printing topology...", UVM_LOW)
    root.print_topology();
  endfunction

  virtual task reset_phase(uvm_phase phase);
    phase.raise_objection(this);
    `uvm_info("reset_phase", "Waiting for reset deassertion...", UVM_LOW)
    wait (rmii_vif.rst_n === 1'b1);
    repeat (5) @(posedge rmii_vif.rmii_ref_clk);
    `uvm_info("reset_phase", "Reset complete.", UVM_LOW)
    phase.drop_objection(this);
  endtask

  function void final_phase(uvm_phase phase);
    uvm_report_server svr;
    super.final_phase(phase);

    svr = uvm_report_server::get_server();

    if (svr.get_severity_count(UVM_FATAL) +
        svr.get_severity_count(UVM_ERROR) > 0)
      `uvm_info("final_phase", "\n========== TEST FAILED ==========\n", UVM_NONE)
    else
      `uvm_info("final_phase", "\n========== TEST PASSED ==========\n", UVM_NONE)
  endfunction

endclass

`endif // GUARD_RMII_MII_BASE_TEST_SV
