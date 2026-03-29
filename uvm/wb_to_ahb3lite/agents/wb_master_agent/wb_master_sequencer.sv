///////////////////////////////////////////////////////////////////////////////
// wb_master_sequencer.sv
///////////////////////////////////////////////////////////////////////////////
// UVM sequencer for Wishbone master transactions.
///////////////////////////////////////////////////////////////////////////////

`ifndef GUARD_WB_MASTER_SEQUENCER_SV
`define GUARD_WB_MASTER_SEQUENCER_SV

class wb_master_sequencer extends uvm_sequencer #(wb_master_transaction);

  `uvm_component_utils(wb_master_sequencer)

  function new(string name = "wb_master_sequencer", uvm_component parent = null);
    super.new(name, parent);
  endfunction

endclass

`endif // GUARD_WB_MASTER_SEQUENCER_SV
