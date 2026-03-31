///////////////////////////////////////////////////////////////////////////////
// apb_mixed_sequence.sv — Random writes/reads across both peripherals
///////////////////////////////////////////////////////////////////////////////

`ifndef GUARD_APB_MIXED_SEQUENCE_SV
`define GUARD_APB_MIXED_SEQUENCE_SV

class apb_mixed_sequence extends svt_apb_master_base_sequence;
  rand int unsigned num_transfers;
  constraint c_num { num_transfers inside {[50:300]}; }

  bit [31:0] rw_addrs[] = '{
    // ETH registers
    32'h0008, 32'h000C, 32'h0048, 32'h004C,
    // PTP registers
    32'h1004, 32'h1020, 32'h1024, 32'h1028, 32'h102C, 32'h1030
  };

  `uvm_object_utils(apb_mixed_sequence)

  function new(string name = "apb_mixed_sequence");
    super.new(name);
  endfunction

  virtual task body();
    integer status;
    int idx;
    bit do_write;

    for (int i = 0; i < num_transfers; i++) begin
      idx = $urandom_range(0, rw_addrs.size() - 1);
      do_write = $urandom_range(0, 1);

      `uvm_create(req)
      if (do_write) begin
        status = req.randomize() with {
          xact_type == svt_apb_transaction::WRITE;
          address   == rw_addrs[local::idx];
          pstrb     == 4'hF;
        };
      end else begin
        status = req.randomize() with {
          xact_type == svt_apb_transaction::READ;
          address   == rw_addrs[local::idx];
        };
      end
      if (!status) `uvm_fatal("SEQ", "Randomize failed")
      `uvm_send(req)
    end
  endtask
endclass

`endif
