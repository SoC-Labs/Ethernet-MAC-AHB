///////////////////////////////////////////////////////////////////////////////
// ahb_write_read_sequence.sv
///////////////////////////////////////////////////////////////////////////////
// AHB master sequence: write then read-back to same address.
///////////////////////////////////////////////////////////////////////////////

`ifndef GUARD_AHB_WRITE_READ_SEQUENCE_SV
`define GUARD_AHB_WRITE_READ_SEQUENCE_SV

class ahb_write_read_sequence extends svt_ahb_master_transaction_base_sequence;

  rand bit [31:0] addr;
  rand bit [31:0] data;

  constraint c_word_aligned { addr[1:0] == 2'b00; }

  `uvm_object_utils(ahb_write_read_sequence)

  function new(string name = "ahb_write_read_sequence");
    super.new(name);
  endfunction

  virtual task body();
    `uvm_info("SEQ", $sformatf("AHB write-read: addr=0x%08h data=0x%08h", addr, data), UVM_MEDIUM)

    // Write
    `uvm_create(req)
    req.cfg = cfg;
    req.xact_type  = svt_ahb_transaction::WRITE;
    req.burst_type = svt_ahb_transaction::SINGLE;
    req.burst_size = svt_ahb_transaction::BURST_SIZE_32BIT;
    req.addr       = addr;
    req.data       = new[1];
    req.data[0]    = data;
    `uvm_send(req)

    // Read-back
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

`endif // GUARD_AHB_WRITE_READ_SEQUENCE_SV
