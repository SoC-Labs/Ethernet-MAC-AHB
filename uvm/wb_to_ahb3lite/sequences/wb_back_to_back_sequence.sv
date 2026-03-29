///////////////////////////////////////////////////////////////////////////////
// wb_back_to_back_sequence.sv
///////////////////////////////////////////////////////////////////////////////
// Issues multiple single transfers back-to-back to test that the bridge
// correctly returns to idle and can immediately start new transfers.
///////////////////////////////////////////////////////////////////////////////

`ifndef GUARD_WB_BACK_TO_BACK_SEQUENCE_SV
`define GUARD_WB_BACK_TO_BACK_SEQUENCE_SV

class wb_back_to_back_sequence extends wb_base_sequence;

  rand int unsigned num_transfers;
  rand bit [31:0]   base_addr;

  constraint c_reasonable {
    num_transfers inside {[4:16]};
    base_addr[1:0] == 2'b00;
  }

  `uvm_object_utils(wb_back_to_back_sequence)

  function new(string name = "wb_back_to_back_sequence");
    super.new(name);
  endfunction

  virtual task body();
    `uvm_info("SEQ", $sformatf("Back-to-back: %0d writes then %0d reads from 0x%08h",
      num_transfers, num_transfers, base_addr), UVM_MEDIUM)

    // Write phase
    for (int i = 0; i < num_transfers; i++) begin
      single_write(base_addr + (i * 4), 32'hA000_0000 + i);
    end

    // Read phase
    for (int i = 0; i < num_transfers; i++) begin
      single_read(base_addr + (i * 4));
    end
  endtask

endclass

`endif // GUARD_WB_BACK_TO_BACK_SEQUENCE_SV
