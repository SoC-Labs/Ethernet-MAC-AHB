///////////////////////////////////////////////////////////////////////////////
// ahb_back_to_back_sequence.sv
///////////////////////////////////////////////////////////////////////////////
// AHB master sequence: back-to-back single transfers.
///////////////////////////////////////////////////////////////////////////////

`ifndef GUARD_AHB_BACK_TO_BACK_SEQUENCE_SV
`define GUARD_AHB_BACK_TO_BACK_SEQUENCE_SV

class ahb_back_to_back_sequence extends svt_ahb_master_transaction_base_sequence;

  rand int unsigned num_transfers;
  rand bit [31:0]   base_addr;

  constraint c_reasonable {
    num_transfers inside {[4:16]};
    base_addr[1:0] == 2'b00;
  }

  `uvm_object_utils(ahb_back_to_back_sequence)

  function new(string name = "ahb_back_to_back_sequence");
    super.new(name);
  endfunction

  virtual task body();
    integer status;
    svt_configuration get_cfg;
    bit [31:0] tgt_addr;
    bit [31:0] tgt_data;

    `uvm_info("SEQ", $sformatf("AHB back-to-back: %0d writes then %0d reads from 0x%08h",
      num_transfers, num_transfers, base_addr), UVM_MEDIUM)

    p_sequencer.get_cfg(get_cfg);
    if (!$cast(cfg, get_cfg))
      `uvm_fatal("body", "Unable to $cast configuration to svt_ahb_port_configuration")

    // Write phase
    for (int i = 0; i < num_transfers; i++) begin
      tgt_addr = base_addr + (i * 4);
      tgt_data = 32'hA000_0000 + i;
      `uvm_create(req)
      status = req.randomize() with {
        xact_type  == svt_ahb_transaction::WRITE;
        burst_type == svt_ahb_transaction::SINGLE;
        burst_size == svt_ahb_transaction::BURST_SIZE_32BIT;
        addr       == local::tgt_addr;
        data.size() == 1;
        data[0]    == local::tgt_data;
      };
      if (!status)
        `uvm_fatal("body", "Unable to randomize AHB write transaction")
      `uvm_send(req)
    end

    // Read phase
    for (int i = 0; i < num_transfers; i++) begin
      tgt_addr = base_addr + (i * 4);
      `uvm_create(req)
      status = req.randomize() with {
        xact_type  == svt_ahb_transaction::READ;
        burst_type == svt_ahb_transaction::SINGLE;
        burst_size == svt_ahb_transaction::BURST_SIZE_32BIT;
        addr       == local::tgt_addr;
        data.size() == 1;
      };
      if (!status)
        `uvm_fatal("body", "Unable to randomize AHB read transaction")
      `uvm_send(req)
    end
  endtask

endclass

`endif // GUARD_AHB_BACK_TO_BACK_SEQUENCE_SV
