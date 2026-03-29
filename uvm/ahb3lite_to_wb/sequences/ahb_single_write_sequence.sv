///////////////////////////////////////////////////////////////////////////////
// ahb_single_write_sequence.sv
///////////////////////////////////////////////////////////////////////////////
// AHB master sequence: single-beat write transfer.
///////////////////////////////////////////////////////////////////////////////

`ifndef GUARD_AHB_SINGLE_WRITE_SEQUENCE_SV
`define GUARD_AHB_SINGLE_WRITE_SEQUENCE_SV

class ahb_single_write_sequence extends svt_ahb_master_transaction_base_sequence;

  rand bit [31:0] addr;
  rand bit [31:0] data;

  constraint c_word_aligned { addr[1:0] == 2'b00; }

  `uvm_object_utils(ahb_single_write_sequence)

  function new(string name = "ahb_single_write_sequence");
    super.new(name);
  endfunction

  virtual task body();
    svt_ahb_master_transaction xact;

    `uvm_info("SEQ", $sformatf("AHB single write: addr=0x%08h data=0x%08h", addr, data), UVM_MEDIUM)

    `uvm_create(req)
    req.cfg = cfg;
    req.xact_type  = svt_ahb_transaction::WRITE;
    req.burst_type = svt_ahb_transaction::SINGLE;
    req.burst_size = svt_ahb_transaction::BURST_SIZE_32BIT;
    req.addr       = addr;
    req.data       = new[1];
    req.data[0]    = data;
    `uvm_send(req)
  endtask

endclass

`endif // GUARD_AHB_SINGLE_WRITE_SEQUENCE_SV
