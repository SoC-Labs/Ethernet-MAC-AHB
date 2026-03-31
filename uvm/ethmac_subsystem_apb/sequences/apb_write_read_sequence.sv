///////////////////////////////////////////////////////////////////////////////
// apb_write_read_sequence.sv — Write then readback
///////////////////////////////////////////////////////////////////////////////

`ifndef GUARD_APB_WRITE_READ_SEQUENCE_SV
`define GUARD_APB_WRITE_READ_SEQUENCE_SV

class apb_write_read_sequence extends svt_apb_master_base_sequence;
  rand bit [31:0] addr;
  rand bit [31:0] data;

  `uvm_object_utils(apb_write_read_sequence)

  function new(string name = "apb_write_read_sequence");
    super.new(name);
  endfunction

  virtual task body();
    integer status;

    // Write
    `uvm_create(req)
    status = req.randomize() with {
      xact_type == svt_apb_transaction::WRITE;
      address   == local::addr;
      data      == local::data;
      pstrb     == 4'hF;
    };
    if (!status) `uvm_fatal("SEQ", "Randomize write failed")
    `uvm_send(req)

    // Read back
    `uvm_create(req)
    status = req.randomize() with {
      xact_type == svt_apb_transaction::READ;
      address   == local::addr;
    };
    if (!status) `uvm_fatal("SEQ", "Randomize read failed")
    `uvm_send(req)
  endtask
endclass

`endif
