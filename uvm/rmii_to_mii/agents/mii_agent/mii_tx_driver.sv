///////////////////////////////////////////////////////////////////////////////
// mii_tx_driver.sv
///////////////////////////////////////////////////////////////////////////////
// UVM driver for the MII transmit path.
// Drives mtxd[3:0], mtxen, mtxerr on the falling edge of mtx_clk so that
// data is stable when the DUT samples on the rising edge.
//
// Includes an analysis port to publish driven transactions as the reference
// for the TX-path scoreboard.
///////////////////////////////////////////////////////////////////////////////

`ifndef GUARD_MII_TX_DRIVER_SV
`define GUARD_MII_TX_DRIVER_SV

class mii_tx_driver extends uvm_driver #(nibble_transaction);

  `uvm_component_utils(mii_tx_driver)

  virtual mii_if.tx_driver vif;

  uvm_analysis_port #(nibble_transaction) ap;

  function new(string name = "mii_tx_driver", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    ap = new("ap", this);
    if (!uvm_config_db#(virtual mii_if.tx_driver)::get(this, "", "vif", vif))
      `uvm_fatal("NOVIF", "Virtual interface not found for mii_tx_driver")
  endfunction

  virtual task run_phase(uvm_phase phase);
    nibble_transaction tr;

    // Initialise to idle
    vif.mtxd   = 4'b0;
    vif.mtxen  = 1'b0;
    vif.mtxerr = 1'b0;

    // Wait for reset to deassert and mtx_clk to start toggling
    wait (vif.rst_n === 1'b1);
    @(negedge vif.mtx_clk);

    forever begin
      seq_item_port.get_next_item(tr);

      // Drive at falling edge of mtx_clk → DUT latches on next rising edge
      @(negedge vif.mtx_clk);
      vif.mtxd   <= tr.data;
      vif.mtxen  <= tr.enable;
      vif.mtxerr <= tr.error;

      // Publish for scoreboard reference
      ap.write(tr);

      `uvm_info("MII_TX_DRV", $sformatf("%s data=0x%01h",
        tr.enable ? "ACTIVE" : "IDLE", tr.data), UVM_HIGH)

      seq_item_port.item_done();
    end
  endtask

endclass

`endif // GUARD_MII_TX_DRIVER_SV
