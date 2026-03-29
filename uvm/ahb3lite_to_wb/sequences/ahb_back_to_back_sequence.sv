///////////////////////////////////////////////////////////////////////////////
// ahb_back_to_back_sequence.sv
///////////////////////////////////////////////////////////////////////////////
// AHB master sequence: back-to-back single transfers.
///////////////////////////////////////////////////////////////////////////////

`ifndef GUARD_AHB_BACK_TO_BACK_SEQUENCE_SV
`define GUARD_AHB_BACK_TO_BACK_SEQUENCE_SV

class ahb_back_to_back_sequence extends svt_ahb_master_transaction_base_sequence;

  rand int unsigned num_transfers;
  rand bit [31:0]   base_addr;

  constraint c_reasonable {
    num_transfers inside {[4:16]};
    base_addr[1:0] == 2'b00;
  }

  `uvm_object_utils(ahb_back_to_back_sequence)

  function new(string name = "ahb_back_to_back_sequence");
    super.new(name);
  endfunction

  virtual task body();
    `uvm_info("SEQ", $sformatf("AHB back-to-back: %0d writes then %0d reads from 0x%08h",
      num_transfers, num_transfers, base_addr), UVM_MEDIUM)

    // Write phase
    for (int i = 0; i < num_transfers; i++) begin
      `uvm_create(req)
      req.cfg = cfg;
      req.xact_type  = svt_ahb_transaction::WRITE;
      req.burst_type = svt_ahb_transaction::SINGLE;
      req.burst_size = svt_ahb_transaction::BURST_SIZE_32BIT;
      req.addr       = base_addr + (i * 4);
      req.data       = new[1];
      req.data[0]    = 32'hA000_0000 + i;
      `uvm_send(req)
    end

    // Read phase
    for (int i = 0; i < num_transfers; i++) begin
      `uvm_create(req)
      req.cfg = cfg;
      req.xact_type  = svt_ahb_transaction::READ;
      req.burst_type = svt_ahb_transaction::SINGLE;
      req.burst_size = svt_ahb_transaction::BURST_SIZE_32BIT;
      req.addr       = base_addr + (i * 4);
      req.data       = new[1];
      req.data[0]    = 32'h0;
      `uvm_send(req)
    end
  endtask

endclass

`endif // GUARD_AHB_BACK_TO_BACK_SEQUENCE_SV
