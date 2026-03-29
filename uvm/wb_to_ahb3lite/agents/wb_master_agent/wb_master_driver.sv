///////////////////////////////////////////////////////////////////////////////
// wb_master_driver.sv
///////////////////////////////////////////////////////////////////////////////
// UVM driver for Wishbone B3 master transactions.
// Converts wb_master_transaction items into WB signal-level protocol.
///////////////////////////////////////////////////////////////////////////////

`ifndef GUARD_WB_MASTER_DRIVER_SV
`define GUARD_WB_MASTER_DRIVER_SV

class wb_master_driver extends uvm_driver #(wb_master_transaction);

  `uvm_component_utils(wb_master_driver)

  virtual wb_master_if.driver vif;

  // WB B3 Cycle Type Identifier encodings
  localparam [2:0] CTI_CLASSIC = 3'b000;
  localparam [2:0] CTI_INCR    = 3'b010;
  localparam [2:0] CTI_EOB     = 3'b111;

  // Timeout for ack/err (in clock cycles)
  int unsigned ack_timeout = 64;

  function new(string name = "wb_master_driver", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual wb_master_if.driver)::get(this, "", "vif", vif))
      `uvm_fatal("NOVIF", "Virtual interface not found for wb_master_driver")
  endfunction

  virtual task run_phase(uvm_phase phase);
    // Initialize bus to idle
    drive_idle();

    forever begin
      seq_item_port.get_next_item(req);
      `uvm_info("WB_DRV", $sformatf("Driving %s %s to addr 0x%08h",
        req.cycle_type.name(), req.write ? "WRITE" : "READ", req.addr), UVM_MEDIUM)

      if (req.cycle_type == WB_CLASSIC)
        drive_classic(req);
      else
        drive_incr4(req);

      seq_item_port.item_done();
    end
  endtask

  // Drive bus to idle state
  virtual task drive_idle();
    @(vif.drv_cb);
    vif.drv_cb.cyc   <= 1'b0;
    vif.drv_cb.stb   <= 1'b0;
    vif.drv_cb.adr   <= 32'h0;
    vif.drv_cb.dat_o <= 32'h0;
    vif.drv_cb.we    <= 1'b0;
    vif.drv_cb.sel   <= 4'h0;
    vif.drv_cb.cti   <= CTI_CLASSIC;
    vif.drv_cb.bte   <= 2'b00;
  endtask

  // Drive a classic single-beat WB transfer
  virtual task drive_classic(wb_master_transaction tr);
    int timeout_cnt;

    @(vif.drv_cb);
    vif.drv_cb.cyc   <= 1'b1;
    vif.drv_cb.stb   <= 1'b1;
    vif.drv_cb.adr   <= tr.addr;
    vif.drv_cb.we    <= tr.write;
    vif.drv_cb.sel   <= tr.sel;
    vif.drv_cb.cti   <= CTI_CLASSIC;
    vif.drv_cb.bte   <= 2'b00;
    if (tr.write)
      vif.drv_cb.dat_o <= tr.data[0];

    // Wait for ack or err
    timeout_cnt = 0;
    do begin
      @(vif.drv_cb);
      timeout_cnt++;
      if (timeout_cnt >= ack_timeout) begin
        `uvm_error("WB_DRV", $sformatf("Timeout waiting for ACK/ERR on classic transfer to 0x%08h", tr.addr))
        break;
      end
    end while (!vif.drv_cb.ack && !vif.drv_cb.err);

    // Capture response
    if (vif.drv_cb.err) begin
      tr.error = 1'b1;
    end else begin
      tr.error = 1'b0;
      if (!tr.write) begin
        tr.rdata = new[1];
        tr.rdata[0] = vif.drv_cb.dat_i;
      end
    end

    // Return bus to idle
    drive_idle();
  endtask

  // Drive a 4-beat INCR4 burst WB B3 transfer
  virtual task drive_incr4(wb_master_transaction tr);
    int timeout_cnt;
    bit [31:0] beat_addr;

    tr.rdata = new[4];
    tr.error = 1'b0;

    for (int beat = 0; beat < 4; beat++) begin
      beat_addr = tr.addr + (beat * 4);

      @(vif.drv_cb);
      vif.drv_cb.cyc   <= 1'b1;
      vif.drv_cb.stb   <= 1'b1;
      vif.drv_cb.adr   <= beat_addr;
      vif.drv_cb.we    <= tr.write;
      vif.drv_cb.sel   <= tr.sel;
      vif.drv_cb.bte   <= 2'b00;

      // CTI: 010 for beats 0-2, 111 for final beat
      if (beat < 3)
        vif.drv_cb.cti <= CTI_INCR;
      else
        vif.drv_cb.cti <= CTI_EOB;

      if (tr.write)
        vif.drv_cb.dat_o <= tr.data[beat];

      // Wait for ack or err
      timeout_cnt = 0;
      do begin
        @(vif.drv_cb);
        timeout_cnt++;
        if (timeout_cnt >= ack_timeout) begin
          `uvm_error("WB_DRV", $sformatf("Timeout waiting for ACK/ERR on burst beat %0d to 0x%08h", beat, beat_addr))
          drive_idle();
          return;
        end
      end while (!vif.drv_cb.ack && !vif.drv_cb.err);

      if (vif.drv_cb.err) begin
        tr.error = 1'b1;
        `uvm_info("WB_DRV", $sformatf("Error on burst beat %0d", beat), UVM_MEDIUM)
        drive_idle();
        return;
      end

      if (!tr.write)
        tr.rdata[beat] = vif.drv_cb.dat_i;
    end

    // Return bus to idle
    drive_idle();
  endtask

endclass

`endif // GUARD_WB_MASTER_DRIVER_SV
