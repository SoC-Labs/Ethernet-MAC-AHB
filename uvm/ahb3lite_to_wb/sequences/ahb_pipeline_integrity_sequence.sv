///////////////////////////////////////////////////////////////////////////////
// ahb_pipeline_integrity_sequence.sv
///////////////////////////////////////////////////////////////////////////////
// AHB master sequence: write unique data to N addresses, then read all back
// in a burst. Designed to expose the AHB address-pipeline overwrite bug
// where the bridge changes the WB address mid-transaction during
// back-to-back reads.
//
// After the read phase, the sequence self-checks by comparing each read
// result against the expected value (from the write phase).
///////////////////////////////////////////////////////////////////////////////

`ifndef GUARD_AHB_PIPELINE_INTEGRITY_SEQUENCE_SV
`define GUARD_AHB_PIPELINE_INTEGRITY_SEQUENCE_SV

class ahb_pipeline_integrity_sequence extends svt_ahb_master_transaction_base_sequence;

  rand int unsigned num_transfers;
  rand bit [31:0]   base_addr;

  constraint c_reasonable {
    num_transfers inside {[4:16]};
    base_addr[1:0] == 2'b00;
  }

  `uvm_object_utils(ahb_pipeline_integrity_sequence)

  function new(string name = "ahb_pipeline_integrity_sequence");
    super.new(name);
  endfunction

  virtual task body();
    integer status;
    svt_configuration get_cfg;
    bit [31:0] tgt_addr;
    bit [31:0] tgt_data;

    // Stored expected values
    bit [31:0] expected_data [bit [31:0]];

    `uvm_info("SEQ", $sformatf(
      "Pipeline integrity: %0d writes then %0d reads from 0x%08h",
      num_transfers, num_transfers, base_addr), UVM_LOW)

    p_sequencer.get_cfg(get_cfg);
    if (!$cast(cfg, get_cfg))
      `uvm_fatal("body", "Unable to $cast configuration to svt_ahb_port_configuration")

    // ---- Write phase: unique data per address ----
    for (int i = 0; i < num_transfers; i++) begin
      tgt_addr = base_addr + (i * 4);
      tgt_data = 32'hBEEF_0000 | (i * 32'h111);
      expected_data[tgt_addr] = tgt_data;

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
      get_response(rsp);
    end

    // ---- Read phase: back-to-back reads ----
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
      get_response(rsp);

      // Self-check: compare returned data against expected
      begin
        svt_ahb_master_transaction rd_rsp;
        bit [31:0] got;
        bit [31:0] exp;

        if (!$cast(rd_rsp, rsp))
          `uvm_fatal("body", "Unable to cast response")

        got = rd_rsp.data[0][31:0];
        exp = expected_data[tgt_addr];

        if (got !== exp) begin
          `uvm_error("PIPE_CHK", $sformatf(
            "PIPELINE BUG: addr=0x%08h expected=0x%08h got=0x%08h (stale data from wrong address)",
            tgt_addr, exp, got))
        end else begin
          `uvm_info("PIPE_CHK", $sformatf(
            "OK: addr=0x%08h data=0x%08h", tgt_addr, got), UVM_MEDIUM)
        end
      end
    end
  endtask

endclass

`endif // GUARD_AHB_PIPELINE_INTEGRITY_SEQUENCE_SV
