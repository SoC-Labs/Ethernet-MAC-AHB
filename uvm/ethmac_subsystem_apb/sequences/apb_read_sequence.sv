///////////////////////////////////////////////////////////////////////////////
// apb_read_sequence.sv — Single APB read
///////////////////////////////////////////////////////////////////////////////

`ifndef GUARD_APB_READ_SEQUENCE_SV
`define GUARD_APB_READ_SEQUENCE_SV

class apb_read_sequence extends svt_apb_master_base_sequence;
  rand bit [31:0] addr;
  bit [31:0] rdata;  // captured after completion

  `uvm_object_utils(apb_read_sequence)

  function new(string name = "apb_read_sequence");
    super.new(name);
  endfunction

  virtual task body();
    integer status;
    `uvm_info("SEQ", $sformatf("APB READ  0x%08h", addr), UVM_MEDIUM)
    `uvm_create(req)
    status = req.randomize() with {
      xact_type == svt_apb_transaction::READ;
      address   == local::addr;
    };
    if (!status) `uvm_fatal("SEQ", "Randomize failed")
    `uvm_send(req)
    get_response(rsp);
    rdata = rsp.data;
  endtask
endclass

`endif
