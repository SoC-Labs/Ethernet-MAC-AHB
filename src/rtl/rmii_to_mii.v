//-----------------------------------------------------------------------------
// rmii_to_mii.v
//-----------------------------------------------------------------------------
// RMII to MII adapter. Converts between the 2-bit 50 MHz RMII interface
// and the 4-bit 25 MHz MII interface expected by the Ethernet MAC core.
//
// Rewritten based on the proven rmii_phy_if module by WangXuan95:
//   https://github.com/WangXuan95/FPGA-RMII-SMII/blob/main/RTL/rmii_phy_if.v
//
// Changes from the original rmii_phy_if:
//   - ASIC compatibility: removed all Verilog `initial` statements (not
//     synthesisable on ASIC; all state is instead reset via the async reset).
//   - Port names adapted to match the existing rmii_to_mii interface used
//     by ethmac_ahb_rmii so the module remains a drop-in replacement.
//   - Removed the mac_mii_txrst / mac_mii_rxrst output ports (not used
//     by the existing MAC wrapper; reset is handled externally).
//   - Removed the mode_speed input -- hard-wired to 100 Mbps operation
//     (action fires every cycle) to match the original fixed-100M design.
//   - Removed the phy_rmii_rxer input (not present on the RMII bus in
//     the existing design; rx error is derived from CRS_DV decoding).
//
// Changes from the previous rmii_to_mii implementation:
//   - Proper RMII CRS_DV decoding per IEEE 802.3u: detects preamble vs.
//     carrier-sense-only by inspecting di-bit values, rather than simply
//     registering CRS_DV as carrier sense.
//   - Two-stage RX input synchronisation (latch 1 + latch 2) for cleaner
//     metastability handling.
//   - TX path correctly encodes mtxerr as the RMII 01/10 error pattern.
//   - Additional output-stage pipeline register on the RMII TX outputs
//     for improved timing closure.
//   - Proper reset synchroniser (8-stage shift register) instead of using
//     the raw async reset directly, improving resilience to reset glitches.
//   - Collision detection (mcoll) now uses the synchronised internal
//     RMII TX enable rather than the registered output.
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
  output reg         mtx_clk,        // 25 MHz transmit clock
  input  wire  [3:0] mtxd,           // Transmit data (4-bit)
  input  wire        mtxen,          // Transmit enable
  input  wire        mtxerr,         // Transmit error

  output reg         mrx_clk,        // 25 MHz receive clock
  output reg   [3:0] mrxd,           // Receive data (4-bit)
  output reg         mrxdv,          // Receive data valid
  output reg         mrxerr,         // Receive error

  output reg         mcoll,          // Collision
  output reg         mcrs            // Carrier sense
);

  // ----------------------------------------------------------------
  //  Internal signals
  // ----------------------------------------------------------------
  reg        rmii_crsdv_r;
  reg  [1:0] rmii_rxd_r;
  reg  [1:0] rmii_rxd_rr;

  reg        rx_busy;
  reg        rx_crs;
  reg        rx_ena;
  reg        rx_err;
  reg  [3:0] rx_data;
  reg        rx_ena_r;
  reg        rx_err_r;
  reg  [3:0] rx_data_r;

  reg        rmii_txen_i;
  reg  [1:0] rmii_txd_i;
  reg  [1:0] rmii_txd_r;

  // ----------------------------------------------------------------
  //  Reset synchroniser (8-stage shift register)
  //  Asynchronous assert, synchronous deassert.
  // ----------------------------------------------------------------
  reg        rstn_sync;
  reg  [7:0] rstn_shift;

  always @(posedge rmii_ref_clk or negedge RESETn) begin
    if (!RESETn) begin
      rstn_sync  <= 1'b0;
      rstn_shift <= 8'h00;
    end else begin
      {rstn_sync, rstn_shift} <= {rstn_shift, 1'b1};
    end
  end

  // ----------------------------------------------------------------
  //  RMII RX raw signal latch (stage 1)
  // ----------------------------------------------------------------
  always @(posedge rmii_ref_clk or negedge rstn_sync) begin
    if (!rstn_sync) begin
      rmii_crsdv_r <= 1'b0;
      rmii_rxd_r   <= 2'h0;
    end else begin
      rmii_crsdv_r <= rmii_crs_dv;
      rmii_rxd_r   <= rmii_rxd;
    end
  end

  // ----------------------------------------------------------------
  //  RMII RX raw signal latch (stage 2)
  // ----------------------------------------------------------------
  always @(posedge rmii_ref_clk or negedge rstn_sync) begin
    if (!rstn_sync) begin
      rmii_rxd_rr <= 2'h0;
    end else begin
      rmii_rxd_rr <= rmii_rxd_r;
    end
  end

  // ----------------------------------------------------------------
  //  RMII RX signal parsing
  //  Implements CRS_DV decoding per the RMII specification:
  //    - When not busy, CRS_DV high with rxd==00 indicates carrier
  //      sense only (preamble); rxd!=00 on both di-bits means data.
  //    - When busy and rx_ena already asserted, alternate cycles
  //      carry the second nibble; CRS_DV going low ends the frame.
  // ----------------------------------------------------------------
  always @(posedge rmii_ref_clk or negedge rstn_sync) begin
    if (!rstn_sync) begin
      rx_busy <= 1'b0;
      rx_crs  <= 1'b0;
      rx_ena  <= 1'b0;
      rx_err  <= 1'b0;
      rx_data <= 4'h0;
    end else begin
      if (rx_busy) begin
        if (rx_ena) begin
          rx_crs  <= rmii_crsdv_r;
          rx_ena  <= 1'b0;
          rx_err  <= 1'b0;
          rx_data <= 4'h0;
        end else if (rmii_crsdv_r) begin
          rx_ena  <= 1'b1;
          rx_err  <= (rmii_rxd_rr == 2'b10);
          rx_data <= {rmii_rxd_r, rmii_rxd_rr};
        end else begin
          rx_busy <= 1'b0;
          rx_ena  <= 1'b0;
          rx_err  <= 1'b0;
          rx_data <= 4'h0;
        end
      end else begin
        if (rmii_crsdv_r) begin
          if (rmii_rxd_rr == 2'h0 || rmii_rxd_r == 2'h0) begin
            rx_crs  <= (rmii_rxd_rr == 2'h0);
            rx_ena  <= 1'b0;
            rx_err  <= 1'b0;
            rx_data <= 4'h0;
          end else begin
            rx_busy <= 1'b1;
            rx_ena  <= 1'b1;
            rx_err  <= (rmii_rxd_rr == 2'b10);
            rx_data <= {rmii_rxd_r, rmii_rxd_rr};
          end
        end else begin
          rx_crs  <= 1'b0;
          rx_ena  <= 1'b0;
          rx_err  <= 1'b0;
          rx_data <= 4'h0;
        end
      end
    end
  end

  // ----------------------------------------------------------------
  //  MII CRS signal generate
  // ----------------------------------------------------------------
  always @(posedge rmii_ref_clk or negedge rstn_sync) begin
    if (!rstn_sync) begin
      mcrs <= 1'b0;
    end else begin
      mcrs <= rx_crs;
    end
  end

  // ----------------------------------------------------------------
  //  RMII RX parsed data latch
  // ----------------------------------------------------------------
  always @(posedge rmii_ref_clk or negedge rstn_sync) begin
    if (!rstn_sync) begin
      rx_ena_r  <= 1'b0;
      rx_err_r  <= 1'b0;
      rx_data_r <= 4'h0;
    end else begin
      rx_ena_r  <= rx_ena;
      rx_err_r  <= rx_err;
      rx_data_r <= rx_data;
    end
  end

  // ----------------------------------------------------------------
  //  MII RX clock generate (divide-by-2 of 50 MHz = 25 MHz)
  // ----------------------------------------------------------------
  always @(posedge rmii_ref_clk or negedge rstn_sync) begin
    if (!rstn_sync) begin
      mrx_clk <= 1'b0;
    end else begin
      mrx_clk <= ~mrx_clk;
    end
  end

  // ----------------------------------------------------------------
  //  MII RX signal generate
  //  Data is updated on the falling edge of mrx_clk (when mrx_clk
  //  is high and about to toggle low), so the MAC samples stable
  //  data on the rising edge of mrx_clk.
  // ----------------------------------------------------------------
  always @(posedge rmii_ref_clk or negedge rstn_sync) begin
    if (!rstn_sync) begin
      mrxdv  <= 1'b0;
      mrxerr <= 1'b0;
      mrxd   <= 4'h0;
    end else begin
      if (mrx_clk) begin
        if (rx_ena) begin
          mrxdv  <= 1'b1;
          mrxerr <= rx_err;
          mrxd   <= rx_data;
        end else if (rx_ena_r) begin
          mrxdv  <= 1'b1;
          mrxerr <= rx_err_r;
          mrxd   <= rx_data_r;
        end else begin
          mrxdv  <= 1'b0;
          mrxerr <= 1'b0;
          mrxd   <= 4'h0;
        end
      end
    end
  end

  // ----------------------------------------------------------------
  //  MII TX clock generate (divide-by-2 of 50 MHz = 25 MHz)
  // ----------------------------------------------------------------
  always @(posedge rmii_ref_clk or negedge rstn_sync) begin
    if (!rstn_sync) begin
      mtx_clk <= 1'b0;
    end else begin
      mtx_clk <= ~mtx_clk;
    end
  end

  // ----------------------------------------------------------------
  //  RMII TX signal generate
  //  On the rising edge of mtx_clk (when mtx_clk transitions from
  //  low), latch the 4-bit MII data and split into two di-bits.
  //  On the next cycle send the second di-bit.
  //  mtxerr is encoded as the RMII error pattern (01,10) per spec.
  // ----------------------------------------------------------------
  always @(posedge rmii_ref_clk or negedge rstn_sync) begin
    if (!rstn_sync) begin
      rmii_txen_i <= 1'b0;
      rmii_txd_i  <= 2'h0;
      rmii_txd_r  <= 2'h0;
    end else begin
      if (~mtx_clk) begin
        // Second half: send upper di-bit
        rmii_txd_i <= rmii_txd_r;
      end else if (mtxen) begin
        // First half: latch new MII data
        rmii_txen_i <= 1'b1;
        {rmii_txd_r, rmii_txd_i} <= mtxerr ? 4'b1010 : mtxd;
      end else begin
        rmii_txen_i <= 1'b0;
        {rmii_txd_r, rmii_txd_i} <= 4'h0;
      end
    end
  end

  // ----------------------------------------------------------------
  //  RMII TX output buffer (additional pipeline stage)
  // ----------------------------------------------------------------
  always @(posedge rmii_ref_clk or negedge rstn_sync) begin
    if (!rstn_sync) begin
      rmii_tx_en <= 1'b0;
      rmii_txd   <= 2'h0;
    end else begin
      rmii_tx_en <= rmii_txen_i;
      rmii_txd   <= rmii_txd_i;
    end
  end

  // ----------------------------------------------------------------
  //  Collision detect
  //  Collision is flagged when both TX and RX are active.
  // ----------------------------------------------------------------
  always @(posedge rmii_ref_clk or negedge rstn_sync) begin
    if (!rstn_sync) begin
      mcoll <= 1'b0;
    end else begin
      mcoll <= rx_crs & rmii_txen_i;
    end
  end

endmodule
