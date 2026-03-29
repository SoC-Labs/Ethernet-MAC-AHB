///////////////////////////////////////////////////////////////////////////////
// ahb_wb_bridge_error_test.sv
///////////////////////////////////////////////////////////////////////////////
// Tests WB error response handling through the ahb3lite_to_wb bridge.
// Configures the WB slave agent to inject errors after a certain number
// of successful transfers.
///////////////////////////////////////////////////////////////////////////////

`ifndef GUARD_AHB_WB_BRIDGE_ERROR_TEST_SV
`define GUARD_AHB_WB_BRIDGE_ERROR_TEST_SV

class ahb_wb_bridge_error_test extends ahb_wb_bridge_base_test;

  `uvm_component_utils(ahb_wb_bridge_error_test)

  function new(string name = "ahb_wb_bridge_error_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    // Configure WB slave agent to inject errors after 3 OKAY responses
    uvm_config_db#(bit)::set(this, "env.wb_agt.driver", "inject_errors", 1);
    uvm_config_db#(int unsigned)::set(this, "env.wb_agt.driver", "error_after", 3);
  endfunction

  virtual task main_phase(uvm_phase phase);
    ahb_single_write_sequence wr_seq;

    phase.raise_objection(this);

    `uvm_info("TEST", "=== Error Response Test ===", UVM_LOW)

    // First 3 transfers should succeed (OKAY)
    `uvm_info("TEST", "Sending 3 OKAY transfers...", UVM_LOW)
    for (int i = 0; i < 3; i++) begin
      wr_seq = ahb_single_write_sequence::type_id::create($sformatf("wr_seq_%0d", i));
      wr_seq.addr = i * 4;
      wr_seq.data = 32'hAA00_0000 + i;
      wr_seq.start(env.ahb_sys_env.master[0].sequencer);
    end

    // 4th transfer should get ERROR
    `uvm_info("TEST", "Sending transfer that should get ERROR...", UVM_LOW)
    wr_seq = ahb_single_write_sequence::type_id::create("wr_seq_err");
    wr_seq.addr = 32'h0000_0100;
    wr_seq.data = 32'hBEEF_DEAD;
    wr_seq.start(env.ahb_sys_env.master[0].sequencer);

    // 5th transfer should also get ERROR
    `uvm_info("TEST", "Sending another transfer that should get ERROR...", UVM_LOW)
    wr_seq = ahb_single_write_sequence::type_id::create("wr_seq_err2");
    wr_seq.addr = 32'h0000_0200;
    wr_seq.data = 32'hDEAD_BEEF;
    wr_seq.start(env.ahb_sys_env.master[0].sequencer);

    repeat (20) @(posedge vif.clk);
    phase.drop_objection(this);
  endtask

endclass

`endif // GUARD_AHB_WB_BRIDGE_ERROR_TEST_SV
