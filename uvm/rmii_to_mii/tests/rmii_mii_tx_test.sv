///////////////////////////////////////////////////////////////////////////////
// rmii_mii_tx_test.sv
///////////////////////////////////////////////////////////////////////////////
// Tests the TX path (MII → RMII) with directed frame patterns.
///////////////////////////////////////////////////////////////////////////////

`ifndef GUARD_RMII_MII_TX_TEST_SV
`define GUARD_RMII_MII_TX_TEST_SV

class rmii_mii_tx_test extends rmii_mii_base_test;

  `uvm_component_utils(rmii_mii_tx_test)

  function new(string name = "rmii_mii_tx_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual task main_phase(uvm_phase phase);
    mii_tx_frame_sequence frame_seq;

    phase.raise_objection(this);

    `uvm_info("TEST", "=== TX Path Test ===", UVM_LOW)

    // Test 1: Short frame with known pattern
    `uvm_info("TEST", "Test 1: Short frame (8 nibbles, incrementing)", UVM_LOW)
    frame_seq = mii_tx_frame_sequence::type_id::create("frame_1");
    frame_seq.num_nibbles = 8;
    frame_seq.frame_data = new[8];
    for (int i = 0; i < 8; i++) frame_seq.frame_data[i] = i[3:0];
    frame_seq.start(env.mii_agt.tx_sequencer);

    // Test 2: All-ones frame
    `uvm_info("TEST", "Test 2: All-ones frame (16 nibbles)", UVM_LOW)
    frame_seq = mii_tx_frame_sequence::type_id::create("frame_2");
    frame_seq.num_nibbles = 16;
    frame_seq.frame_data = new[16];
    for (int i = 0; i < 16; i++) frame_seq.frame_data[i] = 4'hF;
    frame_seq.start(env.mii_agt.tx_sequencer);

    // Test 3: Alternating 0x5/0xA pattern
    `uvm_info("TEST", "Test 3: Alternating 0x5/0xA (32 nibbles)", UVM_LOW)
    frame_seq = mii_tx_frame_sequence::type_id::create("frame_3");
    frame_seq.num_nibbles = 32;
    frame_seq.frame_data = new[32];
    for (int i = 0; i < 32; i++) frame_seq.frame_data[i] = (i % 2) ? 4'hA : 4'h5;
    frame_seq.start(env.mii_agt.tx_sequencer);

    // Test 4: Back-to-back short frames
    `uvm_info("TEST", "Test 4: Back-to-back frames", UVM_LOW)
    for (int f = 0; f < 4; f++) begin
      frame_seq = mii_tx_frame_sequence::type_id::create($sformatf("b2b_%0d", f));
      frame_seq.num_nibbles = 10;
      frame_seq.frame_data = new[10];
      for (int i = 0; i < 10; i++) frame_seq.frame_data[i] = (f * 4 + i) & 4'hF;
      frame_seq.start(env.mii_agt.tx_sequencer);
    end

    // Drain time
    repeat (50) @(posedge rmii_vif.rmii_ref_clk);

    phase.drop_objection(this);
  endtask

endclass

`endif // GUARD_RMII_MII_TX_TEST_SV
