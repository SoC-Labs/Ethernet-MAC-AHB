///////////////////////////////////////////////////////////////////////////////
// wb_burst_read_sequence.sv
///////////////////////////////////////////////////////////////////////////////

`ifndef GUARD_WB_BURST_READ_SEQUENCE_SV
`define GUARD_WB_BURST_READ_SEQUENCE_SV

class wb_burst_read_sequence extends wb_base_sequence;

  rand bit [31:0] addr;

  constraint c_word_aligned { addr[1:0] == 2'b00; }

  `uvm_object_utils(wb_burst_read_sequence)

  function new(string name = "wb_burst_read_sequence");
    super.new(name);
  endfunction

  virtual task body();
    `uvm_info("SEQ", $sformatf("Burst read: addr=0x%08h", addr), UVM_MEDIUM)
    burst_read(addr);
  endtask

endclass

`endif // GUARD_WB_BURST_READ_SEQUENCE_SV
