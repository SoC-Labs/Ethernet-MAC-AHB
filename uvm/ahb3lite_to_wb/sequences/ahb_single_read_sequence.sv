///////////////////////////////////////////////////////////////////////////////
// ahb_single_read_sequence.sv
///////////////////////////////////////////////////////////////////////////////
// AHB master sequence: single-beat read transfer.
///////////////////////////////////////////////////////////////////////////////

`ifndef GUARD_AHB_SINGLE_READ_SEQUENCE_SV
`define GUARD_AHB_SINGLE_READ_SEQUENCE_SV

class ahb_single_read_sequence extends svt_ahb_master_transaction_base_sequence;

  rand bit [31:0] addr;

  constraint c_word_aligned { addr[1:0] == 2'b00; }

  `uvm_object_utils(ahb_single_read_sequence)

  function new(string name = "ahb_single_read_sequence");
    super.new(name);
  endfunction

  virtual task body();
    `uvm_info("SEQ", $sformatf("AHB single read: addr=0x%08h", addr), UVM_MEDIUM)

    `uvm_create(req)
    req.cfg = cfg;
    req.xact_type  = svt_ahb_transaction::READ;
    req.burst_type = svt_ahb_transaction::SINGLE;
    req.burst_size = svt_ahb_transaction::BURST_SIZE_32BIT;
    req.addr       = addr;
    req.data       = new[1];
    req.data[0]    = 32'h0;
    `uvm_send(req)
  endtask

endclass

`endif // GUARD_AHB_SINGLE_READ_SEQUENCE_SV
