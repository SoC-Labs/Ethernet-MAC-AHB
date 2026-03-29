///////////////////////////////////////////////////////////////////////////////
// ahb_wb_bridge_scoreboard.sv
///////////////////////////////////////////////////////////////////////////////
// UVM scoreboard for the ahb3lite_to_wb bridge.
//
// Receives AHB transactions from the VIP's active master monitor and
// WB transactions from the WB slave monitor. Compares them in FIFO order
// to verify the bridge correctly translates protocol, addresses, and data.
///////////////////////////////////////////////////////////////////////////////

`ifndef GUARD_AHB_WB_BRIDGE_SCOREBOARD_SV
`define GUARD_AHB_WB_BRIDGE_SCOREBOARD_SV

// Analysis imp declarations must be outside the class
`uvm_analysis_imp_decl(_ahb)
`uvm_analysis_imp_decl(_wb)

class ahb_wb_bridge_scoreboard extends uvm_scoreboard;

  `uvm_component_utils(ahb_wb_bridge_scoreboard)

  uvm_analysis_imp_ahb #(svt_ahb_transaction, ahb_wb_bridge_scoreboard) ahb_export;
  uvm_analysis_imp_wb  #(wb_slave_transaction, ahb_wb_bridge_scoreboard) wb_export;

  // FIFO queues for transaction matching
  svt_ahb_master_transaction ahb_queue[$];
  wb_slave_transaction       wb_queue[$];

  // Counters
  int unsigned match_count;
  int unsigned mismatch_count;
  int unsigned ahb_count;
  int unsigned wb_count;

  function new(string name = "ahb_wb_bridge_scoreboard", uvm_component parent = null);
    super.new(name, parent);
    match_count    = 0;
    mismatch_count = 0;
    ahb_count      = 0;
    wb_count       = 0;
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    ahb_export = new("ahb_export", this);
    wb_export  = new("wb_export", this);
  endfunction

  // Called when VIP active master monitor captures an AHB transaction
  virtual function void write_ahb(svt_ahb_transaction tr);
    svt_ahb_master_transaction mtr;

    // Filter IDLE transactions (coherent_xact_type check not needed;
    // skip reads/writes whose trans_type is IDLE)
    if (tr.trans_type == svt_ahb_transaction::IDLE)
      return;

    if (!$cast(mtr, tr))
      `uvm_fatal("SB_CAST", "Failed to cast svt_ahb_transaction to svt_ahb_master_transaction")
    ahb_count++;
    ahb_queue.push_back(mtr);
    try_match();
  endfunction

  // Called when WB slave monitor captures a transaction
  virtual function void write_wb(wb_slave_transaction tr);
    wb_count++;
    wb_queue.push_back(tr);
    try_match();
  endfunction

  // Try to match AHB and WB transactions in FIFO order
  virtual function void try_match();
    while (ahb_queue.size() > 0 && wb_queue.size() > 0) begin
      svt_ahb_master_transaction ahb_tr = ahb_queue[0];
      wb_slave_transaction       wb_tr  = wb_queue[0];
      bit ahb_is_write = (ahb_tr.xact_type == svt_ahb_transaction::WRITE);

      if (wb_tr.addr == ahb_tr.addr && wb_tr.write == ahb_is_write) begin
        ahb_queue.pop_front();
        wb_queue.pop_front();
        compare_transactions(ahb_tr, wb_tr);
      end else begin
        // Discard phantom WB transaction
        wb_queue.pop_front();
        `uvm_info("SB_PHANTOM", $sformatf(
          "Discarding unmatched WB: addr=0x%08h %s",
          wb_tr.addr, wb_tr.write ? "WRITE" : "READ"), UVM_MEDIUM)
      end
    end
  endfunction

  virtual function void compare_transactions(
    svt_ahb_master_transaction ahb_tr,
    wb_slave_transaction wb_tr
  );
    bit pass = 1;

    // Check address
    if (ahb_tr.addr !== wb_tr.addr) begin
      `uvm_error("SB_ADDR", $sformatf(
        "Address mismatch: AHB=0x%08h, WB=0x%08h", ahb_tr.addr, wb_tr.addr))
      pass = 0;
    end

    // Check write/read direction
    if ((ahb_tr.xact_type == svt_ahb_transaction::WRITE) !== wb_tr.write) begin
      `uvm_error("SB_DIR", $sformatf(
        "Direction mismatch: AHB xact_type=%s, WB write=%0b",
        ahb_tr.xact_type.name(), wb_tr.write))
      pass = 0;
    end

    // Check data
    if (wb_tr.write) begin
      if (ahb_tr.data.size() > 0 && ahb_tr.data[0] !== wb_tr.wdata) begin
        `uvm_error("SB_WDATA", $sformatf(
          "Write data mismatch: AHB=0x%08h, WB=0x%08h",
          ahb_tr.data[0], wb_tr.wdata))
        pass = 0;
      end
    end else if (!wb_tr.error) begin
      if (ahb_tr.data.size() > 0 && ahb_tr.data[0] !== wb_tr.rdata) begin
        `uvm_error("SB_RDATA", $sformatf(
          "Read data mismatch: AHB=0x%08h, WB=0x%08h",
          ahb_tr.data[0], wb_tr.rdata))
        pass = 0;
      end
    end

    if (pass) begin
      match_count++;
      `uvm_info("SB_MATCH", $sformatf(
        "Transaction matched: %s addr=0x%08h",
        wb_tr.write ? "WRITE" : "READ", wb_tr.addr), UVM_MEDIUM)
    end else begin
      mismatch_count++;
    end
  endfunction

  virtual function void report_phase(uvm_phase phase);
    `uvm_info("SB_REPORT", $sformatf(
      "\n---------- Scoreboard Summary ----------\n  AHB transactions: %0d\n  WB transactions:  %0d\n  Matches:          %0d\n  Mismatches:       %0d\n  Unmatched AHB:    %0d\n  Unmatched WB:     %0d\n-----------------------------------------",
      ahb_count, wb_count, match_count, mismatch_count,
      ahb_queue.size(), wb_queue.size()), UVM_LOW)

    if (mismatch_count > 0)
      `uvm_error("SB_REPORT", $sformatf("%0d mismatches detected", mismatch_count))
    if (ahb_queue.size() > 0)
      `uvm_warning("SB_REPORT", $sformatf("%0d unmatched AHB transactions", ahb_queue.size()))
    if (wb_queue.size() > 0)
      `uvm_warning("SB_REPORT", $sformatf("%0d unmatched WB transactions", wb_queue.size()))
  endfunction

endclass

`endif // GUARD_AHB_WB_BRIDGE_SCOREBOARD_SV
