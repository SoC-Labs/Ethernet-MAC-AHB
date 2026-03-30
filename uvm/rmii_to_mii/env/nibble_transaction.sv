///////////////////////////////////////////////////////////////////////////////
// nibble_transaction.sv
///////////////////////////////////////////////////////////////////////////////
// UVM sequence item representing one MII-cycle nibble (4-bit data).
// Used across both MII and RMII agents for consistent scoreboard comparison.
///////////////////////////////////////////////////////////////////////////////

`ifndef GUARD_NIBBLE_TRANSACTION_SV
`define GUARD_NIBBLE_TRANSACTION_SV

class nibble_transaction extends uvm_sequence_item;

  rand bit [3:0] data;     // 4-bit nibble
  rand bit       enable;   // TX enable or RX data valid
  rand bit       error;    // TX error or RX error

  `uvm_object_utils_begin(nibble_transaction)
    `uvm_field_int(data,   UVM_ALL_ON)
    `uvm_field_int(enable, UVM_ALL_ON)
    `uvm_field_int(error,  UVM_ALL_ON)
  `uvm_object_utils_end

  function new(string name = "nibble_transaction");
    super.new(name);
  endfunction

endclass

`endif // GUARD_NIBBLE_TRANSACTION_SV
