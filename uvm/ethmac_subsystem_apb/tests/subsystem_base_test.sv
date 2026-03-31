///////////////////////////////////////////////////////////////////////////////
// subsystem_base_test.sv — Base test with reset and topology
///////////////////////////////////////////////////////////////////////////////

`ifndef GUARD_SUBSYSTEM_BASE_TEST_SV
`define GUARD_SUBSYSTEM_BASE_TEST_SV

class subsystem_base_test extends uvm_test;
  `uvm_component_utils(subsystem_base_test)

  subsystem_env        env;
  subsystem_apb_config apb_cfg;
  subsystem_ahb_config ahb_cfg;

  virtual svt_apb_if apb_vif;
  virtual svt_ahb_if ahb_vif;

  function new(string name = "subsystem_base_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    if (!uvm_config_db#(virtual svt_apb_if)::get(this, "", "apb_vif", apb_vif))
      `uvm_fatal("NOVIF", "APB VIF not set")
    if (!uvm_config_db#(virtual svt_ahb_if)::get(this, "", "ahb_vif", ahb_vif))
      `uvm_fatal("NOVIF", "AHB VIF not set")

    apb_cfg = subsystem_apb_config::type_id::create("apb_cfg");
    ahb_cfg = subsystem_ahb_config::type_id::create("ahb_cfg");
    uvm_config_db#(subsystem_apb_config)::set(this, "env", "apb_cfg", apb_cfg);
    uvm_config_db#(subsystem_ahb_config)::set(this, "env", "ahb_cfg", ahb_cfg);

    env = subsystem_env::type_id::create("env", this);
  endfunction

  function void end_of_elaboration_phase(uvm_phase phase);
    uvm_root::get().print_topology();
  endfunction

  virtual task reset_phase(uvm_phase phase);
    phase.raise_objection(this);
    @(posedge apb_vif.presetn);
    repeat (5) @(posedge apb_vif.pclk);
    phase.drop_objection(this);
  endtask

  function void final_phase(uvm_phase phase);
    uvm_report_server svr = uvm_report_server::get_server();
    if (svr.get_severity_count(UVM_FATAL) + svr.get_severity_count(UVM_ERROR) > 0)
      `uvm_info("RESULT", "\n========== TEST FAILED ==========\n", UVM_NONE)
    else
      `uvm_info("RESULT", "\n========== TEST PASSED ==========\n", UVM_NONE)
  endfunction
endclass

`endif
