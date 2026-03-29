///////////////////////////////////////////////////////////////////////////////
// wb_master_if.sv
///////////////////////////////////////////////////////////////////////////////
// SystemVerilog interface for Wishbone B3 master bus signals.
///////////////////////////////////////////////////////////////////////////////

interface wb_master_if (
  input logic clk,
  input logic rst_n
);

  // Wishbone signals (active master drives adr/dat_o/sel/we/cyc/stb/cti/bte)
  logic [31:0] adr;
  logic [31:0] dat_o;   // Write data from master
  logic [31:0] dat_i;   // Read data to master
  logic [3:0]  sel;
  logic        we;
  logic        cyc;
  logic        stb;
  logic        ack;
  logic        err;
  logic [2:0]  cti;
  logic [1:0]  bte;

  // Driver clocking block
  clocking drv_cb @(posedge clk);
    default input #1step output #0;
    output adr, dat_o, sel, we, cyc, stb, cti, bte;
    input  dat_i, ack, err;
  endclocking

  // Monitor clocking block
  clocking mon_cb @(posedge clk);
    default input #1step;
    input adr, dat_o, dat_i, sel, we, cyc, stb, ack, err, cti, bte;
  endclocking

  // Modports
  modport driver  (clocking drv_cb, input clk, input rst_n);
  modport monitor (clocking mon_cb, input clk, input rst_n);

endinterface
