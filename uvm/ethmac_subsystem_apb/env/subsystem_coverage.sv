///////////////////////////////////////////////////////////////////////////////
// subsystem_coverage.sv — Functional coverage matching VERIFICATION_PLAN.md
///////////////////////////////////////////////////////////////////////////////

`ifndef GUARD_SUBSYSTEM_COVERAGE_SV
`define GUARD_SUBSYSTEM_COVERAGE_SV

`uvm_analysis_imp_decl(_cov_apb)

class subsystem_coverage extends uvm_component;
  `uvm_component_utils(subsystem_coverage)

  uvm_analysis_imp_cov_apb #(svt_apb_transaction, subsystem_coverage) apb_export;

  // CP1: APB mux decode
  covergroup cg_apb_mux_decode with function sample(bit [31:0] addr, bit is_write);
    cp_port: coverpoint addr[15:12] {
      bins eth_port  = {4'd0};
      bins ptp_port  = {4'd1};
      bins disabled  = {[4'd2:4'd15]};
    }
    cp_dir: coverpoint is_write {
      bins write = {1};
      bins read  = {0};
    }
    cx_port_dir: cross cp_port, cp_dir;
  endgroup

  // CP2/CP3: Register address coverage
  covergroup cg_eth_regs with function sample(bit [11:0] offset, bit is_write);
    cp_reg: coverpoint offset {
      bins moder      = {12'h000};
      bins int_source = {12'h004};
      bins int_mask   = {12'h008};
      bins ipgt       = {12'h00C};
      bins mac_addr0  = {12'h040};
      bins mac_addr1  = {12'h044};
      bins hash0      = {12'h048};
      bins hash1      = {12'h04C};
      bins bd_base    = {12'h400};
    }
    cp_dir: coverpoint is_write { bins wr = {1}; bins rd = {0}; }
    cx_reg_dir: cross cp_reg, cp_dir;
  endgroup

  covergroup cg_ptp_regs with function sample(bit [11:0] offset, bit is_write);
    cp_reg: coverpoint offset {
      bins rtc_ctrl   = {12'h000};
      bins scratch    = {12'h004};
      bins period_h   = {12'h020};
      bins period_l   = {12'h024};
      bins time_sec_h = {12'h010};
      bins time_sec_l = {12'h014};
      bins tsu_rxctrl = {12'h040};
      bins tsu_rxstat = {12'h044};
      bins tsu_txctrl = {12'h060};
    }
    cp_dir: coverpoint is_write { bins wr = {1}; bins rd = {0}; }
    cx_reg_dir: cross cp_reg, cp_dir;
  endgroup

  function new(string name = "subsystem_coverage", uvm_component parent = null);
    super.new(name, parent);
    cg_apb_mux_decode = new();
    cg_eth_regs       = new();
    cg_ptp_regs       = new();
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    apb_export = new("apb_export", this);
  endfunction

  virtual function void write_cov_apb(svt_apb_transaction tr);
    bit [31:0] addr = tr.address;
    bit is_write = (tr.xact_type == svt_apb_transaction::WRITE);

    cg_apb_mux_decode.sample(addr, is_write);

    if (addr[15:12] == 4'd0)
      cg_eth_regs.sample(addr[11:0], is_write);
    else if (addr[15:12] == 4'd1)
      cg_ptp_regs.sample(addr[11:0], is_write);
  endfunction
endclass

`endif
