///////////////////////////////////////////////////////////////////////////////
// rmii_agent.sv
///////////////////////////////////////////////////////////////////////////////
// UVM agent for the RMII side of the rmii_to_mii adapter.
//
// Contains:
//   - RX driver  + sequencer (active: drives RMII RX to DUT)
//   - TX monitor             (passive: observes RMII TX from DUT)
//
// Exposes two analysis ports:
//   - rx_ap: driven nibbles (scoreboard reference for RX path)
//   - tx_ap: monitored nibbles (scoreboard actual for TX path)
///////////////////////////////////////////////////////////////////////////////

`ifndef GUARD_RMII_AGENT_SV
`define GUARD_RMII_AGENT_SV

class rmii_agent extends uvm_agent;

  `uvm_component_utils(rmii_agent)

  rmii_rx_driver                         rx_driver;
  uvm_sequencer #(nibble_transaction)    rx_sequencer;
  rmii_tx_monitor                        tx_monitor;

  uvm_analysis_port #(nibble_transaction) rx_ap;
  uvm_analysis_port #(nibble_transaction) tx_ap;

  function new(string name = "rmii_agent", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    tx_monitor = rmii_tx_monitor::type_id::create("tx_monitor", this);
    tx_ap = new("tx_ap", this);
    rx_ap = new("rx_ap", this);

    if (get_is_active() == UVM_ACTIVE) begin
      rx_driver    = rmii_rx_driver::type_id::create("rx_driver", this);
      rx_sequencer = uvm_sequencer#(nibble_transaction)::type_id::create("rx_sequencer", this);
    end
  endfunction

  virtual function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);

    tx_monitor.ap.connect(tx_ap);

    if (get_is_active() == UVM_ACTIVE) begin
      rx_driver.seq_item_port.connect(rx_sequencer.seq_item_export);
      rx_driver.ap.connect(rx_ap);
    end
  endfunction

endclass

`endif // GUARD_RMII_AGENT_SV
