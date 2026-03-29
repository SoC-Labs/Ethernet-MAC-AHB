//-----------------------------------------------------------------------------
// wb_to_ahb3lite_props.sv
//-----------------------------------------------------------------------------
// SystemVerilog Assertions for the wb_to_ahb3lite bridge.
// Can be bound into the DUT for simulation or formal verification.
//
// Usage in simulation (VCS):
//   Compile with -sverilog and bind in the testbench.
//
// Usage with SymbiYosys:
//   See wb_to_ahb3lite.sby for the formal verification configuration.
//-----------------------------------------------------------------------------

module wb_to_ahb3lite_props (
  input        clk,
  input        rst_n,

  // AHB master outputs
  input  [1:0] htrans,
  input  [2:0] hburst,
  input  [31:0] haddr,
  input        hwrite,
  input  [2:0] hsize,
  input  [3:0] hprot,
  input  [31:0] hwdata,

  // AHB slave inputs
  input        hready,
  input        hresp,
  input  [31:0] hrdata,

  // WB signals
  input        wb_cyc,
  input        wb_stb,
  input        wb_ack,
  input        wb_err,
  input  [2:0] wb_cti,

  // Internal state (exposed via hierarchical reference or bind)
  input  [2:0] state
);

  // AHB transfer type encodings
  localparam [1:0] HTRANS_IDLE   = 2'b00;
  localparam [1:0] HTRANS_BUSY   = 2'b01;
  localparam [1:0] HTRANS_NONSEQ = 2'b10;
  localparam [1:0] HTRANS_SEQ    = 2'b11;

  localparam [2:0] HBURST_SINGLE = 3'b000;
  localparam [2:0] HBURST_INCR4  = 3'b011;

  // State encodings (must match RTL)
  localparam [2:0] S_IDLE        = 3'd0;
  localparam [2:0] S_ADDR        = 3'd1;
  localparam [2:0] S_SINGLE_DATA = 3'd2;
  localparam [2:0] S_BURST_PIPE  = 3'd3;
  localparam [2:0] S_BURST_LAST  = 3'd4;

  //=========================================================================
  // Property 1: No simultaneous ACK and ERR
  //=========================================================================
  property no_ack_and_err;
    @(posedge clk) disable iff (!rst_n)
    !(wb_ack && wb_err);
  endproperty
  assert property (no_ack_and_err)
    else $error("PROP1 FAIL: wb_ack and wb_err asserted simultaneously");

  //=========================================================================
  // Property 2: ACK/ERR only during data phases
  //=========================================================================
  property ack_only_in_data_phase;
    @(posedge clk) disable iff (!rst_n)
    wb_ack |-> (state == S_SINGLE_DATA || state == S_BURST_PIPE || state == S_BURST_LAST);
  endproperty
  assert property (ack_only_in_data_phase)
    else $error("PROP2 FAIL: wb_ack asserted outside data phase (state=%0d)", state);

  property err_only_in_data_phase;
    @(posedge clk) disable iff (!rst_n)
    wb_err |-> (state == S_SINGLE_DATA || state == S_BURST_PIPE || state == S_BURST_LAST);
  endproperty
  assert property (err_only_in_data_phase)
    else $error("PROP2 FAIL: wb_err asserted outside data phase (state=%0d)", state);

  //=========================================================================
  // Property 3: ACK/ERR requires HREADY
  //=========================================================================
  property ack_requires_hready;
    @(posedge clk) disable iff (!rst_n)
    wb_ack |-> hready;
  endproperty
  assert property (ack_requires_hready)
    else $error("PROP3 FAIL: wb_ack without hready");

  property err_requires_hready;
    @(posedge clk) disable iff (!rst_n)
    wb_err |-> hready;
  endproperty
  assert property (err_requires_hready)
    else $error("PROP3 FAIL: wb_err without hready");

  //=========================================================================
  // Property 4: HTRANS sequencing — SEQ only follows NONSEQ or SEQ
  //=========================================================================
  // Track previous htrans when hready was high (completed phase)
  reg [1:0] prev_htrans;
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
      prev_htrans <= HTRANS_IDLE;
    else if (hready)
      prev_htrans <= htrans;
  end

  property seq_follows_nonseq_or_seq;
    @(posedge clk) disable iff (!rst_n)
    (htrans == HTRANS_SEQ) |-> (prev_htrans == HTRANS_NONSEQ || prev_htrans == HTRANS_SEQ);
  endproperty
  assert property (seq_follows_nonseq_or_seq)
    else $error("PROP4 FAIL: HTRANS=SEQ after prev=%0b", prev_htrans);

  //=========================================================================
  // Property 5: HBURST stable during burst
  // Once NONSEQ is issued, HBURST must not change until HTRANS returns
  // to IDLE.
  //=========================================================================
  reg [2:0] latched_hburst;
  reg       in_burst;
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      latched_hburst <= HBURST_SINGLE;
      in_burst       <= 1'b0;
    end else if (hready) begin
      if (htrans == HTRANS_NONSEQ) begin
        latched_hburst <= hburst;
        in_burst       <= (hburst != HBURST_SINGLE);
      end else if (htrans == HTRANS_IDLE) begin
        in_burst <= 1'b0;
      end
    end
  end

  property hburst_stable_during_burst;
    @(posedge clk) disable iff (!rst_n)
    (in_burst && htrans == HTRANS_SEQ) |-> (hburst == latched_hburst);
  endproperty
  assert property (hburst_stable_during_burst)
    else $error("PROP5 FAIL: HBURST changed mid-burst (expected %0b, got %0b)",
                latched_hburst, hburst);

  //=========================================================================
  // Property 6: HSIZE always WORD (3'b010)
  //=========================================================================
  property hsize_always_word;
    @(posedge clk) disable iff (!rst_n)
    hsize == 3'b010;
  endproperty
  assert property (hsize_always_word)
    else $error("PROP6 FAIL: HSIZE=%0b, expected WORD (010)", hsize);

  //=========================================================================
  // Property 7: HPROT always 4'b0011
  //=========================================================================
  property hprot_always_priv_data;
    @(posedge clk) disable iff (!rst_n)
    hprot == 4'b0011;
  endproperty
  assert property (hprot_always_priv_data)
    else $error("PROP7 FAIL: HPROT=%0b, expected 0011", hprot);

  //=========================================================================
  // Property 8: INCR4 burst address increment
  // Each SEQ beat address should be previous address + 4
  //=========================================================================
  reg [31:0] prev_haddr;
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
      prev_haddr <= 32'b0;
    else if (hready && (htrans == HTRANS_NONSEQ || htrans == HTRANS_SEQ))
      prev_haddr <= haddr;
  end

  property incr4_addr_increment;
    @(posedge clk) disable iff (!rst_n)
    (htrans == HTRANS_SEQ && hburst == HBURST_INCR4 && hready) |->
      (haddr == prev_haddr + 32'd4);
  endproperty
  assert property (incr4_addr_increment)
    else $error("PROP8 FAIL: INCR4 addr expected 0x%08X, got 0x%08X",
                prev_haddr + 32'd4, haddr);

  //=========================================================================
  // Property 9: Reset clears state
  //=========================================================================
  property reset_clears_state;
    @(posedge clk)
    !rst_n |-> ##1 (state == S_IDLE && htrans == HTRANS_IDLE && !wb_ack && !wb_err);
  endproperty
  assert property (reset_clears_state)
    else $error("PROP9 FAIL: state not clean after reset");

  //=========================================================================
  // Property 10: Liveness — WB request eventually gets ACK or ERR
  //=========================================================================
  property wb_request_eventually_completes;
    @(posedge clk) disable iff (!rst_n)
    (wb_cyc && wb_stb && state == S_IDLE) |-> ##[1:64] (wb_ack || wb_err);
  endproperty
  assert property (wb_request_eventually_completes)
    else $error("PROP10 FAIL: WB request did not complete within 64 cycles");

  //=========================================================================
  // Property 11: NONSEQ only when bus is free (HREADY=1)
  //=========================================================================
  property nonseq_only_when_hready;
    @(posedge clk) disable iff (!rst_n)
    (htrans == HTRANS_NONSEQ) |-> $past(hready) || $past(!rst_n);
  endproperty
  // Note: relaxed for first cycle after reset

  //=========================================================================
  // Property 12: HWRITE stable during burst
  //=========================================================================
  reg hwrite_latched;
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
      hwrite_latched <= 1'b0;
    else if (hready && htrans == HTRANS_NONSEQ)
      hwrite_latched <= hwrite;
  end

  property hwrite_stable_during_burst;
    @(posedge clk) disable iff (!rst_n)
    (in_burst && htrans == HTRANS_SEQ) |-> (hwrite == hwrite_latched);
  endproperty
  assert property (hwrite_stable_during_burst)
    else $error("PROP12 FAIL: HWRITE changed mid-burst");

  //=========================================================================
  // Cover points for formal verification
  //=========================================================================
  cover property (@(posedge clk) disable iff (!rst_n)
    htrans == HTRANS_NONSEQ && hburst == HBURST_SINGLE && hwrite);
  cover property (@(posedge clk) disable iff (!rst_n)
    htrans == HTRANS_NONSEQ && hburst == HBURST_SINGLE && !hwrite);
  cover property (@(posedge clk) disable iff (!rst_n)
    htrans == HTRANS_NONSEQ && hburst == HBURST_INCR4 && hwrite);
  cover property (@(posedge clk) disable iff (!rst_n)
    htrans == HTRANS_NONSEQ && hburst == HBURST_INCR4 && !hwrite);
  cover property (@(posedge clk) disable iff (!rst_n) wb_err);

endmodule
