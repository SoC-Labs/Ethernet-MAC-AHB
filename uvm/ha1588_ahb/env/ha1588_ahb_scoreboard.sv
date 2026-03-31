///////////////////////////////////////////////////////////////////////////////
// ha1588_ahb_scoreboard.sv
///////////////////////////////////////////////////////////////////////////////
// UVM scoreboard for the ha1588_ahb testbench.
//
// Monitors AHB transactions from the VIP master and maintains a simple
// register model. Verifies write-readback consistency for RW registers.
///////////////////////////////////////////////////////////////////////////////

`ifndef GUARD_HA1588_AHB_SCOREBOARD_SV
`define GUARD_HA1588_AHB_SCOREBOARD_SV

`uvm_analysis_imp_decl(_ahb)

class ha1588_ahb_scoreboard extends uvm_scoreboard;

  `uvm_component_utils(ha1588_ahb_scoreboard)

  uvm_analysis_imp_ahb #(svt_ahb_transaction, ha1588_ahb_scoreboard) ahb_export;

  // Simple register shadow for write-readback checking
  bit [31:0] reg_shadow[bit [31:0]];
  bit        reg_written[bit [31:0]];

  // Counters
  int unsigned write_count;
  int unsigned read_count;
  int unsigned match_count;
  int unsigned mismatch_count;

  function new(string name = "ha1588_ahb_scoreboard", uvm_component parent = null);
    super.new(name, parent);
    write_count    = 0;
    read_count     = 0;
    match_count    = 0;
    mismatch_count = 0;
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    ahb_export = new("ahb_export", this);
  endfunction

  virtual function void write_ahb(svt_ahb_transaction tr);
    svt_ahb_master_transaction mtr;
    bit [31:0] addr;
    bit [31:0] data;

    if (tr.trans_type == svt_ahb_transaction::IDLE)
      return;

    if (!$cast(mtr, tr))
      `uvm_fatal("SB_CAST", "Failed to cast to svt_ahb_master_transaction")

    addr = mtr.addr;

    if (mtr.xact_type == svt_ahb_transaction::WRITE) begin
      write_count++;
      if (mtr.data.size() > 0) begin
        data = mtr.data[0][31:0];
        reg_shadow[addr]  = data;
        reg_written[addr] = 1;
        `uvm_info("SB_WRITE", $sformatf(
          "WRITE addr=0x%08h data=0x%08h", addr, data), UVM_MEDIUM)
      end
    end else begin
      read_count++;
      if (mtr.data.size() > 0) begin
        data = mtr.data[0][31:0];
        // Only check registers we have previously written
        // (status/read-only registers may differ from what was written)
        if (reg_written.exists(addr) && is_rw_register(addr)) begin
          if (data == reg_shadow[addr]) begin
            match_count++;
            `uvm_info("SB_MATCH", $sformatf(
              "READ  addr=0x%08h data=0x%08h (matches shadow)",
              addr, data), UVM_MEDIUM)
          end else begin
            mismatch_count++;
            `uvm_error("SB_MISMATCH", $sformatf(
              "READ  addr=0x%08h data=0x%08h expected=0x%08h",
              addr, data, reg_shadow[addr]))
          end
        end else begin
          `uvm_info("SB_READ", $sformatf(
            "READ  addr=0x%08h data=0x%08h (no shadow check)",
            addr, data), UVM_MEDIUM)
        end
      end
    end
  endfunction

  // Identify pure read-write registers (not control/status with side effects)
  function bit is_rw_register(bit [31:0] addr);
    case (addr)
      32'h04: return 1;  // SCRATCH
      32'h10: return 1;  // TIME_SEC_H
      32'h14: return 1;  // TIME_SEC_L
      32'h18: return 1;  // TIME_NSC_H
      32'h1C: return 1;  // TIME_NSC_L
      32'h20: return 1;  // PERIOD_H
      32'h24: return 1;  // PERIOD_L
      32'h28: return 1;  // ADJ_PERIOD_H
      32'h2C: return 1;  // ADJ_PERIOD_L
      32'h30: return 1;  // ADJ_NUM
      default: return 0;
    endcase
  endfunction

  virtual function void report_phase(uvm_phase phase);
    `uvm_info("SB_REPORT", $sformatf(
      "\n---------- Scoreboard Summary ----------\n  Writes:      %0d\n  Reads:       %0d\n  Matches:     %0d\n  Mismatches:  %0d\n-----------------------------------------",
      write_count, read_count, match_count, mismatch_count), UVM_LOW)

    if (mismatch_count > 0)
      `uvm_error("SB_REPORT", $sformatf("%0d mismatches detected", mismatch_count))
  endfunction

endclass

`endif // GUARD_HA1588_AHB_SCOREBOARD_SV
