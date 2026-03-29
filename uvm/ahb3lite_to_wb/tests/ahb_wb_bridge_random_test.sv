///////////////////////////////////////////////////////////////////////////////
// ahb_wb_bridge_random_test.sv
///////////////////////////////////////////////////////////////////////////////
// Constrained-random test: mix of single transfers with randomized
// WB slave wait cycles. Primary test for coverage closure.
///////////////////////////////////////////////////////////////////////////////

`ifndef GUARD_AHB_WB_BRIDGE_RANDOM_TEST_SV
`define GUARD_AHB_WB_BRIDGE_RANDOM_TEST_SV

class ahb_wb_bridge_random_test extends ahb_wb_bridge_base_test;

  `uvm_component_utils(ahb_wb_bridge_random_test)

  int unsigned num_transactions = 200;

  function new(string name = "ahb_wb_bridge_random_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    // Use wait-state WB slave for more interesting scenarios
    uvm_config_db#(int unsigned)::set(this, "env.wb_agt.driver", "wait_cycles", 2);
  endfunction

  virtual task main_phase(uvm_phase phase);
    ahb_mixed_sequence mixed_seq;

    phase.raise_objection(this);

    `uvm_info("TEST", $sformatf("=== Random Test: %0d transactions ===", num_transactions), UVM_LOW)

    mixed_seq = ahb_mixed_sequence::type_id::create("mixed_seq");
    mixed_seq.num_transactions = num_transactions;
    mixed_seq.start(env.ahb_sys_env.master[0].sequencer);

    repeat (50) @(posedge vif.clk);
    phase.drop_objection(this);
  endtask

endclass

`endif // GUARD_AHB_WB_BRIDGE_RANDOM_TEST_SV
