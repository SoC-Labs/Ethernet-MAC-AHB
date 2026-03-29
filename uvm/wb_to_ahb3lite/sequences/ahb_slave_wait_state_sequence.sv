///////////////////////////////////////////////////////////////////////////////
// ahb_slave_wait_state_sequence.sv
///////////////////////////////////////////////////////////////////////////////
// AHB slave sequence that inserts random wait states (HREADY=0 cycles)
// to test the DUT's backpressure handling.
///////////////////////////////////////////////////////////////////////////////

`ifndef GUARD_AHB_SLAVE_WAIT_STATE_SEQUENCE_SV
`define GUARD_AHB_SLAVE_WAIT_STATE_SEQUENCE_SV

class ahb_slave_wait_state_sequence extends svt_ahb_slave_transaction_base_sequence;

  // Maximum wait states to insert per transfer
  int unsigned max_wait_cycles = 5;

  `uvm_object_utils_begin(ahb_slave_wait_state_sequence)
    `uvm_field_int(max_wait_cycles, UVM_ALL_ON)
  `uvm_object_utils_end

  function new(string name = "ahb_slave_wait_state_sequence");
    super.new(name);
  endfunction

  virtual task body();
    integer status;
    svt_configuration get_cfg;
    svt_ahb_slave_transaction req_resp;

    `uvm_info("body", $sformatf("AHB slave wait-state sequence started (max %0d wait cycles)", max_wait_cycles), UVM_LOW)

    p_sequencer.get_cfg(get_cfg);
    if (!$cast(cfg, get_cfg))
      `uvm_fatal("body", "Unable to $cast configuration to svt_ahb_port_configuration")

    forever begin
      p_sequencer.response_request_port.peek(req_resp);

      status = req_resp.randomize with {
        num_wait_cycles inside {[0:max_wait_cycles]};
        response_type == svt_ahb_slave_transaction::OKAY;
      };
      if (!status)
        `uvm_fatal("body", "Unable to randomize slave response")

      if (req_resp.xact_type == svt_ahb_slave_transaction::WRITE)
        put_write_transaction_data_to_mem(req_resp);
      else
        get_read_data_from_mem_to_transaction(req_resp);

      $cast(req, req_resp);
      `uvm_send(req)
    end
  endtask

endclass

`endif // GUARD_AHB_SLAVE_WAIT_STATE_SEQUENCE_SV
