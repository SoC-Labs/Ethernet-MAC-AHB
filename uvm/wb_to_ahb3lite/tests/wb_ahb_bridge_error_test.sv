///////////////////////////////////////////////////////////////////////////////
// wb_ahb_bridge_error_test.sv
///////////////////////////////////////////////////////////////////////////////
// Tests AHB error response handling through the bridge.
///////////////////////////////////////////////////////////////////////////////

`ifndef GUARD_WB_AHB_BRIDGE_ERROR_TEST_SV
`define GUARD_WB_AHB_BRIDGE_ERROR_TEST_SV

class wb_ahb_bridge_error_test extends wb_ahb_bridge_base_test;

  `uvm_component_utils(wb_ahb_bridge_error_test)

  function new(string name = "wb_ahb_bridge_error_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    // Override slave sequence to inject errors after 3 OKAY responses
    uvm_config_db#(uvm_object_wrapper)::set(this,
      "env.ahb_sys_env.slave*.sequencer.run_phase",
      "default_sequence",
      ahb_slave_error_sequence::type_id::get());

    // Configure error injection point
    uvm_config_db#(int unsigned)::set(this,
      "env.ahb_sys_env.slave*.sequencer.ahb_slave_error_sequence",
      "error_after", 3);
  endfunction

  virtual task main_phase(uvm_phase phase);
    wb_single_write_sequence  wr_seq;
    wb_burst_write_sequence   bwr_seq;

    phase.raise_objection(this);

    `uvm_info("TEST", "=== Error Response Test ===", UVM_LOW)

    // First 3 transfers should succeed (OKAY)
    `uvm_info("TEST", "Sending 3 OKAY transfers...", UVM_LOW)
    for (int i = 0; i < 3; i++) begin
      wr_seq = wb_single_write_sequence::type_id::create($sformatf("wr_seq_%0d", i));
      wr_seq.addr = i * 4;
      wr_seq.data = 32'hAA00_0000 + i;
      wr_seq.start(env.wb_agt.sequencer);
    end

    // 4th transfer should get ERROR
    `uvm_info("TEST", "Sending transfer that should get ERROR...", UVM_LOW)
    wr_seq = wb_single_write_sequence::type_id::create("wr_seq_err");
    wr_seq.addr = 32'h0000_0100;
    wr_seq.data = 32'hBEEF_DEAD;
    wr_seq.start(env.wb_agt.sequencer);

    // Burst that should get ERROR
    `uvm_info("TEST", "Sending burst that should get ERROR...", UVM_LOW)
    bwr_seq = wb_burst_write_sequence::type_id::create("bwr_seq_err");
    bwr_seq.addr = 32'h0000_0200;
    bwr_seq.data = '{32'h1111, 32'h2222, 32'h3333, 32'h4444};
    bwr_seq.start(env.wb_agt.sequencer);

    repeat (20) @(posedge vif.clk);
    phase.drop_objection(this);
  endtask

endclass

`endif // GUARD_WB_AHB_BRIDGE_ERROR_TEST_SV
