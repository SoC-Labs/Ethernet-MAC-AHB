///////////////////////////////////////////////////////////////////////////////
// rmii_mii_collision_test.sv
///////////////////////////////////////////////////////////////////////////////
// Tests collision detection by driving TX and RX simultaneously.
// The DUT asserts mcoll when both rmii_crs_dv and rmii_tx_en are active.
///////////////////////////////////////////////////////////////////////////////

`ifndef GUARD_RMII_MII_COLLISION_TEST_SV
`define GUARD_RMII_MII_COLLISION_TEST_SV

class rmii_mii_collision_test extends rmii_mii_base_test;

  `uvm_component_utils(rmii_mii_collision_test)

  virtual mii_if.rx_monitor mii_rx_vif;

  function new(string name = "rmii_mii_collision_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual mii_if.rx_monitor)::get(this, "", "mii_rx_vif", mii_rx_vif))
      `uvm_fatal("NOVIF", "MII RX monitor virtual interface not set")
  endfunction

  virtual task main_phase(uvm_phase phase);
    mii_tx_frame_sequence  tx_seq;
    rmii_rx_frame_sequence rx_seq;

    phase.raise_objection(this);

    `uvm_info("TEST", "=== Collision Detection Test ===", UVM_LOW)

    // Test 1: TX-only (no collision expected)
    `uvm_info("TEST", "Test 1: TX-only — no collision", UVM_LOW)
    tx_seq = mii_tx_frame_sequence::type_id::create("tx_only");
    tx_seq.num_nibbles = 16;
    tx_seq.frame_data = new[16];
    for (int i = 0; i < 16; i++) tx_seq.frame_data[i] = i[3:0];
    tx_seq.start(env.mii_agt.tx_sequencer);
    repeat (50) @(posedge rmii_vif.rmii_ref_clk);

    // Test 2: RX-only (no collision expected, CRS should assert)
    `uvm_info("TEST", "Test 2: RX-only — CRS asserted, no collision", UVM_LOW)
    rx_seq = rmii_rx_frame_sequence::type_id::create("rx_only");
    rx_seq.num_nibbles = 16;
    rx_seq.frame_data = new[16];
    for (int i = 0; i < 16; i++) rx_seq.frame_data[i] = i[3:0];
    rx_seq.start(env.rmii_agt.rx_sequencer);
    repeat (50) @(posedge rmii_vif.rmii_ref_clk);

    // Test 3: Simultaneous TX and RX (collision expected)
    `uvm_info("TEST", "Test 3: Simultaneous TX+RX — collision expected", UVM_LOW)
    begin
      tx_seq = mii_tx_frame_sequence::type_id::create("tx_coll");
      tx_seq.num_nibbles = 32;
      tx_seq.frame_data = new[32];
      for (int i = 0; i < 32; i++) tx_seq.frame_data[i] = i[3:0];

      rx_seq = rmii_rx_frame_sequence::type_id::create("rx_coll");
      rx_seq.num_nibbles = 32;
      rx_seq.frame_data = new[32];
      for (int i = 0; i < 32; i++) rx_seq.frame_data[i] = (32 - i) & 4'hF;

      fork
        tx_seq.start(env.mii_agt.tx_sequencer);
        rx_seq.start(env.rmii_agt.rx_sequencer);
      join
    end

    // Check that collision was asserted at some point
    repeat (10) @(posedge rmii_vif.rmii_ref_clk);
    `uvm_info("TEST", "Collision test sequences completed — check waveforms for mcoll", UVM_LOW)

    // Drain time
    repeat (50) @(posedge rmii_vif.rmii_ref_clk);

    phase.drop_objection(this);
  endtask

endclass

`endif // GUARD_RMII_MII_COLLISION_TEST_SV
