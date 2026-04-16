///////////////////////////////////////////////////////////////////////////////
// eth_rx_cksum_if.sv — virtual interface bundling APB + MII signals.
///////////////////////////////////////////////////////////////////////////////

interface eth_rx_cksum_if (
  input logic pclk,
  input logic mrx_clk
);
  logic        presetn;
  logic        mrx_rstn;

  logic        apb_psel;
  logic        apb_penable;
  logic [31:0] apb_paddr;
  logic        apb_pwrite;
  logic [31:0] apb_pwdata;
  logic  [3:0] apb_pstrb;
  logic [31:0] apb_prdata;
  logic        apb_pready;
  logic        apb_pslverr;

  logic  [3:0] mrxd;
  logic        mrxdv;
  logic        mrxerr;

  logic        cksum_int_o;
endinterface
