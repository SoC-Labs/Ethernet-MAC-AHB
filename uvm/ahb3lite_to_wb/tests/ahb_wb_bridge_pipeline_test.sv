///////////////////////////////////////////////////////////////////////////////
// ahb_wb_bridge_pipeline_test.sv
///////////////////////////////////////////////////////////////////////////////
// Tests AHB pipeline address integrity through the ahb3lite_to_wb bridge.
//
// Writes unique data to multiple addresses, then reads them back-to-back.
// Each read must return the data written to *that* address, not stale data
// from a neighbouring transaction. Designed to expose the bug where the
// bridge overwrites the WB address register during the AHB address phase
// of a pipelined transfer before the previous WB data phase completes.
///////////////////////////////////////////////////////////////////////////////

`ifndef GUARD_AHB_WB_BRIDGE_PIPELINE_TEST_SV
`define GUARD_AHB_WB_BRIDGE_PIPELINE_TEST_SV

class ahb_wb_bridge_pipeline_test extends ahb_wb_bridge_base_test;

  `uvm_component_utils(ahb_wb_bridge_pipeline_test)

  function new(string name = "ahb_wb_bridge_pipeline_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual task main_phase(uvm_phase phase);
    ahb_pipeline_integrity_sequence pipe_seq;

    phase.raise_objection(this);

    `uvm_info("TEST", "=== Pipeline Integrity Test ===", UVM_LOW)

    // Test with 8 transfers (enough to expose pipelining issues)
    pipe_seq = ahb_pipeline_integrity_sequence::type_id::create("pipe_seq");
    pipe_seq.num_transfers = 8;
    pipe_seq.base_addr     = 32'h0000_2000;
    pipe_seq.start(env.ahb_sys_env.master[0].sequencer);

    // Second round with different base to ensure no address aliasing
    `uvm_info("TEST", "--- Round 2: different base address ---", UVM_LOW)
    pipe_seq = ahb_pipeline_integrity_sequence::type_id::create("pipe_seq_2");
    pipe_seq.num_transfers = 12;
    pipe_seq.base_addr     = 32'h0000_4000;
    pipe_seq.start(env.ahb_sys_env.master[0].sequencer);

    repeat (20) @(posedge vif.clk);

    phase.drop_objection(this);
  endtask

endclass

`endif // GUARD_AHB_WB_BRIDGE_PIPELINE_TEST_SV
