///////////////////////////////////////////////////////////////////////////////
// ahb_wb_bridge_base_test.sv
///////////////////////////////////////////////////////////////////////////////
// Base test for the ahb3lite_to_wb bridge UVM testbench.
// Sets up default configuration and WB slave response behaviour.
///////////////////////////////////////////////////////////////////////////////

`ifndef GUARD_AHB_WB_BRIDGE_BASE_TEST_SV
`define GUARD_AHB_WB_BRIDGE_BASE_TEST_SV

class ahb_wb_bridge_base_test extends uvm_test;

  `uvm_component_utils(ahb_wb_bridge_base_test)

  ahb_wb_bridge_env    env;
  ahb_wb_bridge_config cfg;

  // Virtual interface for clock/reset access
  virtual wb_slave_if vif;

  function new(string name = "ahb_wb_bridge_base_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    `uvm_info("build_phase", "Building base test...", UVM_LOW)

    // Get virtual interface for clock/reset access
    if (!uvm_config_db#(virtual wb_slave_if)::get(this, "", "vif", vif))
      `uvm_fatal("NOVIF", "Virtual interface not set for base test")

    // Create configuration
    cfg = ahb_wb_bridge_config::type_id::create("cfg");
    uvm_config_db#(ahb_wb_bridge_config)::set(this, "env", "cfg", cfg);

    // Create environment
    env = ahb_wb_bridge_env::type_id::create("env", this);

    `uvm_info("build_phase", "Build complete.", UVM_LOW)
  endfunction

  function void end_of_elaboration_phase(uvm_phase phase);
    uvm_root root = uvm_root::get();
    `uvm_info("end_of_elaboration_phase", "Printing topology...", UVM_LOW)
    root.print_topology();
  endfunction

  // Wait for reset deassertion before starting main phase
  virtual task reset_phase(uvm_phase phase);
    phase.raise_objection(this);
    `uvm_info("reset_phase", "Waiting for reset deassertion...", UVM_LOW)
    @(posedge vif.rst_n);
    repeat (5) @(posedge vif.clk);
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

`endif // GUARD_AHB_WB_BRIDGE_BASE_TEST_SV
