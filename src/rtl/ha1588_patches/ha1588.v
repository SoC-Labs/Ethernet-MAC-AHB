/*
 * ha1588.v — PATCHED for ASIC reset hygiene
 *
 * Original: OpenCores HA1588, Copyright (c) 2012, BABY&HW (LGPL v2.1)
 *
 * Patch summary:
 *   - RTC reset now includes system reset (rst) OR-ed with software rtc_rst.
 *     The original only passed the software-controlled rtc_rst (from register
 *     bit RTC_CTRL[4]) to the RTC, meaning the RTC had no reset path from
 *     the system reset and started with X-state in simulation.
 */

`timescale 1ns/1ns

module ha1588 (
  input         rst,clk,
  input         wr_in,rd_in,
  input  [ 7:0] addr_in,
  input  [31:0] data_in,
  output [31:0] data_out,

  input         rtc_clk,
  output [31:0] rtc_time_ptp_ns,
  output [47:0] rtc_time_ptp_sec,
  output        rtc_time_one_pps,

  input       rx_gmii_clk,
  input       rx_gmii_ctrl,
  input [7:0] rx_gmii_data,
  input       rx_giga_mode,

  input       tx_gmii_clk,
  input       tx_gmii_ctrl,
  input [7:0] tx_gmii_data,
  input       tx_giga_mode
);

parameter addr_is_in_word = 0;
wire [ 5: 0] word_addr_in;
wire [ 7: 0] byte_addr_in;
generate
  if (addr_is_in_word)
    assign word_addr_in = addr_in[ 5: 0];
  else
    assign word_addr_in = addr_in[ 7: 2];
endgenerate
assign byte_addr_in = {word_addr_in, 2'b00};

wire rtc_rst;
wire rtc_time_ld, rtc_period_ld, rtc_adj_ld, adj_ld_done;
wire [37:0] rtc_time_reg_ns;
wire [47:0] rtc_time_reg_sec;
wire [39:0] rtc_period;
wire [31:0] rtc_adj_ld_data;
wire [39:0] rtc_period_adj;
wire [37:0] rtc_time_reg_ns_val;
wire [47:0] rtc_time_reg_sec_val;
wire [79:0] rtc_time_ptp_val = {rtc_time_ptp_sec[47:0], rtc_time_ptp_ns[31:0]};

wire rx_q_rst, rx_q_clk;
wire rx_q_rd_en;
wire [  7:0] rx_q_ptp_msgid_mask;
wire [  7:0] rx_q_stat;
wire [  3:0] rx_q_wm;
wire [127:0] rx_q_data;
wire tx_q_rst, tx_q_clk;
wire tx_q_rd_en;
wire [  7:0] tx_q_ptp_msgid_mask;
wire [  7:0] tx_q_stat;
wire [  3:0] tx_q_wm;
wire [127:0] tx_q_data;

// PATCHED: Synchronise system rst into rtc_clk domain for the RTC.
//   2-FF async-assert / sync-deassert. Asserts immediately on rst, deasserts
//   cleanly on rtc_clk after rst has cleared.
reg rst_rtc_s1, rst_rtc_s2;
always @(posedge rtc_clk or posedge rst) begin
  if (rst) begin
    rst_rtc_s1 <= 1'b1;
    rst_rtc_s2 <= 1'b1;
  end else begin
    rst_rtc_s1 <= 1'b0;
    rst_rtc_s2 <= rst_rtc_s1;
  end
end

// PATCHED: Combine system rst (sync'd to rtc_clk) with software rtc_rst.
//   rtc_rst is rgs-controlled and already in rtc_clk; rst_rtc_s2 is rst
//   sync'd to rtc_clk. Register the OR on a flop with rst as async-set so
//   the resulting signal is glitch-free when used as the RTC's async
//   reset. Without this flop, lint flags GLTASR (combinational logic in
//   async-reset path) at the rtc instance.
reg rtc_rst_combined;
always @(posedge rtc_clk or posedge rst) begin
  if (rst) rtc_rst_combined <= 1'b1;
  else     rtc_rst_combined <= rtc_rst;
end

// PATCHED: System reset OR'd with rgs queue resets.
//   rx_q_rst / tx_q_rst are rgs-controlled (sys_fclk = clk). Register on
//   clk with rst as async-set. Output drives the queue's async aclr port
//   (used on both gmii write side and sys_fclk read side); the system
//   reset propagates cleanly without the combinational OR that lint
//   flags as GLTASR. Cross-domain async-reset deassertion to gmii_clk
//   remains a known CDC limitation of the OpenCores queue interface
//   (Reset_sync02).
reg rx_q_rst_combined;
always @(posedge clk or posedge rst) begin
  if (rst) rx_q_rst_combined <= 1'b1;
  else     rx_q_rst_combined <= rx_q_rst;
end
reg tx_q_rst_combined;
always @(posedge clk or posedge rst) begin
  if (rst) tx_q_rst_combined <= 1'b1;
  else     tx_q_rst_combined <= tx_q_rst;
end

rgs u_rgs
(
  .rst(rst),
  .clk(clk),
  .wr_in(wr_in),
  .rd_in(rd_in),
  .addr_in(byte_addr_in),
  .data_in(data_in),
  .data_out(data_out),
  .rtc_clk_in(rtc_clk),
  .rtc_rst_out(rtc_rst),
  .time_ld_out(rtc_time_ld),
  .time_reg_ns_out(rtc_time_reg_ns),
  .time_reg_sec_out(rtc_time_reg_sec),
  .period_ld_out(rtc_period_ld),
  .period_out(rtc_period),
  .adj_ld_out(rtc_adj_ld),
  .adj_ld_data_out(rtc_adj_ld_data),
  .period_adj_out(rtc_period_adj),
  .adj_ld_done_in(adj_ld_done),
  .time_reg_ns_in(rtc_time_reg_ns_val),
  .time_reg_sec_in(rtc_time_reg_sec_val),
  .rx_q_rst_out(rx_q_rst),
  .rx_q_rd_clk_out(rx_q_clk),
  .rx_q_rd_en_out(rx_q_rd_en),
  .rx_q_ptp_msgid_mask_out(rx_q_ptp_msgid_mask),
  .rx_q_stat_in(rx_q_stat),
  .rx_q_wm_in(rx_q_wm),       // RX queue high-watermark (perf instrumentation)
  .rx_q_data_in(rx_q_data),
  .tx_q_rst_out(tx_q_rst),
  .tx_q_rd_clk_out(tx_q_clk),
  .tx_q_rd_en_out(tx_q_rd_en),
  .tx_q_ptp_msgid_mask_out(tx_q_ptp_msgid_mask),
  .tx_q_stat_in(tx_q_stat),
  .tx_q_wm_in(tx_q_wm),       // TX queue high-watermark (perf instrumentation)
  .tx_q_data_in(tx_q_data)
);

rtc u_rtc
(
  .rst(rtc_rst_combined),  // PATCHED: was rtc_rst only (no system reset path)
  .clk(rtc_clk),
  .time_ld(rtc_time_ld),
  .time_reg_ns_in(rtc_time_reg_ns),
  .time_reg_sec_in(rtc_time_reg_sec),
  .period_ld(rtc_period_ld),
  .period_in(rtc_period),
  .adj_ld(rtc_adj_ld),
  .adj_ld_data(rtc_adj_ld_data),
  .adj_ld_done(adj_ld_done),
  .period_adj(rtc_period_adj),
  .time_reg_ns(rtc_time_reg_ns_val),
  .time_reg_sec(rtc_time_reg_sec_val),
  .time_one_pps(rtc_time_one_pps),
  .time_ptp_ns(rtc_time_ptp_ns),
  .time_ptp_sec(rtc_time_ptp_sec)
);

tsu u_rx_tsu
(
  .rst(rst),
  .gmii_clk(rx_gmii_clk),
  .gmii_ctrl(rx_gmii_ctrl),
  .gmii_data(rx_gmii_data),
  .giga_mode(rx_giga_mode),
  .ptp_msgid_mask(rx_q_ptp_msgid_mask),
  .rtc_timer_clk(rtc_clk),
  .rtc_timer_in(rtc_time_ptp_val),
  .q_rst(rx_q_rst_combined),  // PATCHED: includes system reset
  .q_rd_clk(rx_q_clk),
  .q_rd_en(rx_q_rd_en),
  .q_rd_stat(rx_q_stat),
  .q_rd_wm(rx_q_wm),
  .q_rd_data(rx_q_data)
);

tsu u_tx_tsu
(
  .rst(rst),
  .gmii_clk(tx_gmii_clk),
  .gmii_ctrl(tx_gmii_ctrl),
  .gmii_data(tx_gmii_data),
  .giga_mode(tx_giga_mode),
  .ptp_msgid_mask(tx_q_ptp_msgid_mask),
  .rtc_timer_clk(rtc_clk),
  .rtc_timer_in(rtc_time_ptp_val),
  .q_rst(tx_q_rst_combined),  // PATCHED: includes system reset
  .q_rd_clk(tx_q_clk),
  .q_rd_en(tx_q_rd_en),
  .q_rd_stat(tx_q_stat),
  .q_rd_wm(tx_q_wm),
  .q_rd_data(tx_q_data)
);

endmodule
