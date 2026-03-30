///////////////////////////////////////////////////////////////////////////////
// wb_ahb_bridge_gapping_test.sv
///////////////////////////////////////////////////////////////////////////////
// Tests inter-transaction gapping on the Wishbone side combined with
// AHB slave wait-state stalling. Exercises the bridge under varied
// idle gaps (0-15 WB clocks) and aggressive slave backpressure (0-10
// AHB wait cycles) to catch timing issues at bus idle/resume boundaries.
///////////////////////////////////////////////////////////////////////////////

`ifndef GUARD_WB_AHB_BRIDGE_GAPPING_TEST_SV
`define GUARD_WB_AHB_BRIDGE_GAPPING_TEST_SV

class wb_ahb_bridge_gapping_test extends wb_ahb_bridge_base_test;

  `uvm_component_utils(wb_ahb_bridge_gapping_test)

  int unsigned num_transactions = 500;

  function new(string name = "wb_ahb_bridge_gapping_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    // Use aggressive wait-state slave to combine gapping + stalling
    uvm_config_db#(uvm_object_wrapper)::set(this,
      "env.ahb_sys_env.slave*.sequencer.run_phase",
      "default_sequence",
      ahb_slave_wait_state_sequence::type_id::get());
  endfunction

  virtual task main_phase(uvm_phase phase);
    wb_gapping_sequence gap_seq;

    phase.raise_objection(this);

    `uvm_info("TEST", $sformatf("=== Gapping+Stalling Test: %0d transactions ===", num_transactions), UVM_LOW)

    gap_seq = wb_gapping_sequence::type_id::create("gap_seq");
    gap_seq.num_transactions = num_transactions;
    gap_seq.max_gap = 15;
    gap_seq.start(env.wb_agt.sequencer);

    repeat (50) @(posedge vif.clk);
    phase.drop_objection(this);
  endtask

endclass

`endif // GUARD_WB_AHB_BRIDGE_GAPPING_TEST_SV
