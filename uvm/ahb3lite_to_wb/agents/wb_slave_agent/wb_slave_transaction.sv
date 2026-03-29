///////////////////////////////////////////////////////////////////////////////
// wb_slave_transaction.sv
///////////////////////////////////////////////////////////////////////////////
// UVM sequence item for Wishbone B3 slave-side transactions.
// Captures a single Wishbone bus cycle (address phase + data phase).
///////////////////////////////////////////////////////////////////////////////

`ifndef GUARD_WB_SLAVE_TRANSACTION_SV
`define GUARD_WB_SLAVE_TRANSACTION_SV

class wb_slave_transaction extends uvm_sequence_item;

  // Observed fields (filled by monitor)
  bit [31:0] addr;
  bit [31:0] wdata;
  bit [31:0] rdata;
  bit        write;
  bit        error;
  bit [3:0]  sel;

  `uvm_object_utils_begin(wb_slave_transaction)
    `uvm_field_int(addr, UVM_ALL_ON)
    `uvm_field_int(wdata, UVM_ALL_ON)
    `uvm_field_int(rdata, UVM_ALL_ON)
    `uvm_field_int(write, UVM_ALL_ON)
    `uvm_field_int(error, UVM_ALL_ON)
    `uvm_field_int(sel, UVM_ALL_ON)
  `uvm_object_utils_end

  function new(string name = "wb_slave_transaction");
    super.new(name);
  endfunction

endclass

`endif // GUARD_WB_SLAVE_TRANSACTION_SV
