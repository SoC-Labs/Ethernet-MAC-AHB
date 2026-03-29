///////////////////////////////////////////////////////////////////////////////
// wb_slave_driver.sv
///////////////////////////////////////////////////////////////////////////////
// UVM driver for the Wishbone B3 slave side.
// Responds to DUT master requests with ACK (using built-in memory model)
// or ERR based on configuration.
///////////////////////////////////////////////////////////////////////////////

`ifndef GUARD_WB_SLAVE_DRIVER_SV
`define GUARD_WB_SLAVE_DRIVER_SV

class wb_slave_driver extends uvm_driver;

  `uvm_component_utils(wb_slave_driver)

  virtual wb_slave_if.driver vif;

  // Simple memory model (associative array)
  bit [31:0] mem [bit [31:0]];

  // Configuration: number of wait states to insert (0 = immediate ACK)
  int unsigned wait_cycles = 0;

  // Configuration: inject error on specific addresses
  bit inject_errors = 0;
  int unsigned error_after = 0;
  int unsigned txn_count   = 0;

  function new(string name = "wb_slave_driver", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual wb_slave_if.driver)::get(this, "", "vif", vif))
      `uvm_fatal("NOVIF", "Virtual interface not found for wb_slave_driver")

    // Optional configuration
    void'(uvm_config_db#(int unsigned)::get(this, "", "wait_cycles", wait_cycles));
    void'(uvm_config_db#(bit)::get(this, "", "inject_errors", inject_errors));
    void'(uvm_config_db#(int unsigned)::get(this, "", "error_after", error_after));
  endfunction

  virtual task run_phase(uvm_phase phase);
    // Initialize bus to idle
    vif.drv_cb.ack   <= 1'b0;
    vif.drv_cb.err   <= 1'b0;
    vif.drv_cb.dat_i <= 32'h0;

    forever begin
      @(vif.drv_cb);

      // Wait for valid bus cycle
      if (vif.drv_cb.cyc && vif.drv_cb.stb) begin
        txn_count++;

        // Insert wait states
        repeat (wait_cycles) begin
          vif.drv_cb.ack <= 1'b0;
          vif.drv_cb.err <= 1'b0;
          @(vif.drv_cb);
        end

        // Check for error injection
        if (inject_errors && txn_count > error_after) begin
          vif.drv_cb.err <= 1'b1;
          vif.drv_cb.ack <= 1'b0;
          `uvm_info("WB_SLV_DRV", $sformatf("Injecting ERR for txn %0d addr=0x%08h",
            txn_count, vif.drv_cb.adr), UVM_MEDIUM)
        end else begin
          // Normal response
          if (vif.drv_cb.we) begin
            // Write: store data
            mem[vif.drv_cb.adr] = vif.drv_cb.dat_o;
            `uvm_info("WB_SLV_DRV", $sformatf("WRITE addr=0x%08h data=0x%08h",
              vif.drv_cb.adr, vif.drv_cb.dat_o), UVM_HIGH)
          end else begin
            // Read: return stored data (or 0 if uninitialized)
            if (mem.exists(vif.drv_cb.adr))
              vif.drv_cb.dat_i <= mem[vif.drv_cb.adr];
            else
              vif.drv_cb.dat_i <= 32'h0;
            `uvm_info("WB_SLV_DRV", $sformatf("READ addr=0x%08h data=0x%08h",
              vif.drv_cb.adr, mem.exists(vif.drv_cb.adr) ? mem[vif.drv_cb.adr] : 32'h0), UVM_HIGH)
          end
          vif.drv_cb.ack <= 1'b1;
          vif.drv_cb.err <= 1'b0;
        end

        // Deassert after one cycle
        @(vif.drv_cb);
        vif.drv_cb.ack <= 1'b0;
        vif.drv_cb.err <= 1'b0;
      end else begin
        vif.drv_cb.ack <= 1'b0;
        vif.drv_cb.err <= 1'b0;
      end
    end
  endtask

endclass

`endif // GUARD_WB_SLAVE_DRIVER_SV
