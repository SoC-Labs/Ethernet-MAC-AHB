//-----------------------------------------------------------------------------
// tb_rmii_tsu_cosim.v
//-----------------------------------------------------------------------------
// HIGH-FIDELITY co-sim wrapper that composes the REAL rmii_to_mii RX adapter
// with the HA1588 RX TSU, EXACTLY as the silicon does in ethmac_subsystem_apb.v:
//
//     LAN8720 RMII  ->  rmii_to_mii  ->  {mrxd[3:0], mrxdv, mrx_clk}
//                                            |
//                                            v
//   ha1588_apb.rx_gmii_clk  = mrx_clk
//   ha1588_apb.rx_gmii_ctrl = mrxdv
//   ha1588_apb.rx_gmii_data = {4'b0, mrxd}      (MII nibble, upper nibble 0)
//   ha1588_apb.rx_giga_mode = 1'b0              (MII nibble mode)
//
// This is the wiring in ethmac_subsystem_apb.v:456-459. The TSU is fed the
// rmii_to_mii MII output DIRECTLY (the MAC deframer is NOT in the RX-TSU path).
//
// The cocotb test drives the RMII RX pins (rmii_crs_dv / rmii_rxd[1:0] @50MHz)
// with realistic LAN8720-style framing (a carrier-sense rxd=00 window of
// varying odd/even di-bit length, then 0x55*n preamble, 0xD5 SFD, then an L2
// PTP Sync). It then reads RX_TSU_STAT depth over APB to see if the TSU
// captured. Unlike the gmii-direct oracle, the byte/nibble phase the TSU sees
// here is produced by the REAL rmii_to_mii di-bit-pair lock, not a synthetic
// prepended nibble.
//
// Only ADDS files (TB + Makefile). Does not modify rmii_to_mii.v or tsu.v.
//-----------------------------------------------------------------------------

`timescale 1ns / 1ps

module tb_rmii_tsu_cosim;

  // -------------------------------------------------------
  // Clocks / Reset
  // -------------------------------------------------------
  reg  pclk         = 0;   // APB clock (100 MHz)
  reg  presetn      = 0;
  reg  rtc_clk      = 0;   // HA1588 RTC clock (125 MHz)
  reg  rmii_ref_clk = 0;   // RMII 50 MHz reference clock

  // -------------------------------------------------------
  // APB slave port (register access)
  // -------------------------------------------------------
  reg         psel;
  reg         penable;
  reg  [31:0] paddr;
  reg         pwrite;
  reg  [31:0] pwdata;
  reg   [3:0] pstrb;
  wire [31:0] prdata_raw;
  wire [31:0] prdata;
  wire        pready;
  wire        pslverr;

  // Ensure prdata is always resolvable (replace X with 0) -- same trick as the
  // ha1588_apb cocotb TB (reg.v has no reset; X under 4-state sim).
  assign prdata = (^prdata_raw === 1'bx) ? 32'h0 : prdata_raw;

  // -------------------------------------------------------
  // RMII RX side (driven by cocotb -- the LAN8720 BFM)
  // -------------------------------------------------------
  reg        rmii_crs_dv = 0;
  reg  [1:0] rmii_rxd    = 0;
  reg        mode_speed  = 1;   // 100 Mbps (every REFCLK cycle a new di-bit)

  // RMII TX side (unused here, tie off)
  reg  [3:0] mtxd  = 0;
  reg        mtxen = 0;
  reg        mtxerr= 0;

  // -------------------------------------------------------
  // rmii_to_mii MII output (the wires that feed the TSU)
  // -------------------------------------------------------
  wire        mtx_clk;
  wire        mrx_clk;
  wire  [3:0] mrxd;
  wire        mrxdv;
  wire        mrxerr;
  wire        mcoll;
  wire        mcrs;

  wire  [1:0] rmii_txd;
  wire        rmii_tx_en;

  // RMII adapter reset: hold during presetn low, then released. Drive from the
  // same reset so the whole RX path comes out of reset together.
  wire rmii_resetn = presetn;

  // -------------------------------------------------------
  // REAL rmii_to_mii adapter (default params == silicon:
  //   RMII_RX_ERR_FROM_DIBIT=0 -- LAN8720 has no RX_ER pin)
  // -------------------------------------------------------
  rmii_to_mii u_rmii_to_mii (
    .RESETn       (rmii_resetn),
    .mode_speed   (mode_speed),

    // RMII side (driven by cocotb)
    .rmii_ref_clk (rmii_ref_clk),
    .rmii_txd     (rmii_txd),
    .rmii_tx_en   (rmii_tx_en),
    .rmii_rxd     (rmii_rxd),
    .rmii_crs_dv  (rmii_crs_dv),

    // MII side
    .mtx_clk      (mtx_clk),
    .mtxd         (mtxd),
    .mtxen        (mtxen),
    .mtxerr       (mtxerr),

    .mrx_clk      (mrx_clk),
    .mrxd         (mrxd),
    .mrxdv        (mrxdv),
    .mrxerr       (mrxerr),

    .mcoll        (mcoll),
    .mcrs         (mcrs)
  );

  // -------------------------------------------------------
  // HA1588 (+ APB wrapper). RX GMII port fed from rmii_to_mii MII output
  // EXACTLY as ethmac_subsystem_apb.v:456-459 does on silicon.
  // -------------------------------------------------------
  wire [31:0] rtc_time_ptp_ns;
  wire [47:0] rtc_time_ptp_sec;
  wire        rtc_time_one_pps;

  ha1588_apb u_dut (
    .pclk             (pclk),
    .presetn          (presetn),

    // APB slave port
    .psel             (psel),
    .penable          (penable),
    .paddr            (paddr),
    .pwrite           (pwrite),
    .pwdata           (pwdata),
    .pstrb            (pstrb),
    .prdata           (prdata_raw),
    .pready           (pready),
    .pslverr          (pslverr),

    // RTC clock
    .rtc_clk          (rtc_clk),

    // RTC time outputs
    .rtc_time_ptp_ns  (rtc_time_ptp_ns),
    .rtc_time_ptp_sec (rtc_time_ptp_sec),
    .rtc_time_one_pps (rtc_time_one_pps),

    // --- RX GMII fed by rmii_to_mii (silicon wiring) ---
    .rx_gmii_clk      (mrx_clk),
    .rx_gmii_ctrl     (mrxdv),
    .rx_gmii_data     ({4'b0, mrxd}),
    .rx_giga_mode     (1'b0),            // MII nibble mode (silicon ties 1'b0)

    // TX GMII unused in this RX-failure cosim -- tie off
    .tx_gmii_clk      (mtx_clk),
    .tx_gmii_ctrl     (1'b0),
    .tx_gmii_data     (8'b0),
    .tx_giga_mode     (1'b0)
  );

  // -------------------------------------------------------
  // Waveforms
  // -------------------------------------------------------
  initial begin
    $dumpfile("tb_rmii_tsu_cosim.vcd");
    $dumpvars(0, tb_rmii_tsu_cosim);
  end

endmodule
