///////////////////////////////////////////////////////////////////////////////
// mii_rx_monitor.sv
///////////////////////////////////////////////////////////////////////////////
// Passive UVM monitor for the MII receive path.
// Observes mrxd[3:0], mrxdv, mrxerr on the rising edge of mrx_clk.
// Only publishes transactions when mrxdv is asserted.
///////////////////////////////////////////////////////////////////////////////

`ifndef GUARD_MII_RX_MONITOR_SV
`define GUARD_MII_RX_MONITOR_SV

class mii_rx_monitor extends uvm_monitor;

  `uvm_component_utils(mii_rx_monitor)

  virtual mii_if.rx_monitor vif;

  uvm_analysis_port #(nibble_transaction) ap;

  function new(string name = "mii_rx_monitor", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    ap = new("ap", this);
    if (!uvm_config_db#(virtual mii_if.rx_monitor)::get(this, "", "vif", vif))
      `uvm_fatal("NOVIF", "Virtual interface not found for mii_rx_monitor")
  endfunction

  virtual task run_phase(uvm_phase phase);
    wait (vif.rst_n === 1'b1);

    forever begin
      nibble_transaction tr;

      // mrxd/mrxdv are updated by DUT at negedge mrx_clk (rx_phase=1).
      // Sample at posedge mrx_clk for maximum setup margin.
      @(posedge vif.mrx_clk);
      #1; // Let NBA settle

      if (vif.mrxdv) begin
        tr = nibble_transaction::type_id::create("mii_rx_tr");
        tr.data   = vif.mrxd;
        tr.enable = 1;
        tr.error  = vif.mrxerr;

        `uvm_info("MII_RX_MON", $sformatf("data=0x%01h err=%0b crs=%0b coll=%0b",
          tr.data, vif.mrxerr, vif.mcrs, vif.mcoll), UVM_HIGH)

        ap.write(tr);
      end
    end
  endtask

endclass

`endif // GUARD_MII_RX_MONITOR_SV
