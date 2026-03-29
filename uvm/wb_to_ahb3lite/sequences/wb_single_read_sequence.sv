///////////////////////////////////////////////////////////////////////////////
// wb_single_read_sequence.sv
///////////////////////////////////////////////////////////////////////////////

`ifndef GUARD_WB_SINGLE_READ_SEQUENCE_SV
`define GUARD_WB_SINGLE_READ_SEQUENCE_SV

class wb_single_read_sequence extends wb_base_sequence;

  rand bit [31:0] addr;

  constraint c_word_aligned { addr[1:0] == 2'b00; }

  `uvm_object_utils(wb_single_read_sequence)

  function new(string name = "wb_single_read_sequence");
    super.new(name);
  endfunction

  virtual task body();
    `uvm_info("SEQ", $sformatf("Single read: addr=0x%08h", addr), UVM_MEDIUM)
    single_read(addr);
  endtask

endclass

`endif // GUARD_WB_SINGLE_READ_SEQUENCE_SV
