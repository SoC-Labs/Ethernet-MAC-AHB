///////////////////////////////////////////////////////////////////////////////
// rmii_rx_random_sequence.sv
///////////////////////////////////////////////////////////////////////////////
// Sends multiple randomised frames on the RMII RX path.
///////////////////////////////////////////////////////////////////////////////

`ifndef GUARD_RMII_RX_RANDOM_SEQUENCE_SV
`define GUARD_RMII_RX_RANDOM_SEQUENCE_SV

class rmii_rx_random_sequence extends uvm_sequence #(nibble_transaction);

  rand int unsigned num_frames;

  constraint c_frames { num_frames inside {[5:20]}; }

  `uvm_object_utils(rmii_rx_random_sequence)

  function new(string name = "rmii_rx_random_sequence");
    super.new(name);
  endfunction

  virtual task body();
    `uvm_info("SEQ", $sformatf("RMII RX random: %0d frames", num_frames), UVM_MEDIUM)

    for (int i = 0; i < num_frames; i++) begin
      rmii_rx_frame_sequence frame_seq;
      frame_seq = rmii_rx_frame_sequence::type_id::create($sformatf("frame_%0d", i));
      frame_seq.start(m_sequencer);
    end
  endtask

endclass

`endif // GUARD_RMII_RX_RANDOM_SEQUENCE_SV
