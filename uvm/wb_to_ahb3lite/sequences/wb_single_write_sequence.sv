///////////////////////////////////////////////////////////////////////////////
// wb_single_write_sequence.sv
///////////////////////////////////////////////////////////////////////////////

`ifndef GUARD_WB_SINGLE_WRITE_SEQUENCE_SV
`define GUARD_WB_SINGLE_WRITE_SEQUENCE_SV

class wb_single_write_sequence extends wb_base_sequence;

  rand bit [31:0] addr;
  rand bit [31:0] data;

  constraint c_word_aligned { addr[1:0] == 2'b00; }

  `uvm_object_utils(wb_single_write_sequence)

  function new(string name = "wb_single_write_sequence");
    super.new(name);
  endfunction

  virtual task body();
    `uvm_info("SEQ", $sformatf("Single write: addr=0x%08h data=0x%08h", addr, data), UVM_MEDIUM)
    single_write(addr, data);
  endtask

endclass

`endif // GUARD_WB_SINGLE_WRITE_SEQUENCE_SV
