///////////////////////////////////////////////////////////////////////////////
// wb_slave_monitor.sv
///////////////////////////////////////////////////////////////////////////////
// Passive UVM monitor for the Wishbone B3 slave bus.
// Observes DUT master activity and reconstructs transactions for the
// scoreboard.
///////////////////////////////////////////////////////////////////////////////

`ifndef GUARD_WB_SLAVE_MONITOR_SV
`define GUARD_WB_SLAVE_MONITOR_SV

class wb_slave_monitor extends uvm_monitor;

  `uvm_component_utils(wb_slave_monitor)

  virtual wb_slave_if.monitor vif;

  uvm_analysis_port #(wb_slave_transaction) ap;

  function new(string name = "wb_slave_monitor", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    ap = new("ap", this);
    if (!uvm_config_db#(virtual wb_slave_if.monitor)::get(this, "", "vif", vif))
      `uvm_fatal("NOVIF", "Virtual interface not found for wb_slave_monitor")
  endfunction

  virtual task run_phase(uvm_phase phase);
    // Wait for reset to deassert
    @(posedge vif.rst_n);

    forever begin
      wb_slave_transaction tr;
      collect_transaction(tr);
      ap.write(tr);
    end
  endtask

  virtual task collect_transaction(output wb_slave_transaction tr);
    // Wait for valid bus cycle with ACK or ERR
    @(vif.mon_cb);
    while (!(vif.mon_cb.cyc && vif.mon_cb.stb && (vif.mon_cb.ack || vif.mon_cb.err))) begin
      @(vif.mon_cb);
    end

    tr = wb_slave_transaction::type_id::create("wb_slv_mon_tr");
    tr.addr  = vif.mon_cb.adr;
    tr.write = vif.mon_cb.we;
    tr.sel   = vif.mon_cb.sel;
    tr.error = vif.mon_cb.err;

    if (vif.mon_cb.we)
      tr.wdata = vif.mon_cb.dat_o;
    else
      tr.rdata = vif.mon_cb.dat_i;

    `uvm_info("WB_SLV_MON", $sformatf("Captured %s addr=0x%08h%s",
      tr.write ? "WRITE" : "READ", tr.addr,
      tr.error ? " [ERROR]" : ""), UVM_MEDIUM)
  endtask

endclass

`endif // GUARD_WB_SLAVE_MONITOR_SV
