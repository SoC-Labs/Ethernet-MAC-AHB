///////////////////////////////////////////////////////////////////////////////
// rmii_tx_monitor.sv
///////////////////////////////////////////////////////////////////////////////
// Passive UVM monitor for the RMII transmit path (DUT → PHY).
// Collects two consecutive 2-bit RMII samples per MII clock cycle and
// reassembles them into a 4-bit nibble_transaction for the scoreboard.
//
// Phase tracking: the monitor maintains an internal phase counter that
// starts at 0 after reset, matching the DUT's tx_phase.  Phase 0 = low
// nibble, phase 1 = high nibble.
///////////////////////////////////////////////////////////////////////////////

`ifndef GUARD_RMII_TX_MONITOR_SV
`define GUARD_RMII_TX_MONITOR_SV

class rmii_tx_monitor extends uvm_monitor;

  `uvm_component_utils(rmii_tx_monitor)

  virtual rmii_if.tx_monitor vif;

  uvm_analysis_port #(nibble_transaction) ap;

  function new(string name = "rmii_tx_monitor", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    ap = new("ap", this);
    if (!uvm_config_db#(virtual rmii_if.tx_monitor)::get(this, "", "vif", vif))
      `uvm_fatal("NOVIF", "Virtual interface not found for rmii_tx_monitor")
  endfunction

  virtual task run_phase(uvm_phase phase);
    bit       internal_phase;
    bit [1:0] lo_bits;
    bit       lo_en;

    wait (vif.rst_n === 1'b1);
    internal_phase = 0;

    forever begin
      @(posedge vif.rmii_ref_clk);
      #1; // Let NBA settle

      if (!internal_phase) begin
        // Phase 0: DUT outputs low nibble
        lo_bits = vif.rmii_txd;
        lo_en   = vif.rmii_tx_en;
      end else begin
        // Phase 1: DUT outputs high nibble — assemble and publish
        if (lo_en) begin
          nibble_transaction tr = nibble_transaction::type_id::create("rmii_tx_tr");
          tr.data   = {vif.rmii_txd, lo_bits};
          tr.enable = 1;
          tr.error  = 0;

          `uvm_info("RMII_TX_MON", $sformatf("data=0x%01h", tr.data), UVM_HIGH)

          ap.write(tr);
        end
      end

      internal_phase = ~internal_phase;
    end
  endtask

endclass

`endif // GUARD_RMII_TX_MONITOR_SV
