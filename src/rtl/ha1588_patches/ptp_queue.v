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

module ptp_queue #(
  parameter ADDR_W = 4          // FIFO address width (depth = 1<<ADDR_W = 16)
) (
  input          aclr,
  input  [127:0] data,
  input          rdclk,
  input          rdreq,
  input          wrclk,
  input          wrreq,
  output [127:0] q,
  output         rdempty,
  output [ADDR_W:0] rdusedw,   // Bug r5-#1: ADDR_W+1 bits so a FULL (16) FIFO
  output         wrfull,       // reads 0x10, not 0 (4-bit aliased full->empty)
  output [ADDR_W:0] wrusedw,
  output [  3:0] usedw_max     // running peak fill since aclr (perf high-watermark)
);

  // FIFO depth = 16 (ADDR_W is now a header parameter, default 4)
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

  // Bug r5-#1: subtract the FULL (ADDR_W+1)-bit pointers, not just the low
  // ADDR_W bits — otherwise a full FIFO (16) wraps to 0 and reads as empty, so
  // firmware never drains it (FIFO then wedges full, all later PTP TS lost).
  assign rdusedw = wr_bin_in_rd - rd_bin;
  assign wrusedw = wr_bin - rd_bin_in_wr;

  //---------------------------------------------------------------
  // High-watermark: running peak fill since aclr (perf instrumentation).
  // Tracked in the READ clock domain on `rdusedw`. The read clock (rdclk =
  // the register/system clock) is FREE-RUNNING, so the max-tracker always gets
  // edges. (An earlier write-clock-domain version tracked on `wrclk` = the RX
  // gmii clock, which on silicon is GATED — only active during frame reception
  // — so the tracker missed the peak and read 0 even though the queue filled.
  // The read-domain version is also CDC-free: rdusedw and this reg share rdclk.)
  // Bug r5-#1: rdusedw is now the true (ADDR_W+1)-bit occupancy (0..16); full no
  // longer aliases to 0, so the old "!rdempty && reads-0 -> saturate to 0xF"
  // hack is gone. The usedw_max PORT stays ADDR_W-wide for downstream stability,
  // so the full point (16) saturates to 4'hF (0xF == "reached full").
  wire [ADDR_W:0] rd_occ = rdusedw;
  reg  [ADDR_W:0] usedw_max_r;
  always @(posedge rdclk or posedge aclr) begin
    if (aclr)
      usedw_max_r <= {(ADDR_W+1){1'b0}};
    else if (rd_occ > usedw_max_r)
      usedw_max_r <= rd_occ;
  end
  assign usedw_max = usedw_max_r[ADDR_W] ? {ADDR_W{1'b1}}
                                         : usedw_max_r[ADDR_W-1:0];

endmodule
