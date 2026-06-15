//-----------------------------------------------------------------------------
// ptp_queue.v
//-----------------------------------------------------------------------------
// Generic dual-clock FIFO replacement for the HA1588 ptp_queue module.
//
// The original ptp_queue.v requires vendor-specific FIFO IPs (Altera or
// Xilinx). This version implements a generic async FIFO using gray-code
// pointer synchronisation, suitable for simulation, FPGA, and ASIC flows.
//
// Parameters match the original: 128-bit data, 16-entry depth (4-bit
// address), with separate read and write clock domains.
//-----------------------------------------------------------------------------

`timescale 1ns/1ns

module ptp_queue (
  input          aclr,
  input  [127:0] data,
  input          rdclk,
  input          rdreq,
  input          wrclk,
  input          wrreq,
  output [127:0] q,
  output         rdempty,
  output [  3:0] rdusedw,
  output         wrfull,
  output [  3:0] wrusedw,
  output [  3:0] wrusedw_max   // running peak fill since aclr (perf high-watermark)
);

  // FIFO depth = 16, address width = 4
  localparam ADDR_W = 4;
  localparam DEPTH  = 1 << ADDR_W;

  //---------------------------------------------------------------
  // Memory
  //---------------------------------------------------------------
  reg [127:0] mem [0:DEPTH-1];

  //---------------------------------------------------------------
  // Write-domain pointers (binary and gray)
  //---------------------------------------------------------------
  reg [ADDR_W:0] wr_bin, wr_gray;
  wire [ADDR_W:0] wr_bin_next = wr_bin + (wrreq & ~wrfull);
  wire [ADDR_W:0] wr_gray_next = wr_bin_next ^ (wr_bin_next >> 1);

  always @(posedge wrclk or posedge aclr) begin
    if (aclr) begin
      wr_bin  <= {(ADDR_W+1){1'b0}};
      wr_gray <= {(ADDR_W+1){1'b0}};
    end else begin
      wr_bin  <= wr_bin_next;
      wr_gray <= wr_gray_next;
    end
  end

  // Write to memory
  always @(posedge wrclk) begin
    if (wrreq & ~wrfull)
      mem[wr_bin[ADDR_W-1:0]] <= data;
  end

  //---------------------------------------------------------------
  // Read-domain pointers (binary and gray)
  //---------------------------------------------------------------
  reg [ADDR_W:0] rd_bin, rd_gray;
  wire [ADDR_W:0] rd_bin_next = rd_bin + (rdreq & ~rdempty);
  wire [ADDR_W:0] rd_gray_next = rd_bin_next ^ (rd_bin_next >> 1);

  always @(posedge rdclk or posedge aclr) begin
    if (aclr) begin
      rd_bin  <= {(ADDR_W+1){1'b0}};
      rd_gray <= {(ADDR_W+1){1'b0}};
    end else begin
      rd_bin  <= rd_bin_next;
      rd_gray <= rd_gray_next;
    end
  end

  // Read from memory
  assign q = mem[rd_bin[ADDR_W-1:0]];

  //---------------------------------------------------------------
  // Synchronise write gray pointer into read domain
  //---------------------------------------------------------------
  reg [ADDR_W:0] wr_gray_rd1, wr_gray_rd2;
  always @(posedge rdclk or posedge aclr) begin
    if (aclr) begin
      wr_gray_rd1 <= {(ADDR_W+1){1'b0}};
      wr_gray_rd2 <= {(ADDR_W+1){1'b0}};
    end else begin
      wr_gray_rd1 <= wr_gray;
      wr_gray_rd2 <= wr_gray_rd1;
    end
  end

  //---------------------------------------------------------------
  // Synchronise read gray pointer into write domain
  //---------------------------------------------------------------
  reg [ADDR_W:0] rd_gray_wr1, rd_gray_wr2;
  always @(posedge wrclk or posedge aclr) begin
    if (aclr) begin
      rd_gray_wr1 <= {(ADDR_W+1){1'b0}};
      rd_gray_wr2 <= {(ADDR_W+1){1'b0}};
    end else begin
      rd_gray_wr1 <= rd_gray;
      rd_gray_wr2 <= rd_gray_wr1;
    end
  end

  //---------------------------------------------------------------
  // Full and empty flags
  //---------------------------------------------------------------
  // Empty: read gray == synchronised write gray
  assign rdempty = (rd_gray == wr_gray_rd2);

  // Full: write gray MSBs inverted, rest equal to synchronised read gray
  assign wrfull = (wr_gray == {~rd_gray_wr2[ADDR_W:ADDR_W-1],
                                rd_gray_wr2[ADDR_W-2:0]});

  //---------------------------------------------------------------
  // Used-word counts (approximate, for status reporting)
  //---------------------------------------------------------------
  // Convert synchronised gray pointers back to binary for subtraction
  function [ADDR_W:0] gray2bin;
    input [ADDR_W:0] gray;
    integer i;
    begin
      gray2bin[ADDR_W] = gray[ADDR_W];
      for (i = ADDR_W-1; i >= 0; i = i - 1)
        gray2bin[i] = gray2bin[i+1] ^ gray[i];
    end
  endfunction

  wire [ADDR_W:0] wr_bin_in_rd = gray2bin(wr_gray_rd2);
  wire [ADDR_W:0] rd_bin_in_wr = gray2bin(rd_gray_wr2);

  assign rdusedw = wr_bin_in_rd[ADDR_W-1:0] - rd_bin[ADDR_W-1:0];
  assign wrusedw = wr_bin[ADDR_W-1:0] - rd_bin_in_wr[ADDR_W-1:0];

  //---------------------------------------------------------------
  // High-watermark: running peak fill since aclr (perf instrumentation).
  // Tracked in the WRITE clock domain — the write side is where overflow
  // (wrfull) is known. wrusedw wraps to 0 at the 16-deep full point, so the
  // full condition is saturated to 4'hF; the watermark therefore reads 0xF iff
  // the queue ever reached full. Monotonic non-decreasing -> safe to 2-FF
  // synchronise into the read/status domain at the point of use (it only ever
  // changes on a new peak, so a sampler almost never sees a transition).
  wire [ADDR_W-1:0] wr_occ = wrfull ? {ADDR_W{1'b1}} : wrusedw;
  reg  [ADDR_W-1:0] wrusedw_max_r;
  always @(posedge wrclk or posedge aclr) begin
    if (aclr)
      wrusedw_max_r <= {ADDR_W{1'b0}};
    else if (wr_occ > wrusedw_max_r)
      wrusedw_max_r <= wr_occ;
  end
  assign wrusedw_max = wrusedw_max_r;

endmodule
