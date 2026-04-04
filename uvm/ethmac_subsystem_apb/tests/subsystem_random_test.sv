///////////////////////////////////////////////////////////////////////////////
// subsystem_random_test.sv — Constrained-random mix (CP1-CP3 coverage)
///////////////////////////////////////////////////////////////////////////////

`ifndef GUARD_SUBSYSTEM_RANDOM_TEST_SV
`define GUARD_SUBSYSTEM_RANDOM_TEST_SV

class subsystem_random_test extends subsystem_base_test;
  `uvm_component_utils(subsystem_random_test)

  function new(string name = "subsystem_random_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual task main_phase(uvm_phase phase);
    apb_mixed_sequence mixed;

    phase.raise_objection(this);

    `uvm_info("TEST", "=== Subsystem Random Test ===", UVM_LOW)
    mixed = apb_mixed_sequence::type_id::create("mixed");
    mixed.num_transfers = 200;
    mixed.start(env.apb_sys_env.master.sequencer);

    repeat (50) @(posedge apb_vif.pclk);
    phase.drop_objection(this);
  endtask
endclass

`endif
