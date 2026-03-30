///////////////////////////////////////////////////////////////////////////////
// ahb_mixed_sequence.sv
///////////////////////////////////////////////////////////////////////////////
// AHB master sequence: constrained-random mix of single transfers.
// Primary sequence for coverage closure testing.
///////////////////////////////////////////////////////////////////////////////

`ifndef GUARD_AHB_MIXED_SEQUENCE_SV
`define GUARD_AHB_MIXED_SEQUENCE_SV

class ahb_mixed_sequence extends svt_ahb_master_transaction_base_sequence;

  rand int unsigned num_transactions;

  constraint c_reasonable {
    num_transactions inside {[20:1000]};
  }

  `uvm_object_utils(ahb_mixed_sequence)

  function new(string name = "ahb_mixed_sequence");
    super.new(name);
  endfunction

  virtual task body();
    integer status;
    svt_configuration get_cfg;

    `uvm_info("SEQ", $sformatf("AHB mixed sequence: %0d transactions", num_transactions), UVM_MEDIUM)

    p_sequencer.get_cfg(get_cfg);
    if (!$cast(cfg, get_cfg))
      `uvm_fatal("body", "Unable to $cast configuration to svt_ahb_port_configuration")

    for (int i = 0; i < num_transactions; i++) begin
      `uvm_create(req)
      status = req.randomize() with {
        burst_type == svt_ahb_transaction::SINGLE;
        burst_size == svt_ahb_transaction::BURST_SIZE_32BIT;
        xact_type inside {svt_ahb_transaction::WRITE, svt_ahb_transaction::READ};
        addr[1:0] == 2'b00;
        data.size() == 1;
      };
      if (!status)
        `uvm_fatal("body", "Unable to randomize AHB transaction")
      `uvm_send(req)
    end
  endtask

endclass

`endif // GUARD_AHB_MIXED_SEQUENCE_SV
