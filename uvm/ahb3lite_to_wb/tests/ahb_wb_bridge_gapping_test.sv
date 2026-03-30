///////////////////////////////////////////////////////////////////////////////
// ahb_wb_bridge_gapping_test.sv
///////////////////////////////////////////////////////////////////////////////
// Tests inter-transaction gapping on the AHB side combined with
// randomized WB slave wait-state stalling. Exercises the bridge under
// varied idle gaps (0-15 AHB clocks) and randomized slave backpressure
// (0-5 WB wait cycles) to catch timing issues at bus idle/resume
// boundaries.
///////////////////////////////////////////////////////////////////////////////

`ifndef GUARD_AHB_WB_BRIDGE_GAPPING_TEST_SV
`define GUARD_AHB_WB_BRIDGE_GAPPING_TEST_SV

class ahb_wb_bridge_gapping_test extends ahb_wb_bridge_base_test;

  `uvm_component_utils(ahb_wb_bridge_gapping_test)

  int unsigned num_transactions = 500;

  function new(string name = "ahb_wb_bridge_gapping_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    // Enable randomized WB slave wait states for stalling
    uvm_config_db#(bit)::set(this, "env.wb_agt.driver", "random_wait", 1);
    uvm_config_db#(int unsigned)::set(this, "env.wb_agt.driver", "max_random_wait", 5);
  endfunction

  virtual task main_phase(uvm_phase phase);
    ahb_gapping_sequence gap_seq;

    phase.raise_objection(this);

    `uvm_info("TEST", $sformatf("=== Gapping+Stalling Test: %0d transactions ===", num_transactions), UVM_LOW)

    gap_seq = ahb_gapping_sequence::type_id::create("gap_seq");
    gap_seq.num_transactions = num_transactions;
    gap_seq.max_gap = 15;
    gap_seq.start(env.ahb_sys_env.master[0].sequencer);

    repeat (50) @(posedge vif.clk);
    phase.drop_objection(this);
  endtask

endclass

`endif // GUARD_AHB_WB_BRIDGE_GAPPING_TEST_SV
