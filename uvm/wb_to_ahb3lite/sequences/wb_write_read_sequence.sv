///////////////////////////////////////////////////////////////////////////////
// wb_write_read_sequence.sv
///////////////////////////////////////////////////////////////////////////////
// Writes data to an address, then reads it back. Useful for basic
// data integrity checking through the bridge.
///////////////////////////////////////////////////////////////////////////////

`ifndef GUARD_WB_WRITE_READ_SEQUENCE_SV
`define GUARD_WB_WRITE_READ_SEQUENCE_SV

class wb_write_read_sequence extends wb_base_sequence;

  rand bit [31:0] addr;
  rand bit [31:0] data;
  rand bit        use_burst;

  constraint c_word_aligned { addr[1:0] == 2'b00; }

  `uvm_object_utils(wb_write_read_sequence)

  function new(string name = "wb_write_read_sequence");
    super.new(name);
  endfunction

  virtual task body();
    if (use_burst) begin
      bit [31:0] burst_data[4];
      foreach (burst_data[i]) burst_data[i] = data + i;

      `uvm_info("SEQ", $sformatf("Burst write-read: addr=0x%08h", addr), UVM_MEDIUM)
      burst_write(addr, burst_data);
      burst_read(addr);
    end else begin
      `uvm_info("SEQ", $sformatf("Single write-read: addr=0x%08h data=0x%08h", addr, data), UVM_MEDIUM)
      single_write(addr, data);
      single_read(addr);
    end
  endtask

endclass

`endif // GUARD_WB_WRITE_READ_SEQUENCE_SV
