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

  // Clear shadow state (call after DUT reset)
  function void reset();
    reg_shadow.delete();
    reg_written.delete();
    `uvm_info("SB", "Shadow model cleared (reset)", UVM_MEDIUM)
  endfunction

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
    bit [31:0] mask;

    mask = rw_mask(addr);

    if (tr.xact_type == svt_apb_transaction::WRITE) begin
      write_count++;
      data = tr.data & mask;  // only writable bits are stored
      if (mask != 0) begin
        reg_shadow[addr]  = data;
        reg_written[addr] = 1;
      end
      `uvm_info("SB", $sformatf("WRITE 0x%08h = 0x%08h (mask 0x%08h)", addr, tr.data, mask), UVM_MEDIUM)
    end else begin
      read_count++;
      data = tr.data;
      if (reg_written.exists(addr) && mask != 0) begin
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

  // Return writable bit mask for a given register address.
  // Returns 0 for read-only or non-existent registers.
  function bit [31:0] rw_mask(bit [31:0] addr);
    case (addr)
      // ── ETH registers ──
      32'h0008: return 32'h0000_007F;  // INT_MASK      [6:0]
      32'h000C: return 32'h0000_007F;  // IPGT          [6:0]
      32'h0010: return 32'h0000_007F;  // IPGR1         [6:0]
      32'h0014: return 32'h0000_007F;  // IPGR2         [6:0]
      32'h0018: return 32'hFFFF_FFFF;  // PACKETLEN     [31:0]
      32'h0020: return 32'h0000_00FF;  // TX_BD_NUM     [7:0]
      32'h0040: return 32'hFFFF_FFFF;  // MAC_ADDR0     [31:0]
      32'h0044: return 32'h0000_FFFF;  // MAC_ADDR1     [15:0]
      32'h0048: return 32'hFFFF_FFFF;  // HASH0         [31:0]
      32'h004C: return 32'hFFFF_FFFF;  // HASH1         [31:0]
      // ── PTP registers ──
      32'h1004: return 32'hFFFF_FFFF;  // Scratch       [31:0]
      32'h1020: return 32'h0000_00FF;  // Period NS     [7:0] (reads back low byte only)
      32'h1024: return 32'hFFFF_FFFF;  // Period Frac   [31:0]
      32'h1028: return 32'h0000_00FF;  // Adj Period NS [7:0] (reads back low byte only)
      32'h102C: return 32'hFFFF_FFFF;  // Adj Frac      [31:0]
      32'h1030: return 32'hFFFF_FFFF;  // Adj Count     [31:0]
      // PTP time regs (0x1010-0x101C) are read from RTC hardware, not writable
      default:  return 32'h0;
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
