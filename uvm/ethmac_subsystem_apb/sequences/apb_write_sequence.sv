///////////////////////////////////////////////////////////////////////////////
// apb_write_sequence.sv — Single APB write
///////////////////////////////////////////////////////////////////////////////

`ifndef GUARD_APB_WRITE_SEQUENCE_SV
`define GUARD_APB_WRITE_SEQUENCE_SV

class apb_write_sequence extends svt_apb_master_base_sequence;
  rand bit [31:0] addr;
  rand bit [31:0] data;

  `uvm_object_utils(apb_write_sequence)

  function new(string name = "apb_write_sequence");
    super.new(name);
  endfunction

  virtual task body();
    integer status;
    `uvm_info("SEQ", $sformatf("APB WRITE 0x%08h = 0x%08h", addr, data), UVM_MEDIUM)
    `uvm_create(req)
    status = req.randomize() with {
      xact_type == svt_apb_transaction::WRITE;
      address   == local::addr;
      data      == local::data;
      pstrb     == 4'hF;
    };
    if (!status) `uvm_fatal("SEQ", "Randomize failed")
    `uvm_send(req)
  endtask
endclass

`endif
