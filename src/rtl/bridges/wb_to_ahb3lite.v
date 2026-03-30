///////////////////////////////////////////////////////////////////////////////
// wb_to_ahb3lite.v
///////////////////////////////////////////////////////////////////////////////
//
// Wishbone B3 master to AHB3-Lite master bridge.
//
// Converts WISHBONE master transactions (classic and B3 incrementing bursts)
// into AHB-Lite master transfers with correct pipelined protocol.
//
// Supported WISHBONE cycle types:
//   CTI = 000  Classic single-beat transfer
//   CTI = 010  Incrementing burst (4-beat INCR4, linear)
//   CTI = 111  End-of-burst marker
//
// AHB-Lite protocol compliance:
//   - Proper address/data phase pipelining
//   - HBURST stable throughout burst (latched at NONSEQ)
//   - HTRANS: NONSEQ for first beat, SEQ for continuation, IDLE otherwise
//   - Two-cycle HRESP error handling
//   - HPROT driven to sensible default
//

module wb_to_ahb3lite (
  input          clk_i,
  input          rst_n_i,

  // WISHBONE master side (directly connected to WB master, e.g. eth_top)
  input  [31:0]  from_m_wb_adr_o,
  input  [3:0]   from_m_wb_sel_o,    // Unused: bridge always does 32-bit word transfers
  input          from_m_wb_we_o,
  input  [31:0]  from_m_wb_dat_o,
  input          from_m_wb_cyc_o,
  input          from_m_wb_stb_o,
  output         to_m_wb_ack_i,
  output         to_m_wb_err_i,
  output [31:0]  to_m_wb_dat_i,

  input  [2:0]   from_m_wb_cti_o,
  input  [1:0]   from_m_wb_bte_o,    // Unused: only linear bursts supported (BTE=00)

  // AHB3-Lite master side
  output         mHSEL,
  output [2:0]   mHSIZE,
  input  [31:0]  mHRDATA,
  input          mHRESP,
  input          mHREADY,
  output         mHREADYOUT,
  output         mHWRITE,
  output [2:0]   mHBURST,
  output [31:0]  mHADDR,
  output [1:0]   mHTRANS,
  output [31:0]  mHWDATA,
  output [3:0]   mHPROT
);

  //---------------------------------------------------------------
  // AHB transfer type encodings
  //---------------------------------------------------------------
  localparam [1:0] HTRANS_IDLE   = 2'b00;
  localparam [1:0] HTRANS_NONSEQ = 2'b10;
  localparam [1:0] HTRANS_SEQ    = 2'b11;

  //---------------------------------------------------------------
  // AHB burst type encodings
  //---------------------------------------------------------------
  localparam [2:0] HBURST_SINGLE = 3'b000;
  localparam [2:0] HBURST_INCR4  = 3'b011;

  //---------------------------------------------------------------
  // WB B3 Cycle Type Identifier
  //---------------------------------------------------------------
  localparam [2:0] CTI_INCR    = 3'b010;

  //---------------------------------------------------------------
  // State machine
  //
  //  S_IDLE ──(cyc & stb & HREADY)──► S_ADDR
  //
  //  S_ADDR ──(HREADY, single)──────► S_SINGLE_DATA
  //         ──(HREADY, burst)───────► S_BURST_PIPE
  //
  //  S_SINGLE_DATA ──(HREADY)───────► S_IDLE
  //
  //  S_BURST_PIPE ──(HREADY, more)──► S_BURST_PIPE  (beat_count++)
  //               ──(HREADY, last)──► S_BURST_LAST
  //
  //  S_BURST_LAST ──(HREADY)────────► S_IDLE
  //
  //  Any data state ──(HRESP)───────► S_IDLE (error)
  //
  //---------------------------------------------------------------
  localparam [2:0] S_IDLE        = 3'd0;
  localparam [2:0] S_ADDR        = 3'd1;
  localparam [2:0] S_SINGLE_DATA = 3'd2;
  localparam [2:0] S_BURST_PIPE  = 3'd3;
  localparam [2:0] S_BURST_LAST  = 3'd4;

  //---------------------------------------------------------------
  // Registered state
  //---------------------------------------------------------------
  reg [2:0]  state;
  reg [2:0]  next_state;
  reg [31:0] addr_reg;       // Base address (latched at transfer start)
  reg        write_reg;      // Write direction (latched at transfer start)
  reg        burst_reg;      // 1 = INCR4 burst, 0 = single
  reg [1:0]  beat_count;     // Next burst address beat to issue (1-3)
  reg [31:0] hwdata_reg;     // Registered write data (stable during wait states)
  reg        idle_wait;      // Suppress phantom requests for 1 cycle after transfer end

  //---------------------------------------------------------------
  // Combinational output registers
  //---------------------------------------------------------------
  reg [1:0]  htrans_comb;
  reg [31:0] haddr_comb;
  reg [2:0]  hburst_comb;
  reg        hwrite_comb;
  reg        wb_ack_comb;
  reg        wb_err_comb;

  //---------------------------------------------------------------
  // WB request detection
  //---------------------------------------------------------------
  wire wb_request = from_m_wb_cyc_o & from_m_wb_stb_o;
  wire wb_burst   = (from_m_wb_cti_o == CTI_INCR);

  //---------------------------------------------------------------
  // Fixed AHB outputs
  //---------------------------------------------------------------
  assign mHSIZE    = 3'b010;           // Always 32-bit word transfers
  assign mHPROT    = 4'b0011;          // Privileged data, non-cacheable
  assign mHSEL     = (state != S_IDLE); // Active when FSM is processing a transfer
  assign mHREADYOUT = 1'b1;            // Bridge never inserts wait states

  //---------------------------------------------------------------
  // Data path
  //
  // Write data: For single transfers, hwdata_reg is latched in
  // S_IDLE/S_ADDR and remains stable through S_SINGLE_DATA.
  // For burst transfers, the pipelined AHB data phases overlap with
  // WB beat handshakes. The WB master holds each beat's data stable
  // until ACK, so from_m_wb_dat_o is always the correct data for the
  // current data phase during S_BURST_PIPE and S_BURST_LAST.
  //
  // Read data: HRDATA is valid when HREADY=1 during a data phase.
  // We pass it through to the WB master simultaneously with ACK.
  //---------------------------------------------------------------
  assign mHWDATA      = (state == S_BURST_PIPE || state == S_BURST_LAST)
                         ? from_m_wb_dat_o : hwdata_reg;
  assign to_m_wb_dat_i = mHRDATA;

  //---------------------------------------------------------------
  // Control outputs
  //---------------------------------------------------------------
  assign mHTRANS      = htrans_comb;
  assign mHADDR       = haddr_comb;
  assign mHBURST      = hburst_comb;
  assign mHWRITE      = hwrite_comb;
  assign to_m_wb_ack_i = wb_ack_comb;
  assign to_m_wb_err_i = wb_err_comb;

  //---------------------------------------------------------------
  // Combinational next-state and output logic
  //---------------------------------------------------------------
  always @(*) begin
    // Defaults: idle bus, no acknowledgement
    next_state  = state;
    htrans_comb = HTRANS_IDLE;
    haddr_comb  = addr_reg;
    hburst_comb = HBURST_SINGLE;
    hwrite_comb = 1'b0;
    wb_ack_comb = 1'b0;
    wb_err_comb = 1'b0;

    case (state)
      // -----------------------------------------------------------
      // IDLE: Wait for a WISHBONE request. The AHB spec requires
      // HREADY=1 before starting a new transfer; in AHB-Lite with
      // a single master, HREADY is always 1 when the bus is idle.
      // -----------------------------------------------------------
      S_IDLE: begin
        if (wb_request && mHREADY && !idle_wait) begin
          next_state = S_ADDR;
        end
      end

      // -----------------------------------------------------------
      // ADDR: Drive NONSEQ address phase. Hold until HREADY=1
      // confirms the slave has accepted the address.
      // -----------------------------------------------------------
      S_ADDR: begin
        htrans_comb = HTRANS_NONSEQ;
        haddr_comb  = addr_reg;
        hburst_comb = burst_reg ? HBURST_INCR4 : HBURST_SINGLE;
        hwrite_comb = write_reg;

        if (mHREADY) begin
          next_state = burst_reg ? S_BURST_PIPE : S_SINGLE_DATA;
        end
      end

      // -----------------------------------------------------------
      // SINGLE_DATA: Data phase of a single-beat transfer.
      // - Writes: HWDATA is valid (combinational pass-through).
      // - Reads:  HRDATA captured when HREADY=1.
      // -----------------------------------------------------------
      S_SINGLE_DATA: begin
        hwrite_comb = write_reg;

        if (mHRESP) begin
          // Two-cycle AHB error: HRESP=1,HREADY=0 then HRESP=1,HREADY=1
          if (mHREADY) begin
            wb_err_comb = 1'b1;
            next_state  = S_IDLE;
          end
        end else if (mHREADY) begin
          wb_ack_comb = 1'b1;
          next_state  = S_IDLE;
        end
      end

      // -----------------------------------------------------------
      // BURST_PIPE: Pipelined burst beats.
      // Simultaneously completes the data phase of the previous beat
      // and issues the address phase of the next beat (SEQ).
      //
      // beat_count tracks which address to issue next (1, 2, 3).
      // ACK is for the beat whose data phase is completing.
      // -----------------------------------------------------------
      S_BURST_PIPE: begin
        htrans_comb = HTRANS_SEQ;
        haddr_comb  = addr_reg + {28'd0, beat_count, 2'b00};
        hburst_comb = HBURST_INCR4;
        hwrite_comb = write_reg;

        if (mHRESP) begin
          // Error: cancel remaining burst (drive IDLE per AHB spec)
          htrans_comb = HTRANS_IDLE;
          if (mHREADY) begin
            wb_err_comb = 1'b1;
            next_state  = S_IDLE;
          end
        end else if (mHREADY) begin
          wb_ack_comb = 1'b1;

          if (beat_count == 2'd3)
            next_state = S_BURST_LAST;
          // else: stay in S_BURST_PIPE, beat_count incremented in seq block
        end
      end

      // -----------------------------------------------------------
      // BURST_LAST: Final data phase of a 4-beat burst.
      // No new address phase (HTRANS=IDLE). ACK the last beat.
      // -----------------------------------------------------------
      S_BURST_LAST: begin
        hwrite_comb = write_reg;
        hburst_comb = HBURST_INCR4;

        if (mHRESP) begin
          if (mHREADY) begin
            wb_err_comb = 1'b1;
            next_state  = S_IDLE;
          end
        end else if (mHREADY) begin
          wb_ack_comb = 1'b1;
          next_state  = S_IDLE;
        end
      end

      // -----------------------------------------------------------
      default: begin
        next_state = S_IDLE;
      end
    endcase
  end

  //---------------------------------------------------------------
  // Sequential state register and internal state updates
  //---------------------------------------------------------------
  always @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i) begin
      state      <= S_IDLE;
      addr_reg   <= 32'd0;
      write_reg  <= 1'b0;
      burst_reg  <= 1'b0;
      beat_count <= 2'b00;
      hwdata_reg <= 32'd0;
      idle_wait  <= 1'b0;
    end else begin
      state <= next_state;
      // idle_wait is set when entering S_IDLE from a completed/errored
      // transfer, and cleared after one cycle. This gives the WB driver
      // time to update its bus signals, preventing the DUT from latching
      // stale WB values as phantom requests.
      if (state != S_IDLE && next_state == S_IDLE)
        idle_wait <= 1'b1;
      else
        idle_wait <= 1'b0;

      case (state)
        S_IDLE: begin
          if (wb_request && mHREADY && !idle_wait) begin
            addr_reg   <= from_m_wb_adr_o;
            write_reg  <= from_m_wb_we_o;
            burst_reg  <= wb_burst;
            beat_count <= 2'd1;
            hwdata_reg <= from_m_wb_dat_o;
          end
        end

        S_ADDR: begin
          // hwdata_reg retains the value captured in S_IDLE.
          // No update here: for real transactions, the WB data
          // hasn't changed. For phantom transactions (stale WB
          // signals after burst idle), from_m_wb_dat_o may have
          // gone to zero and would corrupt the held value.
        end

        S_SINGLE_DATA: begin
          if (mHRESP && mHREADY) begin
            // Error on single transfer: clear burst state
            burst_reg  <= 1'b0;
            beat_count <= 2'd0;
          end
        end

        S_BURST_PIPE: begin
          if (mHRESP && mHREADY) begin
            // Error during burst: clear burst state
            burst_reg  <= 1'b0;
            beat_count <= 2'd0;
          end else if (mHREADY) begin
            beat_count <= beat_count + 2'd1;
            // Latch next beat's write data
            hwdata_reg <= from_m_wb_dat_o;
          end
        end

        S_BURST_LAST: begin
          if (mHRESP && mHREADY) begin
            // Error on last burst beat: clear burst state
            burst_reg  <= 1'b0;
            beat_count <= 2'd0;
          end
        end

        default: ;
      endcase
    end
  end

endmodule
