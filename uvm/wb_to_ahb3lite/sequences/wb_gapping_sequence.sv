///////////////////////////////////////////////////////////////////////////////
// wb_gapping_sequence.sv
///////////////////////////////////////////////////////////////////////////////
// Constrained-random sequence that exercises inter-transaction gaps (idle
// cycles) on the Wishbone bus. Generates a mix of single and burst transfers
// with randomized idle gaps of 0-15 clock cycles between transactions.
///////////////////////////////////////////////////////////////////////////////

`ifndef GUARD_WB_GAPPING_SEQUENCE_SV
`define GUARD_WB_GAPPING_SEQUENCE_SV

class wb_gapping_sequence extends wb_base_sequence;

  rand int unsigned num_transactions;
  rand int unsigned max_gap;

  constraint c_reasonable {
    num_transactions inside {[20:500]};
    max_gap inside {[1:15]};
  }

  `uvm_object_utils(wb_gapping_sequence)

  function new(string name = "wb_gapping_sequence");
    super.new(name);
  endfunction

  virtual task body();
    `uvm_info("SEQ", $sformatf("Gapping sequence: %0d transactions, max gap %0d cycles",
      num_transactions, max_gap), UVM_MEDIUM)

    for (int i = 0; i < num_transactions; i++) begin
      wb_master_transaction tr;
      `uvm_do_with(tr, { idle_cycles inside {[0:local::max_gap]}; })
    end
  endtask

endclass

`endif // GUARD_WB_GAPPING_SEQUENCE_SV
