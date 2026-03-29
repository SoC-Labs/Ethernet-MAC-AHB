///////////////////////////////////////////////////////////////////////////////
// ahb_single_read_sequence.sv
///////////////////////////////////////////////////////////////////////////////
// AHB master sequence: single-beat read transfer.
///////////////////////////////////////////////////////////////////////////////

`ifndef GUARD_AHB_SINGLE_READ_SEQUENCE_SV
`define GUARD_AHB_SINGLE_READ_SEQUENCE_SV

class ahb_single_read_sequence extends svt_ahb_master_transaction_base_sequence;

  rand bit [31:0] addr;

  constraint c_word_aligned { addr[1:0] == 2'b00; }

  `uvm_object_utils(ahb_single_read_sequence)

  function new(string name = "ahb_single_read_sequence");
    super.new(name);
  endfunction

  virtual task body();
    integer status;
    svt_configuration get_cfg;

    `uvm_info("SEQ", $sformatf("AHB single read: addr=0x%08h", addr), UVM_MEDIUM)

    p_sequencer.get_cfg(get_cfg);
    if (!$cast(cfg, get_cfg))
      `uvm_fatal("body", "Unable to $cast configuration to svt_ahb_port_configuration")

    `uvm_create(req)
    status = req.randomize() with {
      xact_type  == svt_ahb_transaction::READ;
      burst_type == svt_ahb_transaction::SINGLE;
      burst_size == svt_ahb_transaction::BURST_SIZE_32BIT;
      addr       == local::addr;
      data.size() == 1;
    };
    if (!status)
      `uvm_fatal("body", "Unable to randomize AHB read transaction")
    `uvm_send(req)
  endtask

endclass

`endif // GUARD_AHB_SINGLE_READ_SEQUENCE_SV
