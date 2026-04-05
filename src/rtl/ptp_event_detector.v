// =============================================================================
// PTP Event Detector — Lightweight MII PTP Frame Detector
// =============================================================================
// Monitors a 4-bit MII interface and generates a single-cycle pulse when
// a PTP frame is detected (EtherType 0x88F7). Designed to sit alongside
// the HA1588 PTP core without requiring any modifications to it.
//
// Detection method:
//   1. Detect Start-of-Frame Delimiter (SFD) in preamble
//   2. Count 24 nibbles (12 bytes: 6B Dest MAC + 6B Src MAC)
//   3. Check nibbles 24-27 for PTP EtherType 0x88F7
//      MII sends low nibble first: byte 0x88 → {0x8, 0x8}, byte 0xF7 → {0x7, 0xF}
//   4. Assert ptp_event for one clock cycle on match
//
// Timestamp accuracy: capture occurs ~960ns after first bit on wire
// (24 nibbles × 40ns at 25 MHz MII). This is a fixed, deterministic offset
// that cancels in the PTP offset calculation ((t2-t1)-(t4-t3))/2.
// =============================================================================

module ptp_event_detector (
    input  wire       clk,      // MII clock (25 MHz for 100 Mbps)
    input  wire       resetn,   // Active-low reset
    input  wire       mii_dv,   // MII data valid / TX enable
    input  wire [3:0] mii_data, // MII nibble data
    output reg        ptp_event // Single-cycle pulse on PTP frame detection
);

  // -------------------------------------------------------------------------
  // State machine
  // -------------------------------------------------------------------------
  localparam S_IDLE      = 3'd0;  // Waiting for frame (mii_dv = 0)
  localparam S_PREAMBLE  = 3'd1;  // Receiving preamble nibbles (0x5)
  localparam S_POST_SFD  = 3'd2;  // Counting nibbles after SFD
  localparam S_ETHERTYPE = 3'd3;  // Checking EtherType nibbles
  localparam S_DONE      = 3'd4;  // Frame identified, wait for end

  reg [2:0] state;
  reg [4:0] nibble_cnt;  // Counts 0-23 after SFD (24 nibbles of MAC addresses)
  reg [1:0] et_idx;      // EtherType nibble index (0-3)

  // Expected EtherType nibble sequence for 0x88F7 (low nibble first per byte)
  // Byte 0x88: low=0x8, high=0x8 → nibbles[0]=8, nibbles[1]=8
  // Byte 0xF7: low=0x7, high=0xF → nibbles[2]=7, nibbles[3]=F
  reg [3:0] et_expected;
  always @(*) begin
    case (et_idx)
      2'd0: et_expected = 4'h8;
      2'd1: et_expected = 4'h8;
      2'd2: et_expected = 4'h7;
      2'd3: et_expected = 4'hF;
    endcase
  end

  always @(posedge clk or negedge resetn) begin
    if (!resetn) begin
      state      <= S_IDLE;
      nibble_cnt <= 5'd0;
      et_idx     <= 2'd0;
      ptp_event  <= 1'b0;
    end else begin
      ptp_event <= 1'b0;  // Default: deassert

      case (state)
        // -----------------------------------------------------------------
        S_IDLE: begin
          if (mii_dv && mii_data == 4'h5)
            state <= S_PREAMBLE;
        end

        // -----------------------------------------------------------------
        S_PREAMBLE: begin
          if (!mii_dv) begin
            // Frame ended during preamble (runt)
            state <= S_IDLE;
          end else if (mii_data == 4'hD) begin
            // SFD detected — start counting MAC address nibbles
            state      <= S_POST_SFD;
            nibble_cnt <= 5'd0;
          end else if (mii_data != 4'h5) begin
            // Not preamble, not SFD — abort, wait for frame end
            state <= S_DONE;
          end
        end

        // -----------------------------------------------------------------
        S_POST_SFD: begin
          if (!mii_dv) begin
            state <= S_IDLE;
          end else if (nibble_cnt == 5'd23) begin
            // 24 nibbles of MAC addresses received, start EtherType check
            state  <= S_ETHERTYPE;
            et_idx <= 2'd0;
          end else begin
            nibble_cnt <= nibble_cnt + 5'd1;
          end
        end

        // -----------------------------------------------------------------
        S_ETHERTYPE: begin
          if (!mii_dv) begin
            state <= S_IDLE;
          end else if (mii_data != et_expected) begin
            // Mismatch — not a PTP frame
            state <= S_DONE;
          end else if (et_idx == 2'd3) begin
            // All 4 nibbles matched 0x88F7 — PTP frame detected
            ptp_event <= 1'b1;
            state     <= S_DONE;
          end else begin
            et_idx <= et_idx + 2'd1;
          end
        end

        // -----------------------------------------------------------------
        S_DONE: begin
          // Wait for frame to end before accepting next
          if (!mii_dv)
            state <= S_IDLE;
        end

        default: state <= S_IDLE;
      endcase
    end
  end

endmodule
