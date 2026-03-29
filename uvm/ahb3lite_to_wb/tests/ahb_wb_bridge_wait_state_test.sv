///////////////////////////////////////////////////////////////////////////////
// ahb_wb_bridge_wait_state_test.sv
///////////////////////////////////////////////////////////////////////////////
// Tests WB slave wait state (backpressure) handling through the bridge.
// Configures the WB slave agent to insert wait cycles before responding.
///////////////////////////////////////////////////////////////////////////////

`ifndef GUARD_AHB_WB_BRIDGE_WAIT_STATE_TEST_SV
`define GUARD_AHB_WB_BRIDGE_WAIT_STATE_TEST_SV

class ahb_wb_bridge_wait_state_test extends ahb_wb_bridge_base_test;

  `uvm_component_utils(ahb_wb_bridge_wait_state_test)

  function new(string name = "ahb_wb_bridge_wait_state_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    // Configure WB slave agent to insert 3 wait cycles per transaction
    uvm_config_db#(int unsigned)::set(this, "env.wb_agt.driver", "wait_cycles", 3);
  endfunction

  virtual task main_phase(uvm_phase phase);
    ahb_single_write_sequence wr_seq;
    ahb_single_read_sequence  rd_seq;
    ahb_write_read_sequence   wr_rd_seq;

    phase.raise_objection(this);

    `uvm_info("TEST", "=== Wait State Test ===", UVM_LOW)

    // Single write with wait states
    `uvm_info("TEST", "Test 1: Single write with wait states", UVM_LOW)
    wr_seq = ahb_single_write_sequence::type_id::create("wr_seq");
    wr_seq.addr = 32'h0000_0000;
    wr_seq.data = 32'hDEAD_BEEF;
    wr_seq.start(env.ahb_sys_env.master[0].sequencer);

    // Single read with wait states
    `uvm_info("TEST", "Test 2: Single read with wait states", UVM_LOW)
    rd_seq = ahb_single_read_sequence::type_id::create("rd_seq");
    rd_seq.addr = 32'h0000_0000;
    rd_seq.start(env.ahb_sys_env.master[0].sequencer);

    // Write-readback with wait states
    `uvm_info("TEST", "Test 3: Write-readback pairs with wait states", UVM_LOW)
    for (int i = 0; i < 4; i++) begin
      wr_rd_seq = ahb_write_read_sequence::type_id::create($sformatf("wr_rd_%0d", i));
      wr_rd_seq.addr = 32'h0000_0100 + (i * 4);
      wr_rd_seq.data = 32'hF000_0000 + i;
      wr_rd_seq.start(env.ahb_sys_env.master[0].sequencer);
    end

    repeat (20) @(posedge vif.clk);
    phase.drop_objection(this);
  endtask

endclass

`endif // GUARD_AHB_WB_BRIDGE_WAIT_STATE_TEST_SV
