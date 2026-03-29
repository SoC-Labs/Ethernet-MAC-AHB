///////////////////////////////////////////////////////////////////////////////
// wb_ahb_bridge_burst_test.sv
///////////////////////////////////////////////////////////////////////////////
// Tests INCR4 burst transfers through the bridge.
///////////////////////////////////////////////////////////////////////////////

`ifndef GUARD_WB_AHB_BRIDGE_BURST_TEST_SV
`define GUARD_WB_AHB_BRIDGE_BURST_TEST_SV

class wb_ahb_bridge_burst_test extends wb_ahb_bridge_base_test;

  `uvm_component_utils(wb_ahb_bridge_burst_test)

  function new(string name = "wb_ahb_bridge_burst_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual task main_phase(uvm_phase phase);
    wb_burst_write_sequence  bwr_seq;
    wb_burst_read_sequence   brd_seq;
    wb_write_read_sequence   wr_rd_seq;
    wb_single_write_sequence swr_seq;
    wb_single_read_sequence  srd_seq;

    phase.raise_objection(this);

    `uvm_info("TEST", "=== Burst Transfer Test ===", UVM_LOW)

    // Test 1: Burst write
    `uvm_info("TEST", "Test 1: INCR4 burst write", UVM_LOW)
    bwr_seq = wb_burst_write_sequence::type_id::create("bwr_seq");
    bwr_seq.addr = 32'h0000_0000;
    bwr_seq.data = '{32'h1111_1111, 32'h2222_2222, 32'h3333_3333, 32'h4444_4444};
    bwr_seq.start(env.wb_agt.sequencer);

    // Test 2: Burst read
    `uvm_info("TEST", "Test 2: INCR4 burst read", UVM_LOW)
    brd_seq = wb_burst_read_sequence::type_id::create("brd_seq");
    brd_seq.addr = 32'h0000_0000;
    brd_seq.start(env.wb_agt.sequencer);

    // Test 3: Burst write-readback
    `uvm_info("TEST", "Test 3: Burst write then burst read", UVM_LOW)
    wr_rd_seq = wb_write_read_sequence::type_id::create("wr_rd_seq");
    wr_rd_seq.use_burst = 1;
    wr_rd_seq.addr = 32'h0000_0100;
    wr_rd_seq.data = 32'hAAAA_0000;
    wr_rd_seq.start(env.wb_agt.sequencer);

    // Test 4: Consecutive bursts
    `uvm_info("TEST", "Test 4: Two consecutive INCR4 bursts", UVM_LOW)
    bwr_seq = wb_burst_write_sequence::type_id::create("bwr_seq");
    bwr_seq.addr = 32'h0000_0200;
    bwr_seq.data = '{32'hAAAA_AAAA, 32'hBBBB_BBBB, 32'hCCCC_CCCC, 32'hDDDD_DDDD};
    bwr_seq.start(env.wb_agt.sequencer);

    bwr_seq = wb_burst_write_sequence::type_id::create("bwr_seq2");
    bwr_seq.addr = 32'h0000_0210;
    bwr_seq.data = '{32'hEEEE_EEEE, 32'hFFFF_FFFF, 32'h0000_0001, 32'h0000_0002};
    bwr_seq.start(env.wb_agt.sequencer);

    // Test 5: Burst then single
    `uvm_info("TEST", "Test 5: Burst followed by single transfer", UVM_LOW)
    bwr_seq = wb_burst_write_sequence::type_id::create("bwr_seq3");
    bwr_seq.addr = 32'h0000_0300;
    bwr_seq.data = '{32'h5555_5555, 32'h6666_6666, 32'h7777_7777, 32'h8888_8888};
    bwr_seq.start(env.wb_agt.sequencer);

    swr_seq = wb_single_write_sequence::type_id::create("swr_seq");
    swr_seq.addr = 32'h0000_0400;
    swr_seq.data = 32'h9999_9999;
    swr_seq.start(env.wb_agt.sequencer);

    // Test 6: Single then burst
    `uvm_info("TEST", "Test 6: Single followed by burst transfer", UVM_LOW)
    swr_seq = wb_single_write_sequence::type_id::create("swr_seq2");
    swr_seq.addr = 32'h0000_0500;
    swr_seq.data = 32'hF0F0_F0F0;
    swr_seq.start(env.wb_agt.sequencer);

    bwr_seq = wb_burst_write_sequence::type_id::create("bwr_seq4");
    bwr_seq.addr = 32'h0000_0600;
    bwr_seq.data = '{32'h0A0A_0A0A, 32'h0B0B_0B0B, 32'h0C0C_0C0C, 32'h0D0D_0D0D};
    bwr_seq.start(env.wb_agt.sequencer);

    repeat (20) @(posedge vif.clk);
    phase.drop_objection(this);
  endtask

endclass

`endif // GUARD_WB_AHB_BRIDGE_BURST_TEST_SV
