///////////////////////////////////////////////////////////////////////////////
// wb_ahb_bridge_base_test.sv
///////////////////////////////////////////////////////////////////////////////
// Base test for the wb_to_ahb3lite bridge UVM testbench.
// Sets up default configuration and slave response sequence.
///////////////////////////////////////////////////////////////////////////////

`ifndef GUARD_WB_AHB_BRIDGE_BASE_TEST_SV
`define GUARD_WB_AHB_BRIDGE_BASE_TEST_SV

class wb_ahb_bridge_base_test extends uvm_test;

  `uvm_component_utils(wb_ahb_bridge_base_test)

  wb_ahb_bridge_env env;
  wb_ahb_bridge_config cfg;

  // Virtual interface for clock/reset access
  virtual wb_master_if vif;

  function new(string name = "wb_ahb_bridge_base_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    `uvm_info("build_phase", "Building base test...", UVM_LOW)

    // Get virtual interface for clock/reset access
    if (!uvm_config_db#(virtual wb_master_if)::get(this, "", "vif", vif))
      `uvm_fatal("NOVIF", "Virtual interface not set for base test")

    // Create configuration
    cfg = wb_ahb_bridge_config::type_id::create("cfg");
    uvm_config_db#(wb_ahb_bridge_config)::set(this, "env", "cfg", cfg);

    // Create environment
    env = wb_ahb_bridge_env::type_id::create("env", this);

    // Set default slave memory response sequence on all slave sequencers
    uvm_config_db#(uvm_object_wrapper)::set(this,
      "env.ahb_sys_env.slave*.sequencer.run_phase",
      "default_sequence",
      ahb_slave_response_sequence::type_id::get());

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

`endif // GUARD_WB_AHB_BRIDGE_BASE_TEST_SV
