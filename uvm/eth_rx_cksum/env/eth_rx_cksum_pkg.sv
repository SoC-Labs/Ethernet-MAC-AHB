///////////////////////////////////////////////////////////////////////////////
// eth_rx_cksum_pkg.sv — UVM package for the RX Checksum Calculator block TB.
//
// Stage 5 delivers the scaffolding (env, coverage, config, sequences, tests,
// TB) so the block is addressable from a standard UVM regression. The
// coverage group below mirrors the scenarios already covered by the cocotb
// suite at cocotb/eth_rx_cksum/test_eth_rx_cksum.py — use that as the
// reference for expected register / flag combinations.
//
// No VC-VIP dependencies: the APB driver and MII source are native SV so
// the env runs wherever VCS + UVM are available.
///////////////////////////////////////////////////////////////////////////////

`ifndef GUARD_ETH_RX_CKSUM_PKG_SV
`define GUARD_ETH_RX_CKSUM_PKG_SV

package eth_rx_cksum_pkg;

  import uvm_pkg::*;
  `include "uvm_macros.svh"

  // Register offsets — mirror src/rdl/eth_rx_cksum_regs.rdl.
  parameter int unsigned OFF_ID                = 'h00;
  parameter int unsigned OFF_CTRL              = 'h04;
  parameter int unsigned OFF_STATUS            = 'h08;
  parameter int unsigned OFF_FRAME_COUNT       = 'h0C;
  parameter int unsigned OFF_IP_GOOD_COUNT     = 'h10;
  parameter int unsigned OFF_IP_BAD_COUNT      = 'h14;
  parameter int unsigned OFF_L4_GOOD_COUNT     = 'h18;
  parameter int unsigned OFF_L4_BAD_COUNT      = 'h1C;
  parameter int unsigned OFF_LAST_FRAME_INFO   = 'h20;
  parameter int unsigned OFF_LAST_IP_HDR_CKSUM = 'h28;
  parameter int unsigned OFF_LAST_L4_CKSUM     = 'h2C;
  parameter int unsigned OFF_ALIAS_SEQNUM      = 'h9C;

  parameter logic [31:0] CKSUM_ID_VALUE = 32'h434B534D; // "CKSM"

  `include "eth_rx_cksum_config.sv"
  `include "eth_rx_cksum_coverage.sv"
  `include "eth_rx_cksum_env.sv"

  `include "eth_rx_cksum_basic_seq.sv"

  `include "eth_rx_cksum_base_test.sv"
  `include "eth_rx_cksum_smoke_test.sv"

endpackage

`endif
