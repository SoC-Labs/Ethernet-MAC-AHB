///////////////////////////////////////////////////////////////////////////////
// wb_master_transaction.sv
///////////////////////////////////////////////////////////////////////////////
// UVM sequence item for Wishbone B3 master transactions.
///////////////////////////////////////////////////////////////////////////////

`ifndef GUARD_WB_MASTER_TRANSACTION_SV
`define GUARD_WB_MASTER_TRANSACTION_SV

typedef enum bit {
  WB_CLASSIC = 1'b0,
  WB_INCR4   = 1'b1
} wb_cycle_type_e;

class wb_master_transaction extends uvm_sequence_item;

  // Stimulus fields
  rand bit [31:0]       addr;
  rand bit [31:0]       data[];
  rand bit              write;
  rand wb_cycle_type_e  cycle_type;
  rand bit [3:0]        sel;

  // Inter-transaction gap: number of idle clock cycles before this transfer
  rand int unsigned     idle_cycles;

  // Response fields (filled by driver/monitor)
  bit [31:0] rdata[];
  bit        error;

  // Constraints
  constraint c_word_aligned {
    addr[1:0] == 2'b00;
  }

  // INCR4 burst (4 beats x 4 bytes = 16 bytes) must not cross 1KB boundary
  constraint c_no_1kb_crossing {
    if (cycle_type == WB_INCR4) {
      addr[9:0] <= (10'h400 - 10'h10);
    }
  }

  constraint c_sel_default {
    sel == 4'hF;
  }

  constraint c_idle_cycles {
    idle_cycles inside {[0:3]};
  }

  constraint c_data_size {
    if (cycle_type == WB_CLASSIC) {
      data.size() == 1;
    } else {
      data.size() == 4;
    }
  }

  `uvm_object_utils_begin(wb_master_transaction)
    `uvm_field_int(addr, UVM_ALL_ON)
    `uvm_field_array_int(data, UVM_ALL_ON)
    `uvm_field_int(write, UVM_ALL_ON)
    `uvm_field_enum(wb_cycle_type_e, cycle_type, UVM_ALL_ON)
    `uvm_field_int(sel, UVM_ALL_ON)
    `uvm_field_int(idle_cycles, UVM_ALL_ON)
    `uvm_field_array_int(rdata, UVM_ALL_ON)
    `uvm_field_int(error, UVM_ALL_ON)
  `uvm_object_utils_end

  function new(string name = "wb_master_transaction");
    super.new(name);
  endfunction

endclass

`endif // GUARD_WB_MASTER_TRANSACTION_SV
