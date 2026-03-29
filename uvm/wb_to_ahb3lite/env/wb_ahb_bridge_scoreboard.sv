///////////////////////////////////////////////////////////////////////////////
// wb_ahb_bridge_scoreboard.sv
///////////////////////////////////////////////////////////////////////////////
// UVM scoreboard for the wb_to_ahb3lite bridge.
//
// Receives WB transactions from the WB monitor and AHB transactions from
// the VIP's passive master monitor. Compares them in FIFO order to verify
// the bridge correctly translates protocol, addresses, data, and burst types.
///////////////////////////////////////////////////////////////////////////////

`ifndef GUARD_WB_AHB_BRIDGE_SCOREBOARD_SV
`define GUARD_WB_AHB_BRIDGE_SCOREBOARD_SV

// Analysis imp declarations must be outside the class
`uvm_analysis_imp_decl(_wb)
`uvm_analysis_imp_decl(_ahb)

class wb_ahb_bridge_scoreboard extends uvm_scoreboard;

  `uvm_component_utils(wb_ahb_bridge_scoreboard)

  uvm_analysis_imp_wb  #(wb_master_transaction, wb_ahb_bridge_scoreboard) wb_export;
  uvm_analysis_imp_ahb #(svt_ahb_transaction, wb_ahb_bridge_scoreboard) ahb_export;

  // FIFO queues for transaction matching
  wb_master_transaction         wb_queue[$];
  svt_ahb_master_transaction    ahb_queue[$];

  // Counters
  int unsigned match_count;
  int unsigned mismatch_count;
  int unsigned wb_count;
  int unsigned ahb_count;

  function new(string name = "wb_ahb_bridge_scoreboard", uvm_component parent = null);
    super.new(name, parent);
    match_count    = 0;
    mismatch_count = 0;
    wb_count       = 0;
    ahb_count      = 0;
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    wb_export  = new("wb_export", this);
    ahb_export = new("ahb_export", this);
  endfunction

  // Called when WB monitor captures a transaction
  virtual function void write_wb(wb_master_transaction tr);
    wb_count++;
    wb_queue.push_back(tr);
    try_match();
  endfunction

  // Called when VIP passive master monitor captures an AHB transaction
  virtual function void write_ahb(svt_ahb_transaction tr);
    svt_ahb_master_transaction mtr;
    if (!$cast(mtr, tr))
      `uvm_fatal("SB_CAST", "Failed to cast svt_ahb_transaction to svt_ahb_master_transaction")
    ahb_count++;
    ahb_queue.push_back(mtr);
    try_match();
  endfunction

  // Try to match WB and AHB transactions in FIFO order.
  // The DUT drives NONSEQ on idle (ctrlstart stuck high), producing
  // phantom AHB transactions. Skip AHB entries whose address+direction
  // don't match the head of the WB queue.
  virtual function void try_match();
    while (wb_queue.size() > 0 && ahb_queue.size() > 0) begin
      wb_master_transaction         wb_tr  = wb_queue[0];
      svt_ahb_master_transaction    ahb_tr = ahb_queue[0];
      bit ahb_is_write = (ahb_tr.xact_type == svt_ahb_transaction::WRITE);

      if (wb_tr.addr == ahb_tr.addr && wb_tr.write == ahb_is_write) begin
        // Address and direction match — compare
        wb_queue.pop_front();
        ahb_queue.pop_front();
        compare_transactions(wb_tr, ahb_tr);
      end else begin
        // Discard phantom AHB from DUT idle behaviour
        ahb_queue.pop_front();
        `uvm_info("SB_PHANTOM", $sformatf(
          "Discarding phantom AHB: addr=0x%08h type=%s",
          ahb_tr.addr, ahb_tr.xact_type.name()), UVM_MEDIUM)
      end
    end
  endfunction

  virtual function void compare_transactions(
    wb_master_transaction wb_tr,
    svt_ahb_master_transaction ahb_tr
  );
    bit pass = 1;

    // Check address
    if (wb_tr.addr !== ahb_tr.addr) begin
      `uvm_error("SB_ADDR", $sformatf(
        "Address mismatch: WB=0x%08h, AHB=0x%08h", wb_tr.addr, ahb_tr.addr))
      pass = 0;
    end

    // Check write/read direction
    if (wb_tr.write !== (ahb_tr.xact_type == svt_ahb_transaction::WRITE)) begin
      `uvm_error("SB_DIR", $sformatf(
        "Direction mismatch: WB write=%0b, AHB xact_type=%s",
        wb_tr.write, ahb_tr.xact_type.name()))
      pass = 0;
    end

    // Check burst type mapping
    if (wb_tr.cycle_type == WB_CLASSIC) begin
      if (ahb_tr.burst_type !== svt_ahb_transaction::SINGLE) begin
        `uvm_error("SB_BURST", $sformatf(
          "Burst mismatch: WB=CLASSIC but AHB burst_type=%s",
          ahb_tr.burst_type.name()))
        pass = 0;
      end
    end else begin // WB_INCR4
      if (ahb_tr.burst_type !== svt_ahb_transaction::INCR4) begin
        `uvm_error("SB_BURST", $sformatf(
          "Burst mismatch: WB=INCR4 but AHB burst_type=%s",
          ahb_tr.burst_type.name()))
        pass = 0;
      end
    end

    // Check data
    if (wb_tr.write) begin
      if (!check_write_data(wb_tr, ahb_tr)) pass = 0;
    end else if (!wb_tr.error) begin
      if (!check_read_data(wb_tr, ahb_tr)) pass = 0;
    end

    if (pass) begin
      match_count++;
      `uvm_info("SB_MATCH", $sformatf(
        "Transaction matched: %s %s addr=0x%08h",
        wb_tr.cycle_type.name(), wb_tr.write ? "WRITE" : "READ",
        wb_tr.addr), UVM_MEDIUM)
    end else begin
      mismatch_count++;
    end
  endfunction

  virtual function bit check_write_data(
    wb_master_transaction wb_tr,
    svt_ahb_master_transaction ahb_tr
  );
    bit ok = 1;
    int num_beats = wb_tr.data.size();
    for (int i = 0; i < num_beats && i < ahb_tr.data.size(); i++) begin
      if (wb_tr.data[i] !== ahb_tr.data[i]) begin
        `uvm_error("SB_WDATA", $sformatf(
          "Write data mismatch at beat %0d: WB=0x%08h, AHB=0x%08h",
          i, wb_tr.data[i], ahb_tr.data[i]))
        ok = 0;
      end
    end
    return ok;
  endfunction

  virtual function bit check_read_data(
    wb_master_transaction wb_tr,
    svt_ahb_master_transaction ahb_tr
  );
    bit ok = 1;
    int num_beats = wb_tr.rdata.size();
    for (int i = 0; i < num_beats && i < ahb_tr.data.size(); i++) begin
      if (wb_tr.rdata[i] !== ahb_tr.data[i]) begin
        `uvm_error("SB_RDATA", $sformatf(
          "Read data mismatch at beat %0d: WB=0x%08h, AHB=0x%08h",
          i, wb_tr.rdata[i], ahb_tr.data[i]))
        ok = 0;
      end
    end
    return ok;
  endfunction

  virtual function void report_phase(uvm_phase phase);
    `uvm_info("SB_REPORT", $sformatf(
      "\n---------- Scoreboard Summary ----------\n  WB transactions:  %0d\n  AHB transactions: %0d\n  Matches:          %0d\n  Mismatches:       %0d\n  Unmatched WB:     %0d\n  Unmatched AHB:    %0d\n-----------------------------------------",
      wb_count, ahb_count, match_count, mismatch_count,
      wb_queue.size(), ahb_queue.size()), UVM_LOW)

    if (mismatch_count > 0)
      `uvm_error("SB_REPORT", $sformatf("%0d mismatches detected", mismatch_count))
    if (wb_queue.size() > 0)
      `uvm_warning("SB_REPORT", $sformatf("%0d unmatched WB transactions", wb_queue.size()))
    if (ahb_queue.size() > 0)
      `uvm_warning("SB_REPORT", $sformatf("%0d unmatched AHB transactions", ahb_queue.size()))
  endfunction

endclass

`endif // GUARD_WB_AHB_BRIDGE_SCOREBOARD_SV
