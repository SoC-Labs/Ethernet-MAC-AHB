///////////////////////////////////////////////////////////////////////////////
// wb_slave_if.sv
///////////////////////////////////////////////////////////////////////////////
// SystemVerilog interface for Wishbone B3 slave bus signals.
// The DUT drives the master side; the VIP slave agent responds.
///////////////////////////////////////////////////////////////////////////////

interface wb_slave_if (
  input logic clk,
  input logic rst_n
);

  // Wishbone signals (DUT master drives adr/dat_o/sel/we/cyc/stb)
  logic [31:0] adr;
  logic [31:0] dat_o;   // Write data from DUT master
  logic [31:0] dat_i;   // Read data from slave (VIP)
  logic [3:0]  sel;
  logic        we;
  logic        cyc;
  logic        stb;
  logic        ack;
  logic        err;

  // Driver clocking block (slave drives ack, err, dat_i)
  clocking drv_cb @(posedge clk);
    default input #1step output #0;
    input  adr, dat_o, sel, we, cyc, stb;
    output dat_i, ack, err;
  endclocking

  // Monitor clocking block
  clocking mon_cb @(posedge clk);
    default input #1step;
    input adr, dat_o, dat_i, sel, we, cyc, stb, ack, err;
  endclocking

  // Modports
  modport driver  (clocking drv_cb, input clk, input rst_n);
  modport monitor (clocking mon_cb, input clk, input rst_n);

endinterface
