///////////////////////////////////////////////////////////////////////////////
// wb_ahb_bridge_wait_state_test.sv
///////////////////////////////////////////////////////////////////////////////
// Tests AHB slave wait state (backpressure) handling through the bridge.
///////////////////////////////////////////////////////////////////////////////

`ifndef GUARD_WB_AHB_BRIDGE_WAIT_STATE_TEST_SV
`define GUARD_WB_AHB_BRIDGE_WAIT_STATE_TEST_SV

class wb_ahb_bridge_wait_state_test extends wb_ahb_bridge_base_test;

  `uvm_component_utils(wb_ahb_bridge_wait_state_test)

  function new(string name = "wb_ahb_bridge_wait_state_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    // Override slave sequence to insert random wait states
    uvm_config_db#(uvm_object_wrapper)::set(this,
      "env.ahb_sys_env.slave*.sequencer.run_phase",
      "default_sequence",
      ahb_slave_wait_state_sequence::type_id::get());
  endfunction

  virtual task main_phase(uvm_phase phase);
    wb_single_write_sequence  wr_seq;
    wb_single_read_sequence   rd_seq;
    wb_burst_write_sequence   bwr_seq;
    wb_burst_read_sequence    brd_seq;
    wb_write_read_sequence    wr_rd_seq;

    phase.raise_objection(this);

    `uvm_info("TEST", "=== Wait State Test ===", UVM_LOW)

    // Single transfers with wait states
    `uvm_info("TEST", "Test 1: Single write with wait states", UVM_LOW)
    wr_seq = wb_single_write_sequence::type_id::create("wr_seq");
    wr_seq.addr = 32'h0000_0000;
    wr_seq.data = 32'hDEAD_BEEF;
    wr_seq.start(env.wb_agt.sequencer);

    `uvm_info("TEST", "Test 2: Single read with wait states", UVM_LOW)
    rd_seq = wb_single_read_sequence::type_id::create("rd_seq");
    rd_seq.addr = 32'h0000_0000;
    rd_seq.start(env.wb_agt.sequencer);

    // Burst transfers with wait states
    `uvm_info("TEST", "Test 3: Burst write with wait states", UVM_LOW)
    bwr_seq = wb_burst_write_sequence::type_id::create("bwr_seq");
    bwr_seq.addr = 32'h0000_0100;
    bwr_seq.data = '{32'hAAAA, 32'hBBBB, 32'hCCCC, 32'hDDDD};
    bwr_seq.start(env.wb_agt.sequencer);

    `uvm_info("TEST", "Test 4: Burst read with wait states", UVM_LOW)
    brd_seq = wb_burst_read_sequence::type_id::create("brd_seq");
    brd_seq.addr = 32'h0000_0100;
    brd_seq.start(env.wb_agt.sequencer);

    // Write-readback with wait states
    `uvm_info("TEST", "Test 5: Write-readback with wait states", UVM_LOW)
    for (int i = 0; i < 4; i++) begin
      wr_rd_seq = wb_write_read_sequence::type_id::create($sformatf("wr_rd_%0d", i));
      wr_rd_seq.use_burst = (i % 2);
      wr_rd_seq.addr = 32'h0000_0200 + (i * 32'h20);
      wr_rd_seq.data = 32'hF000_0000 + i;
      wr_rd_seq.start(env.wb_agt.sequencer);
    end

    repeat (20) @(posedge vif.clk);
    phase.drop_objection(this);
  endtask

endclass

`endif // GUARD_WB_AHB_BRIDGE_WAIT_STATE_TEST_SV
