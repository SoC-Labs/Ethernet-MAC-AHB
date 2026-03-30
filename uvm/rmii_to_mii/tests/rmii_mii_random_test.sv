///////////////////////////////////////////////////////////////////////////////
// rmii_mii_random_test.sv
///////////////////////////////////////////////////////////////////////////////
// Constrained-random test: concurrent random TX and RX traffic.
// Primary test for coverage closure.
///////////////////////////////////////////////////////////////////////////////

`ifndef GUARD_RMII_MII_RANDOM_TEST_SV
`define GUARD_RMII_MII_RANDOM_TEST_SV

class rmii_mii_random_test extends rmii_mii_base_test;

  `uvm_component_utils(rmii_mii_random_test)

  int unsigned num_tx_frames = 20;
  int unsigned num_rx_frames = 20;

  function new(string name = "rmii_mii_random_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual task main_phase(uvm_phase phase);
    mii_tx_random_sequence  tx_seq;
    rmii_rx_random_sequence rx_seq;

    phase.raise_objection(this);

    `uvm_info("TEST", $sformatf("=== Random Test: %0d TX frames, %0d RX frames ===",
      num_tx_frames, num_rx_frames), UVM_LOW)

    tx_seq = mii_tx_random_sequence::type_id::create("tx_random");
    tx_seq.num_frames = num_tx_frames;

    rx_seq = rmii_rx_random_sequence::type_id::create("rx_random");
    rx_seq.num_frames = num_rx_frames;

    // Run TX and RX concurrently
    fork
      tx_seq.start(env.mii_agt.tx_sequencer);
      rx_seq.start(env.rmii_agt.rx_sequencer);
    join

    // Drain time
    repeat (100) @(posedge rmii_vif.rmii_ref_clk);

    phase.drop_objection(this);
  endtask

endclass

`endif // GUARD_RMII_MII_RANDOM_TEST_SV
