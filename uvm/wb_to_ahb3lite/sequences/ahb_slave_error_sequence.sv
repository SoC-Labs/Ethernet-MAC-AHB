///////////////////////////////////////////////////////////////////////////////
// ahb_slave_error_sequence.sv
///////////////////////////////////////////////////////////////////////////////
// AHB slave sequence that injects ERROR responses after a configurable
// number of OKAY responses, to test the DUT's error handling.
///////////////////////////////////////////////////////////////////////////////

`ifndef GUARD_AHB_SLAVE_ERROR_SEQUENCE_SV
`define GUARD_AHB_SLAVE_ERROR_SEQUENCE_SV

class ahb_slave_error_sequence extends svt_ahb_slave_transaction_base_sequence;

  // Inject error after this many OKAY responses
  int unsigned error_after = 3;

  // Counter
  int unsigned txn_count = 0;

  `uvm_object_utils_begin(ahb_slave_error_sequence)
    `uvm_field_int(error_after, UVM_ALL_ON)
  `uvm_object_utils_end

  function new(string name = "ahb_slave_error_sequence");
    super.new(name);
  endfunction

  virtual task body();
    integer status;
    svt_configuration get_cfg;
    svt_ahb_slave_transaction req_resp;

    `uvm_info("body", $sformatf("AHB slave error sequence started (error after %0d OKAYs)", error_after), UVM_LOW)

    p_sequencer.get_cfg(get_cfg);
    if (!$cast(cfg, get_cfg))
      `uvm_fatal("body", "Unable to $cast configuration to svt_ahb_port_configuration")

    forever begin
      p_sequencer.response_request_port.peek(req_resp);

      txn_count++;

      if (txn_count > error_after) begin
        // Inject ERROR response
        status = req_resp.randomize with {
          num_wait_cycles == 0;
          response_type == svt_ahb_slave_transaction::ERROR;
        };
        `uvm_info("body", $sformatf("Injecting ERROR response for txn %0d", txn_count), UVM_MEDIUM)
      end else begin
        // Normal OKAY response
        status = req_resp.randomize with {
          num_wait_cycles == 0;
          response_type == svt_ahb_slave_transaction::OKAY;
        };

        if (req_resp.xact_type == svt_ahb_slave_transaction::WRITE)
          put_write_transaction_data_to_mem(req_resp);
        else
          get_read_data_from_mem_to_transaction(req_resp);
      end

      if (!status)
        `uvm_fatal("body", "Unable to randomize slave response")

      $cast(req, req_resp);
      `uvm_send(req)
    end
  endtask

endclass

`endif // GUARD_AHB_SLAVE_ERROR_SEQUENCE_SV
