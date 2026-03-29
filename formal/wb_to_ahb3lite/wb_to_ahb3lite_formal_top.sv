//-----------------------------------------------------------------------------
// wb_to_ahb3lite_formal_top.sv
//-----------------------------------------------------------------------------
// Formal verification top-level wrapper.
// Instantiates the DUT and binds the SVA properties module.
// Provides assumptions on the input signals.
//-----------------------------------------------------------------------------

module wb_to_ahb3lite_formal_top (
  input        clk_i,
  input        rst_n_i,

  // WB master inputs (unconstrained by formal tool)
  input [31:0] from_m_wb_adr_o,
  input [3:0]  from_m_wb_sel_o,
  input        from_m_wb_we_o,
  input [31:0] from_m_wb_dat_o,
  input        from_m_wb_cyc_o,
  input        from_m_wb_stb_o,
  input [2:0]  from_m_wb_cti_o,
  input [1:0]  from_m_wb_bte_o,

  // AHB slave inputs (unconstrained by formal tool)
  input [31:0] mHRDATA,
  input        mHRESP,
  input        mHREADY
);

  // DUT outputs
  wire        to_m_wb_ack_i;
  wire        to_m_wb_err_i;
  wire [31:0] to_m_wb_dat_i;
  wire        mHSEL;
  wire [2:0]  mHSIZE;
  wire        mHREADYOUT;
  wire        mHWRITE;
  wire [2:0]  mHBURST;
  wire [31:0] mHADDR;
  wire [1:0]  mHTRANS;
  wire [31:0] mHWDATA;
  wire [3:0]  mHPROT;

  //---------------------------------------------------------------
  // DUT instance
  //---------------------------------------------------------------
  wb_to_ahb3lite u_dut (
    .clk_i              (clk_i),
    .rst_n_i            (rst_n_i),
    .from_m_wb_adr_o    (from_m_wb_adr_o),
    .from_m_wb_sel_o    (from_m_wb_sel_o),
    .from_m_wb_we_o     (from_m_wb_we_o),
    .from_m_wb_dat_o    (from_m_wb_dat_o),
    .from_m_wb_cyc_o    (from_m_wb_cyc_o),
    .from_m_wb_stb_o    (from_m_wb_stb_o),
    .to_m_wb_ack_i      (to_m_wb_ack_i),
    .to_m_wb_err_i      (to_m_wb_err_i),
    .to_m_wb_dat_i      (to_m_wb_dat_i),
    .from_m_wb_cti_o    (from_m_wb_cti_o),
    .from_m_wb_bte_o    (from_m_wb_bte_o),
    .mHSEL              (mHSEL),
    .mHSIZE             (mHSIZE),
    .mHRDATA            (mHRDATA),
    .mHRESP             (mHRESP),
    .mHREADY            (mHREADY),
    .mHREADYOUT         (mHREADYOUT),
    .mHWRITE            (mHWRITE),
    .mHBURST            (mHBURST),
    .mHADDR             (mHADDR),
    .mHTRANS            (mHTRANS),
    .mHWDATA            (mHWDATA),
    .mHPROT             (mHPROT)
  );

  //---------------------------------------------------------------
  // SVA properties bind
  //---------------------------------------------------------------
  wb_to_ahb3lite_props u_props (
    .clk      (clk_i),
    .rst_n    (rst_n_i),
    .htrans   (mHTRANS),
    .hburst   (mHBURST),
    .haddr    (mHADDR),
    .hwrite   (mHWRITE),
    .hsize    (mHSIZE),
    .hprot    (mHPROT),
    .hwdata   (mHWDATA),
    .hready   (mHREADY),
    .hresp    (mHRESP),
    .hrdata   (mHRDATA),
    .wb_cyc   (from_m_wb_cyc_o),
    .wb_stb   (from_m_wb_stb_o),
    .wb_ack   (to_m_wb_ack_i),
    .wb_err   (to_m_wb_err_i),
    .wb_cti   (from_m_wb_cti_o),
    .state    (u_dut.state)
  );

  //---------------------------------------------------------------
  // Input assumptions
  //---------------------------------------------------------------

  // Assume reset is asserted at the start
  initial assume (!rst_n_i);

  // WB protocol: stb only with cyc
  always @(posedge clk_i) begin
    assume (from_m_wb_stb_o |-> from_m_wb_cyc_o);
  end

  // WB CTI: only valid values (classic, incrementing, end-of-burst)
  always @(posedge clk_i) begin
    assume (from_m_wb_cti_o == 3'b000 ||
            from_m_wb_cti_o == 3'b010 ||
            from_m_wb_cti_o == 3'b111);
  end

  // WB BTE: always linear (ethmac only uses BTE=00)
  always @(posedge clk_i) begin
    assume (from_m_wb_bte_o == 2'b00);
  end

  // WB addresses are word-aligned
  always @(posedge clk_i) begin
    assume (from_m_wb_adr_o[1:0] == 2'b00);
  end

  // AHB HREADY cannot be low forever (liveness)
  // Assume HREADY eventually goes high within 16 cycles
  reg [3:0] hready_wait_cnt;
  always @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i)
      hready_wait_cnt <= 4'd0;
    else if (mHREADY)
      hready_wait_cnt <= 4'd0;
    else
      hready_wait_cnt <= hready_wait_cnt + 4'd1;
  end
  always @(posedge clk_i) begin
    assume (hready_wait_cnt < 4'd15);
  end

  // AHB two-cycle error protocol: if HRESP=1 and HREADY=0,
  // next cycle must have HRESP=1 and HREADY=1
  always @(posedge clk_i) begin
    if (rst_n_i && mHRESP && !mHREADY)
      assume (##1 (mHRESP && mHREADY));
  end

endmodule
