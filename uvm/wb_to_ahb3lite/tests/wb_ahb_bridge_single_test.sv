///////////////////////////////////////////////////////////////////////////////
// wb_ahb_bridge_single_test.sv
///////////////////////////////////////////////////////////////////////////////
// Tests single-beat classic WB transfers through the bridge.
///////////////////////////////////////////////////////////////////////////////

`ifndef GUARD_WB_AHB_BRIDGE_SINGLE_TEST_SV
`define GUARD_WB_AHB_BRIDGE_SINGLE_TEST_SV

class wb_ahb_bridge_single_test extends wb_ahb_bridge_base_test;

  `uvm_component_utils(wb_ahb_bridge_single_test)

  function new(string name = "wb_ahb_bridge_single_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual task main_phase(uvm_phase phase);
    wb_single_write_sequence  wr_seq;
    wb_single_read_sequence   rd_seq;
    wb_write_read_sequence    wr_rd_seq;
    wb_back_to_back_sequence  b2b_seq;

    phase.raise_objection(this);

    `uvm_info("TEST", "=== Single Transfer Test ===", UVM_LOW)

    // Test 1: Single write
    `uvm_info("TEST", "Test 1: Single word write", UVM_LOW)
    wr_seq = wb_single_write_sequence::type_id::create("wr_seq");
    wr_seq.addr = 32'h0000_0100;
    wr_seq.data = 32'hDEAD_BEEF;
    wr_seq.start(env.wb_agt.sequencer);

    // Test 2: Single read
    `uvm_info("TEST", "Test 2: Single word read", UVM_LOW)
    rd_seq = wb_single_read_sequence::type_id::create("rd_seq");
    rd_seq.addr = 32'h0000_0100;
    rd_seq.start(env.wb_agt.sequencer);

    // Test 3: Write then readback
    `uvm_info("TEST", "Test 3: Write then readback", UVM_LOW)
    wr_rd_seq = wb_write_read_sequence::type_id::create("wr_rd_seq");
    wr_rd_seq.use_burst = 0;
    wr_rd_seq.addr = 32'h0000_0200;
    wr_rd_seq.data = 32'hCAFE_BABE;
    wr_rd_seq.start(env.wb_agt.sequencer);

    // Test 4: Back-to-back singles
    `uvm_info("TEST", "Test 4: Back-to-back single transfers", UVM_LOW)
    b2b_seq = wb_back_to_back_sequence::type_id::create("b2b_seq");
    b2b_seq.num_transfers = 8;
    b2b_seq.base_addr = 32'h0000_1000;
    b2b_seq.start(env.wb_agt.sequencer);

    // Test 5: Multiple addresses
    `uvm_info("TEST", "Test 5: Multiple addresses", UVM_LOW)
    for (int i = 0; i < 6; i++) begin
      wr_rd_seq = wb_write_read_sequence::type_id::create("wr_rd_seq");
      wr_rd_seq.use_burst = 0;
      wr_rd_seq.addr = i * 32'h100;
      wr_rd_seq.data = 32'hA000_0000 + i;
      wr_rd_seq.start(env.wb_agt.sequencer);
    end

    // Allow time for all AHB transactions to complete
    repeat (20) @(posedge vif.clk);

    phase.drop_objection(this);
  endtask

endclass

`endif // GUARD_WB_AHB_BRIDGE_SINGLE_TEST_SV
