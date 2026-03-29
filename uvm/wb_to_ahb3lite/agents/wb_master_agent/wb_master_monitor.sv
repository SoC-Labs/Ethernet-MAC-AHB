///////////////////////////////////////////////////////////////////////////////
// wb_master_monitor.sv
///////////////////////////////////////////////////////////////////////////////
// Passive UVM monitor for the Wishbone B3 bus.
// Observes bus activity and reconstructs transactions for the scoreboard.
///////////////////////////////////////////////////////////////////////////////

`ifndef GUARD_WB_MASTER_MONITOR_SV
`define GUARD_WB_MASTER_MONITOR_SV

class wb_master_monitor extends uvm_monitor;

  `uvm_component_utils(wb_master_monitor)

  virtual wb_master_if.monitor vif;

  uvm_analysis_port #(wb_master_transaction) ap;

  function new(string name = "wb_master_monitor", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    ap = new("ap", this);
    if (!uvm_config_db#(virtual wb_master_if.monitor)::get(this, "", "vif", vif))
      `uvm_fatal("NOVIF", "Virtual interface not found for wb_master_monitor")
  endfunction

  virtual task run_phase(uvm_phase phase);
    forever begin
      wb_master_transaction tr;
      collect_transaction(tr);
      ap.write(tr);
    end
  endtask

  virtual task collect_transaction(output wb_master_transaction tr);
    bit [31:0] addr_queue[$];
    bit [31:0] wdata_queue[$];
    bit [31:0] rdata_queue[$];
    bit        is_write;
    bit        is_burst;
    bit        got_error;

    // Wait for cycle start (cyc & stb asserted)
    @(vif.mon_cb);
    while (!(vif.mon_cb.cyc && vif.mon_cb.stb)) begin
      @(vif.mon_cb);
    end

    // Capture first beat info
    is_write  = vif.mon_cb.we;
    is_burst  = (vif.mon_cb.cti == 3'b010);
    got_error = 1'b0;

    // Collect beats until cycle ends
    while (vif.mon_cb.cyc && vif.mon_cb.stb) begin
      if (vif.mon_cb.ack || vif.mon_cb.err) begin
        addr_queue.push_back(vif.mon_cb.adr);
        if (is_write)
          wdata_queue.push_back(vif.mon_cb.dat_o);
        else
          rdata_queue.push_back(vif.mon_cb.dat_i);

        if (vif.mon_cb.err)
          got_error = 1'b1;

        // Check if this was the last beat (CTI=111 or classic or error)
        if (vif.mon_cb.err || vif.mon_cb.cti == 3'b111 || vif.mon_cb.cti == 3'b000) begin
          @(vif.mon_cb);
          break;
        end
      end
      @(vif.mon_cb);
    end

    // Build transaction
    tr = wb_master_transaction::type_id::create("wb_mon_tr");
    tr.addr  = addr_queue[0];
    tr.write = is_write;
    tr.error = got_error;

    if (is_burst && addr_queue.size() > 1)
      tr.cycle_type = WB_INCR4;
    else
      tr.cycle_type = WB_CLASSIC;

    if (is_write) begin
      tr.data = new[wdata_queue.size()];
      foreach (wdata_queue[i]) tr.data[i] = wdata_queue[i];
    end else begin
      tr.rdata = new[rdata_queue.size()];
      foreach (rdata_queue[i]) tr.rdata[i] = rdata_queue[i];
    end

    `uvm_info("WB_MON", $sformatf("Captured %s %s addr=0x%08h beats=%0d%s",
      tr.cycle_type.name(), tr.write ? "WRITE" : "READ",
      tr.addr, is_write ? wdata_queue.size() : rdata_queue.size(),
      tr.error ? " [ERROR]" : ""), UVM_MEDIUM)
  endtask

endclass

`endif // GUARD_WB_MASTER_MONITOR_SV
