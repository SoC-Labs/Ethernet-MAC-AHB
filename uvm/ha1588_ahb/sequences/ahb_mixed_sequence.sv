///////////////////////////////////////////////////////////////////////////////
// ahb_mixed_sequence.sv
///////////////////////////////////////////////////////////////////////////////
// Constrained-random mix of writes and reads to HA1588 registers.
///////////////////////////////////////////////////////////////////////////////

`ifndef GUARD_HA1588_AHB_MIXED_SEQUENCE_SV
`define GUARD_HA1588_AHB_MIXED_SEQUENCE_SV

class ahb_mixed_sequence extends svt_ahb_master_transaction_base_sequence;

  rand int unsigned num_transfers;

  constraint c_num { num_transfers inside {[20:200]}; }

  // RW register addresses (word-aligned)
  bit [31:0] rw_addrs[] = '{
    32'h04, 32'h10, 32'h14, 32'h18, 32'h1C,
    32'h20, 32'h24, 32'h28, 32'h2C, 32'h30
  };

  `uvm_object_utils(ahb_mixed_sequence)

  function new(string name = "ahb_mixed_sequence");
    super.new(name);
  endfunction

  virtual task body();
    integer status;
    svt_configuration get_cfg;
    int addr_idx;
    bit do_write;

    `uvm_info("SEQ", $sformatf("AHB mixed: %0d transfers", num_transfers), UVM_LOW)

    p_sequencer.get_cfg(get_cfg);
    if (!$cast(cfg, get_cfg))
      `uvm_fatal("body", "Unable to $cast configuration")

    for (int i = 0; i < num_transfers; i++) begin
      addr_idx = $urandom_range(0, rw_addrs.size() - 1);
      do_write = $urandom_range(0, 1);

      `uvm_create(req)
      if (do_write) begin
        status = req.randomize() with {
          xact_type  == svt_ahb_transaction::WRITE;
          burst_type == svt_ahb_transaction::SINGLE;
          burst_size == svt_ahb_transaction::BURST_SIZE_32BIT;
          addr       == rw_addrs[local::addr_idx];
          data.size() == 1;
        };
      end else begin
        status = req.randomize() with {
          xact_type  == svt_ahb_transaction::READ;
          burst_type == svt_ahb_transaction::SINGLE;
          burst_size == svt_ahb_transaction::BURST_SIZE_32BIT;
          addr       == rw_addrs[local::addr_idx];
          data.size() == 1;
        };
      end

      if (!status)
        `uvm_fatal("body", "Unable to randomize AHB transaction")
      `uvm_send(req)
    end
  endtask

endclass

`endif
