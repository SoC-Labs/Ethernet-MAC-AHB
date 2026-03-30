///////////////////////////////////////////////////////////////////////////////
// mii_tx_frame_sequence.sv
///////////////////////////////////////////////////////////////////////////////
// Sends a burst of active nibbles followed by an idle gap on the MII TX
// path, simulating a single Ethernet frame's worth of data through the
// adapter.
///////////////////////////////////////////////////////////////////////////////

`ifndef GUARD_MII_TX_FRAME_SEQUENCE_SV
`define GUARD_MII_TX_FRAME_SEQUENCE_SV

class mii_tx_frame_sequence extends uvm_sequence #(nibble_transaction);

  rand int unsigned num_nibbles;
  rand bit [3:0]    frame_data[];

  constraint c_len       { num_nibbles inside {[8:128]}; }
  constraint c_data_size { frame_data.size() == num_nibbles; }

  `uvm_object_utils(mii_tx_frame_sequence)

  function new(string name = "mii_tx_frame_sequence");
    super.new(name);
  endfunction

  virtual task body();
    `uvm_info("SEQ", $sformatf("MII TX frame: %0d nibbles", num_nibbles), UVM_MEDIUM)

    // Active data
    for (int i = 0; i < num_nibbles; i++) begin
      `uvm_do_with(req, {
        data   == local::frame_data[i];
        enable == 1;
        error  == 0;
      })
    end

    // Inter-frame idle gap (12 bytes = 24 nibbles at MII rate)
    repeat (24) begin
      `uvm_do_with(req, {
        enable == 0;
        error  == 0;
      })
    end
  endtask

endclass

`endif // GUARD_MII_TX_FRAME_SEQUENCE_SV
