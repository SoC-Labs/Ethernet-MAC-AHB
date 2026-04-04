///////////////////////////////////////////////////////////////////////////////
// subsystem_dut_if.sv — Observability interface for DUT status signals
///////////////////////////////////////////////////////////////////////////////
// Provides package-safe access to DUT signals that tests need to check
// (avoids hierarchical references from within a package).
///////////////////////////////////////////////////////////////////////////////

`ifndef GUARD_SUBSYSTEM_DUT_IF_SV
`define GUARD_SUBSYSTEM_DUT_IF_SV

interface subsystem_dut_if (
  input logic        clk,
  input logic        rst_n,
  input logic        int_o,
  input logic  [1:0] htrans,
  input logic [31:0] rtc_time_ptp_ns
);

  // Reset control tasks — allow tests to assert/deassert reset
  // without hierarchical references from within a package.
  task assert_reset();
    force rst_n = 1'b0;
  endtask

  task deassert_reset();
    release rst_n;
  endtask

endinterface

`endif
