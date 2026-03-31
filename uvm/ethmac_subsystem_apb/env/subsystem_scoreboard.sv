///////////////////////////////////////////////////////////////////////////////
// subsystem_scoreboard.sv — Register shadow model for write-readback checks
///////////////////////////////////////////////////////////////////////////////

`ifndef GUARD_SUBSYSTEM_SCOREBOARD_SV
`define GUARD_SUBSYSTEM_SCOREBOARD_SV

`uvm_analysis_imp_decl(_apb)

class subsystem_scoreboard extends uvm_scoreboard;
  `uvm_component_utils(subsystem_scoreboard)

  uvm_analysis_imp_apb #(svt_apb_transaction, subsystem_scoreboard) apb_export;

  bit [31:0] reg_shadow[bit [31:0]];
  bit        reg_written[bit [31:0]];

  int unsigned write_count, read_count, match_count, mismatch_count;

  function new(string name = "subsystem_scoreboard", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    apb_export = new("apb_export", this);
    write_count = 0; read_count = 0; match_count = 0; mismatch_count = 0;
  endfunction

  virtual function void write_apb(svt_apb_transaction tr);
    bit [31:0] addr = tr.address;
    bit [31:0] data;

    if (tr.xact_type == svt_apb_transaction::WRITE) begin
      write_count++;
      data = tr.data;
      reg_shadow[addr]  = data;
      reg_written[addr] = 1;
      `uvm_info("SB", $sformatf("WRITE 0x%08h = 0x%08h", addr, data), UVM_MEDIUM)
    end else begin
      read_count++;
      data = tr.data;
      if (reg_written.exists(addr) && is_rw(addr)) begin
        if (data == reg_shadow[addr]) begin
          match_count++;
          `uvm_info("SB", $sformatf("READ  0x%08h = 0x%08h OK", addr, data), UVM_MEDIUM)
        end else begin
          mismatch_count++;
          `uvm_error("SB", $sformatf("READ  0x%08h = 0x%08h != shadow 0x%08h",
            addr, data, reg_shadow[addr]))
        end
      end
    end
  endfunction

  function bit is_rw(bit [31:0] addr);
    case (addr)
      // ETH RW registers
      32'h0008, 32'h000C, 32'h0010, 32'h0014,
      32'h0018, 32'h0020, 32'h0040, 32'h0044,
      32'h0048, 32'h004C:
        return 1;
      // PTP RW registers
      32'h1004, 32'h1010, 32'h1014, 32'h1018, 32'h101C,
      32'h1020, 32'h1024, 32'h1028, 32'h102C, 32'h1030:
        return 1;
      default: return 0;
    endcase
  endfunction

  virtual function void report_phase(uvm_phase phase);
    `uvm_info("SB", $sformatf(
      "\n--- Scoreboard ---\n  Writes: %0d  Reads: %0d  Matches: %0d  Mismatches: %0d\n",
      write_count, read_count, match_count, mismatch_count), UVM_LOW)
    if (mismatch_count > 0)
      `uvm_error("SB", $sformatf("%0d mismatches", mismatch_count))
  endfunction
endclass

`endif
