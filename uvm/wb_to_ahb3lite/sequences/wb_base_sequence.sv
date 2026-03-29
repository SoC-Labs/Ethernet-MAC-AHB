///////////////////////////////////////////////////////////////////////////////
// wb_base_sequence.sv
///////////////////////////////////////////////////////////////////////////////
// Base sequence with utility tasks for Wishbone transactions.
///////////////////////////////////////////////////////////////////////////////

`ifndef GUARD_WB_BASE_SEQUENCE_SV
`define GUARD_WB_BASE_SEQUENCE_SV

class wb_base_sequence extends uvm_sequence #(wb_master_transaction);

  `uvm_object_utils(wb_base_sequence)
  `uvm_declare_p_sequencer(wb_master_sequencer)

  function new(string name = "wb_base_sequence");
    super.new(name);
  endfunction

  // Utility: single classic write
  virtual task single_write(bit [31:0] addr, bit [31:0] data);
    wb_master_transaction tr;
    `uvm_create(tr)
    tr.addr       = addr;
    tr.write      = 1'b1;
    tr.cycle_type = WB_CLASSIC;
    tr.sel        = 4'hF;
    tr.data       = new[1];
    tr.data[0]    = data;
    `uvm_send(tr)
  endtask

  // Utility: single classic read
  virtual task single_read(bit [31:0] addr);
    wb_master_transaction tr;
    `uvm_create(tr)
    tr.addr       = addr;
    tr.write      = 1'b0;
    tr.cycle_type = WB_CLASSIC;
    tr.sel        = 4'hF;
    tr.data       = new[1];
    tr.data[0]    = 32'h0;
    `uvm_send(tr)
  endtask

  // Utility: 4-beat INCR4 burst write
  virtual task burst_write(bit [31:0] addr, bit [31:0] data[4]);
    wb_master_transaction tr;
    `uvm_create(tr)
    tr.addr       = addr;
    tr.write      = 1'b1;
    tr.cycle_type = WB_INCR4;
    tr.sel        = 4'hF;
    tr.data       = new[4];
    foreach (data[i]) tr.data[i] = data[i];
    `uvm_send(tr)
  endtask

  // Utility: 4-beat INCR4 burst read
  virtual task burst_read(bit [31:0] addr);
    wb_master_transaction tr;
    `uvm_create(tr)
    tr.addr       = addr;
    tr.write      = 1'b0;
    tr.cycle_type = WB_INCR4;
    tr.sel        = 4'hF;
    tr.data       = new[4];
    foreach (tr.data[i]) tr.data[i] = 32'h0;
    `uvm_send(tr)
  endtask

endclass

`endif // GUARD_WB_BASE_SEQUENCE_SV
