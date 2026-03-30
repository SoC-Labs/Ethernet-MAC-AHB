///////////////////////////////////////////////////////////////////////////////
// mii_if.sv
///////////////////////////////////////////////////////////////////////////////
// SystemVerilog interface for the MII (Media Independent Interface) side
// of the rmii_to_mii adapter.
//
// TX signals (driven by MAC / UVM driver, inputs to DUT):
//   mtxd[3:0], mtxen, mtxerr
//
// RX signals (driven by DUT, outputs to MAC / monitored by UVM):
//   mrxd[3:0], mrxdv, mrxerr, mcoll, mcrs
//
// Clocks are DUT outputs (25 MHz, derived from 50 MHz RMII ref clock).
///////////////////////////////////////////////////////////////////////////////

interface mii_if (
  input logic mtx_clk,
  input logic mrx_clk,
  input logic rst_n
);

  // TX side (MAC → DUT)
  logic [3:0] mtxd;
  logic       mtxen;
  logic       mtxerr;

  // RX side (DUT → MAC)
  logic [3:0] mrxd;
  logic       mrxdv;
  logic       mrxerr;
  logic       mcoll;
  logic       mcrs;

  modport tx_driver  (input  mtx_clk, rst_n,
                      output mtxd, mtxen, mtxerr);
  modport rx_monitor (input  mrx_clk, rst_n,
                      input  mrxd, mrxdv, mrxerr, mcoll, mcrs);

endinterface
