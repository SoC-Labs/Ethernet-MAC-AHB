///////////////////////////////////////////////////////////////////////////////
// wb_slave_agent.sv
///////////////////////////////////////////////////////////////////////////////
// UVM agent for the Wishbone B3 slave interface.
// Wraps driver and monitor.
///////////////////////////////////////////////////////////////////////////////

`ifndef GUARD_WB_SLAVE_AGENT_SV
`define GUARD_WB_SLAVE_AGENT_SV

class wb_slave_agent extends uvm_agent;

  `uvm_component_utils(wb_slave_agent)

  wb_slave_driver  driver;
  wb_slave_monitor monitor;

  uvm_analysis_port #(wb_slave_transaction) ap;

  function new(string name = "wb_slave_agent", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    monitor = wb_slave_monitor::type_id::create("monitor", this);
    ap = new("ap", this);

    if (get_is_active() == UVM_ACTIVE) begin
      driver = wb_slave_driver::type_id::create("driver", this);
    end
  endfunction

  virtual function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    monitor.ap.connect(ap);
  endfunction

endclass

`endif // GUARD_WB_SLAVE_AGENT_SV
