///////////////////////////////////////////////////////////////////////////////
// ha1588_ahb_base_test.sv
///////////////////////////////////////////////////////////////////////////////
// Base test for the ha1588_ahb UVM testbench.
///////////////////////////////////////////////////////////////////////////////

`ifndef GUARD_HA1588_AHB_BASE_TEST_SV
`define GUARD_HA1588_AHB_BASE_TEST_SV

class ha1588_ahb_base_test extends uvm_test;

  `uvm_component_utils(ha1588_ahb_base_test)

  ha1588_ahb_env    env;
  ha1588_ahb_config cfg;

  virtual svt_ahb_if ahb_vif;

  function new(string name = "ha1588_ahb_base_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    `uvm_info("build_phase", "Building base test...", UVM_LOW)

    if (!uvm_config_db#(virtual svt_ahb_if)::get(this, "", "ahb_vif", ahb_vif))
      `uvm_fatal("NOVIF", "AHB virtual interface not set for base test")

    cfg = ha1588_ahb_config::type_id::create("cfg");
    uvm_config_db#(ha1588_ahb_config)::set(this, "env", "cfg", cfg);

    env = ha1588_ahb_env::type_id::create("env", this);

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
    @(posedge ahb_vif.hresetn);
    repeat (5) @(posedge ahb_vif.hclk);
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

`endif
