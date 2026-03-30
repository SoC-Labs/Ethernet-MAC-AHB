///////////////////////////////////////////////////////////////////////////////
// rmii_mii_scoreboard.sv
///////////////////////////////////////////////////////////////////////////////
// UVM scoreboard for the rmii_to_mii adapter.
//
// Verifies two independent data paths:
//   TX path (MII → RMII): MII TX driver reference vs RMII TX monitor output
//   RX path (RMII → MII): RMII RX driver reference vs MII RX monitor output
//
// Transactions are matched in FIFO order.  Only active (enable=1)
// transactions are compared.
///////////////////////////////////////////////////////////////////////////////

`ifndef GUARD_RMII_MII_SCOREBOARD_SV
`define GUARD_RMII_MII_SCOREBOARD_SV

`uvm_analysis_imp_decl(_mii_tx)
`uvm_analysis_imp_decl(_rmii_tx)
`uvm_analysis_imp_decl(_rmii_rx)
`uvm_analysis_imp_decl(_mii_rx)

class rmii_mii_scoreboard extends uvm_scoreboard;

  `uvm_component_utils(rmii_mii_scoreboard)

  // TX path: MII driver (expected) → RMII monitor (actual)
  uvm_analysis_imp_mii_tx  #(nibble_transaction, rmii_mii_scoreboard) mii_tx_export;
  uvm_analysis_imp_rmii_tx #(nibble_transaction, rmii_mii_scoreboard) rmii_tx_export;

  // RX path: RMII driver (expected) → MII monitor (actual)
  uvm_analysis_imp_rmii_rx #(nibble_transaction, rmii_mii_scoreboard) rmii_rx_export;
  uvm_analysis_imp_mii_rx  #(nibble_transaction, rmii_mii_scoreboard) mii_rx_export;

  // FIFO queues
  nibble_transaction tx_expected[$];
  nibble_transaction tx_actual[$];
  nibble_transaction rx_expected[$];
  nibble_transaction rx_actual[$];

  // Counters
  int unsigned tx_match, tx_mismatch;
  int unsigned rx_match, rx_mismatch;
  int unsigned tx_exp_count, tx_act_count;
  int unsigned rx_exp_count, rx_act_count;

  function new(string name = "rmii_mii_scoreboard", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    mii_tx_export  = new("mii_tx_export",  this);
    rmii_tx_export = new("rmii_tx_export", this);
    rmii_rx_export = new("rmii_rx_export", this);
    mii_rx_export  = new("mii_rx_export",  this);
  endfunction

  // -----------------------------------------------------------------
  // TX path write callbacks
  // -----------------------------------------------------------------
  virtual function void write_mii_tx(nibble_transaction tr);
    if (tr.enable) begin
      nibble_transaction t;
      $cast(t, tr.clone());
      tx_expected.push_back(t);
      tx_exp_count++;
      try_match_tx();
    end
  endfunction

  virtual function void write_rmii_tx(nibble_transaction tr);
    if (tr.enable) begin
      nibble_transaction t;
      $cast(t, tr.clone());
      tx_actual.push_back(t);
      tx_act_count++;
      try_match_tx();
    end
  endfunction

  // -----------------------------------------------------------------
  // RX path write callbacks
  // -----------------------------------------------------------------
  virtual function void write_rmii_rx(nibble_transaction tr);
    if (tr.enable) begin
      nibble_transaction t;
      $cast(t, tr.clone());
      rx_expected.push_back(t);
      rx_exp_count++;
      try_match_rx();
    end
  endfunction

  virtual function void write_mii_rx(nibble_transaction tr);
    if (tr.enable) begin
      nibble_transaction t;
      $cast(t, tr.clone());
      rx_actual.push_back(t);
      rx_act_count++;
      try_match_rx();
    end
  endfunction

  // -----------------------------------------------------------------
  // TX path matcher
  // -----------------------------------------------------------------
  virtual function void try_match_tx();
    while (tx_expected.size() > 0 && tx_actual.size() > 0) begin
      nibble_transaction exp = tx_expected.pop_front();
      nibble_transaction act = tx_actual.pop_front();

      if (exp.data === act.data) begin
        tx_match++;
        `uvm_info("SB_TX_MATCH", $sformatf("TX nibble matched: 0x%01h", exp.data), UVM_HIGH)
      end else begin
        tx_mismatch++;
        `uvm_error("SB_TX_MISMATCH", $sformatf(
          "TX data mismatch: expected=0x%01h actual=0x%01h", exp.data, act.data))
      end
    end
  endfunction

  // -----------------------------------------------------------------
  // RX path matcher
  // -----------------------------------------------------------------
  virtual function void try_match_rx();
    while (rx_expected.size() > 0 && rx_actual.size() > 0) begin
      nibble_transaction exp = rx_expected.pop_front();
      nibble_transaction act = rx_actual.pop_front();

      if (exp.data === act.data) begin
        rx_match++;
        `uvm_info("SB_RX_MATCH", $sformatf("RX nibble matched: 0x%01h", exp.data), UVM_HIGH)
      end else begin
        rx_mismatch++;
        `uvm_error("SB_RX_MISMATCH", $sformatf(
          "RX data mismatch: expected=0x%01h actual=0x%01h", exp.data, act.data))
      end
    end
  endfunction

  // -----------------------------------------------------------------
  // Report
  // -----------------------------------------------------------------
  virtual function void report_phase(uvm_phase phase);
    `uvm_info("SB_REPORT", $sformatf({
      "\n---------- Scoreboard Summary ----------",
      "\n  TX expected:  %0d", "\n  TX actual:    %0d",
      "\n  TX matches:   %0d", "\n  TX mismatches:%0d",
      "\n  TX unmatched: exp=%0d act=%0d",
      "\n  RX expected:  %0d", "\n  RX actual:    %0d",
      "\n  RX matches:   %0d", "\n  RX mismatches:%0d",
      "\n  RX unmatched: exp=%0d act=%0d",
      "\n-----------------------------------------"},
      tx_exp_count, tx_act_count, tx_match, tx_mismatch,
      tx_expected.size(), tx_actual.size(),
      rx_exp_count, rx_act_count, rx_match, rx_mismatch,
      rx_expected.size(), rx_actual.size()), UVM_LOW)

    if (tx_mismatch > 0)
      `uvm_error("SB_REPORT", $sformatf("%0d TX mismatches detected", tx_mismatch))
    if (rx_mismatch > 0)
      `uvm_error("SB_REPORT", $sformatf("%0d RX mismatches detected", rx_mismatch))
    if (tx_expected.size() > 0 || tx_actual.size() > 0)
      `uvm_warning("SB_REPORT", $sformatf("TX path: %0d unmatched expected, %0d unmatched actual",
        tx_expected.size(), tx_actual.size()))
    if (rx_expected.size() > 0 || rx_actual.size() > 0)
      `uvm_warning("SB_REPORT", $sformatf("RX path: %0d unmatched expected, %0d unmatched actual",
        rx_expected.size(), rx_actual.size()))
  endfunction

endclass

`endif // GUARD_RMII_MII_SCOREBOARD_SV
