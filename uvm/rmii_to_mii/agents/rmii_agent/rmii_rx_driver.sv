///////////////////////////////////////////////////////////////////////////////
// rmii_rx_driver.sv
///////////////////////////////////////////////////////////////////////////////
// UVM driver for the RMII receive path (PHY → DUT).
// Takes nibble_transaction items and splits each 4-bit nibble into two
// consecutive 2-bit RMII samples on rmii_rxd, synchronised to rmii_ref_clk.
//
// Phase alignment: uses phase_ref (= DUT mrx_clk = clk_div2) to
// synchronise with the DUT's rx_phase counter.  The driver drives the
// low nibble at the falling edge of phase_ref (DUT rx_phase=1→0 in NBA),
// so the DUT reads it at the next posedge where rx_phase=0 (capture).
// The high nibble is driven one rmii_ref_clk cycle later, read by the DUT
// at the following posedge where rx_phase=1 (assembly).
//
// Includes an analysis port to publish driven transactions as the reference
// for the RX-path scoreboard.
///////////////////////////////////////////////////////////////////////////////

`ifndef GUARD_RMII_RX_DRIVER_SV
`define GUARD_RMII_RX_DRIVER_SV

class rmii_rx_driver extends uvm_driver #(nibble_transaction);

  `uvm_component_utils(rmii_rx_driver)

  virtual rmii_if.rx_driver vif;

  uvm_analysis_port #(nibble_transaction) ap;

  function new(string name = "rmii_rx_driver", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    ap = new("ap", this);
    if (!uvm_config_db#(virtual rmii_if.rx_driver)::get(this, "", "vif", vif))
      `uvm_fatal("NOVIF", "Virtual interface not found for rmii_rx_driver")
  endfunction

  virtual task run_phase(uvm_phase phase);
    nibble_transaction tr;

    // Initialise to idle
    vif.rmii_rxd   = 2'b00;
    vif.rmii_crs_dv = 1'b0;

    wait (vif.rst_n === 1'b1);

    forever begin
      seq_item_port.get_next_item(tr);

      // Synchronise: wait for falling edge of phase_ref (= negedge mrx_clk).
      // At this posedge rmii_ref_clk the DUT's rx_phase was 1 (assembly),
      // so our NBA will be visible at the next posedge where rx_phase=0.
      @(negedge vif.phase_ref);
      vif.rmii_rxd    <= tr.data[1:0];
      vif.rmii_crs_dv <= tr.enable;

      // High nibble: one rmii_ref_clk later (DUT rx_phase=0 at this posedge,
      // NBA visible at next posedge where rx_phase=1 for assembly).
      @(posedge vif.rmii_ref_clk);
      vif.rmii_rxd    <= tr.data[3:2];
      vif.rmii_crs_dv <= tr.enable;

      // Publish for scoreboard reference
      ap.write(tr);

      `uvm_info("RMII_RX_DRV", $sformatf("%s data=0x%01h",
        tr.enable ? "ACTIVE" : "IDLE", tr.data), UVM_HIGH)

      seq_item_port.item_done();
    end
  endtask

endclass

`endif // GUARD_RMII_RX_DRIVER_SV
