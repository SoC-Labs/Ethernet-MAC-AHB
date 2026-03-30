///////////////////////////////////////////////////////////////////////////////
// wb_mixed_sequence.sv
///////////////////////////////////////////////////////////////////////////////
// Constrained-random mix of single and burst transfers (writes and reads).
// Primary sequence for coverage closure testing.
///////////////////////////////////////////////////////////////////////////////

`ifndef GUARD_WB_MIXED_SEQUENCE_SV
`define GUARD_WB_MIXED_SEQUENCE_SV

class wb_mixed_sequence extends wb_base_sequence;

  rand int unsigned num_transactions;

  constraint c_reasonable {
    num_transactions inside {[20:1000]};
  }

  `uvm_object_utils(wb_mixed_sequence)

  function new(string name = "wb_mixed_sequence");
    super.new(name);
  endfunction

  virtual task body();
    `uvm_info("SEQ", $sformatf("Mixed sequence: %0d transactions", num_transactions), UVM_MEDIUM)

    for (int i = 0; i < num_transactions; i++) begin
      wb_master_transaction tr;
      `uvm_do(tr)
    end
  endtask

endclass

`endif // GUARD_WB_MIXED_SEQUENCE_SV
