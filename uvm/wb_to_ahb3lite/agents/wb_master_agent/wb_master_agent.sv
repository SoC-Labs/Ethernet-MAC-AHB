///////////////////////////////////////////////////////////////////////////////
// wb_master_agent.sv
///////////////////////////////////////////////////////////////////////////////
// UVM agent for the Wishbone B3 master interface.
// Wraps driver, monitor, and sequencer.
///////////////////////////////////////////////////////////////////////////////

`ifndef GUARD_WB_MASTER_AGENT_SV
`define GUARD_WB_MASTER_AGENT_SV

class wb_master_agent extends uvm_agent;

  `uvm_component_utils(wb_master_agent)

  wb_master_driver    driver;
  wb_master_monitor   monitor;
  wb_master_sequencer sequencer;

  uvm_analysis_port #(wb_master_transaction) ap;

  function new(string name = "wb_master_agent", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    monitor = wb_master_monitor::type_id::create("monitor", this);
    ap = new("ap", this);

    if (get_is_active() == UVM_ACTIVE) begin
      driver    = wb_master_driver::type_id::create("driver", this);
      sequencer = wb_master_sequencer::type_id::create("sequencer", this);
    end
  endfunction

  virtual function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);

    monitor.ap.connect(ap);

    if (get_is_active() == UVM_ACTIVE) begin
      driver.seq_item_port.connect(sequencer.seq_item_export);
    end
  endfunction

endclass

`endif // GUARD_WB_MASTER_AGENT_SV
