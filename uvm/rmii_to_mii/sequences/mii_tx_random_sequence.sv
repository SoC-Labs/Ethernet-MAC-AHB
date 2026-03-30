///////////////////////////////////////////////////////////////////////////////
// mii_tx_random_sequence.sv
///////////////////////////////////////////////////////////////////////////////
// Sends multiple randomised frames on the MII TX path.
///////////////////////////////////////////////////////////////////////////////

`ifndef GUARD_MII_TX_RANDOM_SEQUENCE_SV
`define GUARD_MII_TX_RANDOM_SEQUENCE_SV

class mii_tx_random_sequence extends uvm_sequence #(nibble_transaction);

  rand int unsigned num_frames;

  constraint c_frames { num_frames inside {[5:20]}; }

  `uvm_object_utils(mii_tx_random_sequence)

  function new(string name = "mii_tx_random_sequence");
    super.new(name);
  endfunction

  virtual task body();
    `uvm_info("SEQ", $sformatf("MII TX random: %0d frames", num_frames), UVM_MEDIUM)

    for (int i = 0; i < num_frames; i++) begin
      mii_tx_frame_sequence frame_seq;
      frame_seq = mii_tx_frame_sequence::type_id::create($sformatf("frame_%0d", i));
      frame_seq.start(m_sequencer);
    end
  endtask

endclass

`endif // GUARD_MII_TX_RANDOM_SEQUENCE_SV
