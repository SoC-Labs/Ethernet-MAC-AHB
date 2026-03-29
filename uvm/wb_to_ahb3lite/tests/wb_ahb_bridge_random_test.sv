///////////////////////////////////////////////////////////////////////////////
// wb_ahb_bridge_random_test.sv
///////////////////////////////////////////////////////////////////////////////
// Constrained-random test: mix of single and burst transfers with
// randomized slave response delays. Primary test for coverage closure.
///////////////////////////////////////////////////////////////////////////////

`ifndef GUARD_WB_AHB_BRIDGE_RANDOM_TEST_SV
`define GUARD_WB_AHB_BRIDGE_RANDOM_TEST_SV

class wb_ahb_bridge_random_test extends wb_ahb_bridge_base_test;

  `uvm_component_utils(wb_ahb_bridge_random_test)

  int unsigned num_transactions = 200;

  function new(string name = "wb_ahb_bridge_random_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    // Use wait-state slave sequence for more interesting scenarios
    uvm_config_db#(uvm_object_wrapper)::set(this,
      "env.ahb_sys_env.slave*.sequencer.run_phase",
      "default_sequence",
      ahb_slave_wait_state_sequence::type_id::get());
  endfunction

  virtual task main_phase(uvm_phase phase);
    wb_mixed_sequence mixed_seq;

    phase.raise_objection(this);

    `uvm_info("TEST", $sformatf("=== Random Test: %0d transactions ===", num_transactions), UVM_LOW)

    mixed_seq = wb_mixed_sequence::type_id::create("mixed_seq");
    mixed_seq.num_transactions = num_transactions;
    mixed_seq.start(env.wb_agt.sequencer);

    repeat (50) @(posedge vif.clk);
    phase.drop_objection(this);
  endtask

endclass

`endif // GUARD_WB_AHB_BRIDGE_RANDOM_TEST_SV
