///////////////////////////////////////////////////////////////////////////////
// mii_agent.sv
///////////////////////////////////////////////////////////////////////////////
// UVM agent for the MII side of the rmii_to_mii adapter.
//
// Contains:
//   - TX driver  + sequencer (active: drives MII TX to DUT)
//   - RX monitor             (passive: observes MII RX from DUT)
//
// Exposes two analysis ports:
//   - tx_ap: driven nibbles (scoreboard reference for TX path)
//   - rx_ap: received nibbles (scoreboard actual for RX path)
///////////////////////////////////////////////////////////////////////////////

`ifndef GUARD_MII_AGENT_SV
`define GUARD_MII_AGENT_SV

class mii_agent extends uvm_agent;

  `uvm_component_utils(mii_agent)

  mii_tx_driver                        tx_driver;
  uvm_sequencer #(nibble_transaction)  tx_sequencer;
  mii_rx_monitor                       rx_monitor;

  uvm_analysis_port #(nibble_transaction) tx_ap;
  uvm_analysis_port #(nibble_transaction) rx_ap;

  function new(string name = "mii_agent", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    rx_monitor = mii_rx_monitor::type_id::create("rx_monitor", this);
    rx_ap = new("rx_ap", this);
    tx_ap = new("tx_ap", this);

    if (get_is_active() == UVM_ACTIVE) begin
      tx_driver    = mii_tx_driver::type_id::create("tx_driver", this);
      tx_sequencer = uvm_sequencer#(nibble_transaction)::type_id::create("tx_sequencer", this);
    end
  endfunction

  virtual function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);

    rx_monitor.ap.connect(rx_ap);

    if (get_is_active() == UVM_ACTIVE) begin
      tx_driver.seq_item_port.connect(tx_sequencer.seq_item_export);
      tx_driver.ap.connect(tx_ap);
    end
  endfunction

endclass

`endif // GUARD_MII_AGENT_SV
