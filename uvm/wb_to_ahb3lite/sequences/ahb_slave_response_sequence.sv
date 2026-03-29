///////////////////////////////////////////////////////////////////////////////
// ahb_slave_response_sequence.sv
///////////////////////////////////////////////////////////////////////////////
// Default AHB slave response sequence using the SVT VIP built-in memory.
// Responds with OKAY and zero wait states.
///////////////////////////////////////////////////////////////////////////////

`ifndef GUARD_AHB_SLAVE_RESPONSE_SEQUENCE_SV
`define GUARD_AHB_SLAVE_RESPONSE_SEQUENCE_SV

class ahb_slave_response_sequence extends svt_ahb_slave_transaction_base_sequence;

  `uvm_object_utils(ahb_slave_response_sequence)

  function new(string name = "ahb_slave_response_sequence");
    super.new(name);
  endfunction

  virtual task body();
    integer status;
    svt_configuration get_cfg;
    svt_ahb_slave_transaction req_resp;

    `uvm_info("body", "AHB slave memory response sequence started", UVM_LOW)

    p_sequencer.get_cfg(get_cfg);
    if (!$cast(cfg, get_cfg))
      `uvm_fatal("body", "Unable to $cast configuration to svt_ahb_port_configuration")

    forever begin
      // Get response request from slave monitor
      p_sequencer.response_request_port.peek(req_resp);

      // OKAY response with no wait states
      status = req_resp.randomize with {
        num_wait_cycles == 0;
        response_type == svt_ahb_slave_transaction::OKAY;
      };
      if (!status)
        `uvm_fatal("body", "Unable to randomize slave response")

      // Use built-in memory for data storage/retrieval
      if (req_resp.xact_type == svt_ahb_slave_transaction::WRITE)
        put_write_transaction_data_to_mem(req_resp);
      else
        get_read_data_from_mem_to_transaction(req_resp);

      $cast(req, req_resp);
      `uvm_send(req)
    end
  endtask

endclass

`endif // GUARD_AHB_SLAVE_RESPONSE_SEQUENCE_SV
