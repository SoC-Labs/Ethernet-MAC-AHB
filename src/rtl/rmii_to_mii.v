//-----------------------------------------------------------------------------
// rmii_to_mii.v
//-----------------------------------------------------------------------------
// RMII to MII adapter. Converts between the 2-bit 50 MHz RMII interface
// and the 4-bit 25 MHz MII interface expected by the Ethernet MAC core.
//
// RMII (50 MHz, 2-bit):
//   - Single reference clock for both TX and RX
//   - CRS_DV multiplexes carrier sense and data valid
//
// MII (25 MHz, 4-bit):
//   - Separate TX and RX clocks (25 MHz, derived from 50 MHz ref)
//   - Separate CRS and RxDV signals
//-----------------------------------------------------------------------------

module rmii_to_mii (
  input  wire        RESETn,

  // RMII side
  input  wire        rmii_ref_clk,   // 50 MHz reference clock
  output reg   [1:0] rmii_txd,       // Transmit data (2-bit)
  output reg         rmii_tx_en,     // Transmit enable
  input  wire  [1:0] rmii_rxd,       // Receive data (2-bit)
  input  wire        rmii_crs_dv,    // Carrier sense / data valid

  // MII side
  output wire        mtx_clk,        // 25 MHz transmit clock
  input  wire  [3:0] mtxd,           // Transmit data (4-bit)
  input  wire        mtxen,          // Transmit enable
  input  wire        mtxerr,         // Transmit error

  output wire        mrx_clk,        // 25 MHz receive clock
  output reg   [3:0] mrxd,           // Receive data (4-bit)
  output reg         mrxdv,          // Receive data valid
  output reg         mrxerr,         // Receive error

  output reg         mcoll,          // Collision
  output reg         mcrs            // Carrier sense
);

  //---------------------------------------------------
  // 25 MHz clock generation (divide 50 MHz by 2)
  //---------------------------------------------------
  reg clk_div2;

  always @(posedge rmii_ref_clk or negedge RESETn) begin
    if (!RESETn)
      clk_div2 <= 1'b0;
    else
      clk_div2 <= ~clk_div2;
  end

  assign mtx_clk = clk_div2;
  assign mrx_clk = clk_div2;

  //---------------------------------------------------
  // TX path: MII (4-bit @ 25 MHz) -> RMII (2-bit @ 50 MHz)
  //---------------------------------------------------
  // Latch 4-bit MII data on mtx_clk rising edge, then
  // send low nibble on first 50 MHz cycle, high nibble on second.
  reg       tx_phase;
  reg [3:0] tx_data_held;
  reg       tx_en_held;

  always @(posedge rmii_ref_clk or negedge RESETn) begin
    if (!RESETn) begin
      tx_phase     <= 1'b0;
      tx_data_held <= 4'b0000;
      tx_en_held   <= 1'b0;
      rmii_txd     <= 2'b00;
      rmii_tx_en   <= 1'b0;
    end else begin
      if (!tx_phase) begin
        // First phase: latch MII data, send low nibble
        tx_data_held <= mtxd;
        tx_en_held   <= mtxen;
        rmii_txd     <= mtxd[1:0];
        rmii_tx_en   <= mtxen;
      end else begin
        // Second phase: send high nibble
        rmii_txd     <= tx_data_held[3:2];
        rmii_tx_en   <= tx_en_held;
      end
      tx_phase <= ~tx_phase;
    end
  end

  //---------------------------------------------------
  // RX path: RMII (2-bit @ 50 MHz) -> MII (4-bit @ 25 MHz)
  //---------------------------------------------------
  // Collect two 2-bit samples per MII clock cycle and
  // present as 4-bit data on the MII receive interface.
  reg       rx_phase;
  reg [1:0] rx_data_low;
  reg       rx_dv_held;

  always @(posedge rmii_ref_clk or negedge RESETn) begin
    if (!RESETn) begin
      rx_phase    <= 1'b0;
      rx_data_low <= 2'b00;
      rx_dv_held  <= 1'b0;
      mrxd        <= 4'b0000;
      mrxdv       <= 1'b0;
      mrxerr      <= 1'b0;
    end else begin
      if (!rx_phase) begin
        // First phase: capture low nibble
        rx_data_low <= rmii_rxd;
        rx_dv_held  <= rmii_crs_dv;
      end else begin
        // Second phase: combine into 4-bit nibble
        mrxd  <= {rmii_rxd, rx_data_low};
        mrxdv <= rx_dv_held;
      end
      rx_phase <= ~rx_phase;
    end
  end

  //---------------------------------------------------
  // CRS_DV decoding and collision detection
  //---------------------------------------------------
  // RMII CRS_DV encodes both carrier sense and data valid.
  // Carrier sense is asserted whenever CRS_DV is high.
  // Collision is detected when both TX and RX are active.
  always @(posedge rmii_ref_clk or negedge RESETn) begin
    if (!RESETn) begin
      mcrs  <= 1'b0;
      mcoll <= 1'b0;
    end else begin
      mcrs  <= rmii_crs_dv;
      mcoll <= rmii_crs_dv & rmii_tx_en;
    end
  end

endmodule
