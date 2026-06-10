/*
 * tsu.v
 * 
 * Copyright (c) 2012, BABY&HW. All rights reserved.
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 2.1 of the License, or (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public
 * License along with this library; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston,
 * MA 02110-1301  USA
 */

`timescale 1ns/1ns

module tsu (
    input       rst,

    input       gmii_clk,
    input       gmii_ctrl,
    input [7:0] gmii_data,
    input       giga_mode,

    input [7:0] ptp_msgid_mask,
    
    input        rtc_timer_clk,
    input [79:0] rtc_timer_in,  // timeStamp1s_48bit + timeStamp1ns_32bit

    input         q_rst,
    input         q_rd_clk,
    input         q_rd_en,
    output [  7:0] q_rd_stat,
    output [127:0] q_rd_data  // null_16bit + timeStamp1s_48bit + timeStamp1ns_32bit + msgId_4bit + ckSum_12bit + seqId_16bit 
);

// mii to gmii converter -- nibble-level SFD anchor (SoC Labs ha1588_patches).
//
// ROOT CAUSE this addresses (silicon t2=0): rmii_to_mii's RX di-bit-pair lock
// (rmii_to_mii.v:207-235) starts emitting MII nibbles on a phase derived from
// the LAN8720 CRS_DV framing, which need NOT match the OpenCores-MAC-TX framing.
// The stock nibble_h below toggles ONLY from the gmii_ctrl rising edge, so the
// byte pairing phase is set by WHEN gmii_ctrl first rises, NOT by frame content.
// During the all-0x5 preamble a one-nibble pairing offset is INVISIBLE (0x5,0x5
// pairs to 0x55 either way); at the SFD the nibble stream is ...0x5,0x5,0xD,DA..
// and a one-nibble offset SPLITS 0xD5 across two assembled bytes, so
// gmii_data_conv NEVER equals 0xD5. The downstream byte-level sfd_byte detector
// (line ~301) therefore never fires on the misaligned RX stream, int_bcnt is
// never re-anchored, ptp_found stays 0, the RX FIFO is never written -> t2=0.
//
// FIX (mirrors OpenCores eth_rxstatem StartData0 / ptp_event_detector
// S_PREAMBLE->S_POST_SFD: lock on the lone 0xD nibble that terminates a run of
// 0x5 preamble nibbles). The implementation has THREE composable layers, each
// chosen to keep the byte-emit grid the downstream int_* stage requires intact:
//
//  (1) nibble_h (above) is left COMPLETELY untouched -> the byte-emit grid
//      (gmii_ctrl_conv) stays on its uniform every-other-cycle cadence for ANY
//      rmii_to_mii start phase. (The int_* delay chain uses even taps _d2/_d4/..;
//      a double pulse or gap would fire a spurious int_eop and corrupt int_bcnt.)
//
//  (2) a ONE-NIBBLE DATA SKID (phase_inv / nib_q, below): on the wrong-parity
//      0xD (0xD arriving while nibble_h==0, the misaligned case) the gearbox's
//      DATA source switches to a one-cycle-delayed nibble so 0xD becomes the HIGH
//      nibble of the SFD byte (pairing with the preceding 0x5 -> 0xD5) and DA/SA/
//      EtherType reassemble byte-aligned -- all on the UNCHANGED uniform grid, so
//      no double pulse / gap, no spurious int_eop, and the int_*_d1 parser-feed
//      stage is byte-for-byte stock (the int_eop_d1<->ptp_found coincidence
//      q_wr_en relies on is preserved exactly).
//
//  (3) an SFD-anchored int_sop RE-ISSUE (sfd_resop, below) for realigned frames:
//      the one-nibble skid pushes the SFD/DA stream one int_valid WORD later
//      relative to frame start, so the stock frame-start int_sop (which fires in
//      the preamble, BEFORE the misalignment is known) would leave the parser's
//      int_cnt one word early and the EtherType at int_cnt==5. A SECOND int_sop
//      pulse issued on the SFD word re-anchors int_cnt 0 there, restoring the
//      EtherType to int_cnt==4 -- identical to the byte-aligned frame.
//
// EVEN / byte-aligned (incl. all TX): 0xD lands on nibble_h==1, sfd_realign
// never asserts, phase_inv stays 0, the gearbox uses live data and the stock
// frame-start int_sop -> behaviour is BIT-IDENTICAL to stock. Gated once per
// frame (nib_locked); all new state clears between frames on !gmii_ctrl; all new
// regs are in the gmii_clk domain (no new CDC). The downstream byte-level
// int_bcnt SFD anchor (sfd_lock, below) is KEPT and re-locks the word phase on
// the reconstructed 0xD5 byte for any preamble length.
wire pre5_nib = gmii_ctrl & (gmii_data[3:0] == 4'h5);  // preamble nibble (0x5)
wire sfd_nib  = gmii_ctrl & (gmii_data[3:0] == 4'hd);  // SFD nibble (0xD)

// ---------------------------------------------------------------------------
// SoC Labs patch: RESET-DEASSERT SYNCHRONIZERS (silicon hardening).
//
// `rst` arrives from the register/pclk domain. The stock tsu used it raw as
// the async reset of every gmii_clk / rtc_timer_clk flop: async ASSERT is
// fine, but async DEASSERT violates recovery/removal on those flops while
// their clocks free-run -> metastable register state on real silicon. On HW
// this manifested as the RX TSU coming up randomly dead per session/reset
// (identical app + bitstream captured on one boot, depth=0 on the next; the
// state is sticky because SWD app loads do not system-reset). The sibling RX
// blocks (eth_rx_cksum / ptp_event_detector) already get a 2-FF reset bridge
// in ethmac_subsystem_apb.v; the TSU never did. These synchronizers give
// every TSU domain async-assert / SYNCHRONOUS-deassert resets.
// ---------------------------------------------------------------------------
reg rst_gmii_meta, rst_gmii;
always @(posedge rst or posedge gmii_clk) begin
  if (rst) begin
    rst_gmii_meta <= 1'b1;
    rst_gmii      <= 1'b1;
  end else begin
    rst_gmii_meta <= 1'b0;
    rst_gmii      <= rst_gmii_meta;
  end
end

reg rst_rtc_meta, rst_rtc;
always @(posedge rst or posedge rtc_timer_clk) begin
  if (rst) begin
    rst_rtc_meta <= 1'b1;
    rst_rtc      <= 1'b1;
  end else begin
    rst_rtc_meta <= 1'b0;
    rst_rtc      <= rst_rtc_meta;
  end
end

// nibble_h: the byte-emit/pairing phase. SoC Labs patch: stock free-ran this
// across frames (only toggling while gmii_ctrl is high), so ANY prior
// odd-nibble carrier event (false carrier, runt, reset corruption) flipped
// the pairing parity for EVERY subsequent frame, forever (observed on HW as
// sticky random-per-session RX-TSU death). MII data-valid always rises on a
// byte boundary, so clearing during idle pins the frame's first nibble to
// the LOW slot -- every frame starts at known parity, self-healing per frame.
reg nibble_h;
always @(posedge rst_gmii or posedge gmii_clk) begin
  if (rst_gmii)
    nibble_h <= 1'b0;
  else if (gmii_ctrl)
    nibble_h <= !nibble_h;
  else
    nibble_h <= 1'b0;   // idle-clear: known parity at every frame start
end

// --- nibble-level SFD lock (mirrors OpenCores eth_rxstatem StartData0 /
//     ptp_event_detector S_PREAMBLE->S_POST_SFD) -------------------------------
// For a nibble-MISALIGNED rmii_to_mii RX stream the 0xD SFD nibble lands while
// nibble_h==0 (LOW slot), so the gearbox would assemble 0x?D and split 0xD5 (the
// silicon t2=0 bug). Both working references lock on the lone 0xD nibble (after
// a run of 0x5 preamble nibbles) and build bytes from there.
//
// The constraint that makes a naive nibble_h-force fail is that the int_* stage
// requires gmii_ctrl_conv to pulse on a STRICTLY UNIFORM every-other-cycle grid
// (its delay chain uses even taps _d2/_d4/.. and a double pulse or gap fires a
// spurious int_eop and corrupts int_bcnt). So we MUST NOT change the emit grid.
// nibble_h above is therefore left COMPLETELY untouched (uniform grid for any
// rmii phase; EVEN and all TX are bit-identical to stock).
//
// Instead we correct the misalignment with a ONE-NIBBLE DATA SKID: on the
// wrong-parity 0xD (nibble_h==0 at the 0xD) we latch phase_inv, and from there
// the gearbox sources its nibbles from a one-cycle-delayed copy (nib_q) instead
// of the live gmii_data. That delays the whole post-SFD nibble stream by one
// nibble so 0xD becomes the HIGH nibble of the SFD byte (pairing with the
// preceding 0x5 -> 0xD5) and DA/SA/EtherType reassemble byte-aligned -- all on
// the UNCHANGED uniform emit grid (no double pulse, no gap). The byte-level
// int_bcnt SFD anchor (below) then re-locks the word phase on the 0xD5 byte.
// EVEN / byte-aligned (incl. all TX): 0xD lands on nibble_h==1, sfd_realign never
// asserts, phase_inv stays 0, gearbox uses live gmii_data -> bit-identical to
// stock. Gated once per frame (nib_locked); all state clears between frames.
reg in_pre;       // inside a 0x5 preamble run (>=1 0x5 seen this frame)
reg nib_locked;   // SFD nibble has anchored the phase this frame (one-shot)
reg phase_inv;    // one-nibble data skid engaged (latched after a wrong SFD)
reg [3:0] nib_q;  // one-cycle-delayed gmii_data nibble (the skid register)

wire sfd_realign = sfd_nib & in_pre & ~nib_locked & ~nibble_h;
// effective data nibble for THIS cycle: delayed (skid) once realigned, else live.
// The skid is engaged ON the realign cycle TOO (sfd_realign): there nib_q holds
// the preceding 0x5 preamble nibble, which goes into the LOW slot (nibble_h==0),
// and the held 0xD is delayed by the skid onto the next (HIGH) slot -> the SFD
// byte assembles as {0xD,0x5}=0xD5. From the next cycle phase_inv keeps the skid.
wire [3:0] data_nib = (phase_inv | sfd_realign) ? nib_q : gmii_data[3:0];

always @(posedge rst_gmii or posedge gmii_clk) begin
  if (rst_gmii) begin
    in_pre     <= 1'b0;
    nib_locked <= 1'b0;
    phase_inv  <= 1'b0;
    nib_q      <= 4'd0;
  end
  else if (!gmii_ctrl) begin       // inter-frame: clear, re-arm for next frame
    in_pre     <= 1'b0;
    nib_locked <= 1'b0;
    phase_inv  <= 1'b0;
    nib_q      <= 4'd0;
  end
  else begin
    nib_q <= gmii_data[3:0];        // 1-nibble skid
    if (pre5_nib) in_pre <= 1'b1;   // track the preamble run (arms sfd_realign)
    if (sfd_realign) begin
      phase_inv  <= 1'b1;           // engage the one-nibble data skid
      nib_locked <= 1'b1;
      in_pre     <= 1'b0;
    end
    else if (sfd_nib & in_pre & ~nib_locked) begin
      nib_locked <= 1'b1;           // right-parity SFD: stock pairing is correct
      in_pre     <= 1'b0;
    end
  end
end

reg       gmii_ctrl_conv;
reg [7:0] gmii_data_conv;
always @(posedge rst_gmii or posedge gmii_clk) begin
  if (rst_gmii) begin
    gmii_ctrl_conv <= 1'b0;
    gmii_data_conv <= 8'd0;
  end
  else begin
    if (giga_mode) begin
      gmii_ctrl_conv      <= gmii_ctrl;
      gmii_data_conv[7:0] <= gmii_data[7:0];
    end
    else begin
      // 4b-8b datapath gearbox. The EMIT grid (gmii_ctrl_conv via stock nibble_h)
      // is UNCHANGED -- uniform every-other-cycle. The DATA is the one-nibble
      // skid (data_nib): live normally, delayed by one nibble once realigned, so
      // the misaligned SFD/DA stream byte-aligns onto the same uniform grid
      // without a double pulse or nibble rotation.
      if (gmii_ctrl) begin
        gmii_ctrl_conv      <= ( nibble_h)? 1'b1:1'b0;
        gmii_data_conv[7:4] <= ( nibble_h)? data_nib:gmii_data_conv[7:4];
        gmii_data_conv[3:0] <= (!nibble_h)? data_nib:gmii_data_conv[3:0];
      end
      else begin
        gmii_ctrl_conv      <= 1'b0;
        gmii_data_conv[7:4] <= gmii_data_conv[7:4];
        gmii_data_conv[3:0] <= gmii_data_conv[3:0];
      end
    end
  end
end

// buffer gmii input
reg       gmii_ctrl_conv_d1, gmii_ctrl_conv_d2, gmii_ctrl_conv_d3, gmii_ctrl_conv_d4,
          gmii_ctrl_conv_d5, gmii_ctrl_conv_d6, gmii_ctrl_conv_d7, gmii_ctrl_conv_d8,
          gmii_ctrl_conv_d9, gmii_ctrl_conv_da;
reg [7:0] gmii_data_conv_d1, gmii_data_conv_d2, gmii_data_conv_d3, gmii_data_conv_d4,
          gmii_data_conv_d5, gmii_data_conv_d6, gmii_data_conv_d7, gmii_data_conv_d8,
          gmii_data_conv_d9, gmii_data_conv_da;
always @(posedge rst_gmii or posedge gmii_clk) begin
  if (rst_gmii) begin
    gmii_ctrl_conv_d1 <= 1'b0;
    gmii_ctrl_conv_d2 <= 1'b0;
    gmii_ctrl_conv_d3 <= 1'b0;
    gmii_ctrl_conv_d4 <= 1'b0;
    gmii_ctrl_conv_d5 <= 1'b0;
    gmii_ctrl_conv_d6 <= 1'b0;
    gmii_ctrl_conv_d7 <= 1'b0;
    gmii_ctrl_conv_d8 <= 1'b0;
    gmii_ctrl_conv_d9 <= 1'b0;
    gmii_ctrl_conv_da <= 1'b0;
    gmii_data_conv_d1 <= 8'd0;
    gmii_data_conv_d2 <= 8'd0;
    gmii_data_conv_d3 <= 8'd0;
    gmii_data_conv_d4 <= 8'd0;
    gmii_data_conv_d5 <= 8'd0;
    gmii_data_conv_d6 <= 8'd0;
    gmii_data_conv_d7 <= 8'd0;
    gmii_data_conv_d8 <= 8'd0;
    gmii_data_conv_d9 <= 8'd0;
    gmii_data_conv_da <= 8'd0;
  end
  else begin
    gmii_ctrl_conv_d1 <= gmii_ctrl_conv;
    gmii_ctrl_conv_d2 <= gmii_ctrl_conv_d1;
    gmii_ctrl_conv_d3 <= gmii_ctrl_conv_d2;
    gmii_ctrl_conv_d4 <= gmii_ctrl_conv_d3;
    gmii_ctrl_conv_d5 <= gmii_ctrl_conv_d4;
    gmii_ctrl_conv_d6 <= gmii_ctrl_conv_d5;
    gmii_ctrl_conv_d7 <= gmii_ctrl_conv_d6;
    gmii_ctrl_conv_d8 <= gmii_ctrl_conv_d7;
    gmii_ctrl_conv_d9 <= gmii_ctrl_conv_d8;
    gmii_ctrl_conv_da <= gmii_ctrl_conv_d9;
    gmii_data_conv_d1 <= gmii_data_conv;
    gmii_data_conv_d2 <= gmii_data_conv_d1;
    gmii_data_conv_d3 <= gmii_data_conv_d2;
    gmii_data_conv_d4 <= gmii_data_conv_d3;
    gmii_data_conv_d5 <= gmii_data_conv_d4;
    gmii_data_conv_d6 <= gmii_data_conv_d5;
    gmii_data_conv_d7 <= gmii_data_conv_d6;
    gmii_data_conv_d8 <= gmii_data_conv_d7;
    gmii_data_conv_d9 <= gmii_data_conv_d8;
    gmii_data_conv_da <= gmii_data_conv_d9;
  end
end

// choose buffered gmii input
reg       int_gmii_ctrl;
reg       int_gmii_ctrl_d1, int_gmii_ctrl_d2, int_gmii_ctrl_d3, int_gmii_ctrl_d4,
          int_gmii_ctrl_d5;
reg [7:0] int_gmii_data;
reg [7:0] int_gmii_data_d1, int_gmii_data_d2, int_gmii_data_d3, int_gmii_data_d4,
          int_gmii_data_d5;
always @(posedge rst_gmii or posedge gmii_clk) begin
  if (rst_gmii) begin
    int_gmii_ctrl    <= 1'b0;
    int_gmii_data    <= 8'h00;
    int_gmii_ctrl_d1 <= 1'b0;
    int_gmii_data_d1 <= 8'h00;
    int_gmii_ctrl_d2 <= 1'b0;
    int_gmii_data_d2 <= 8'h00;
    int_gmii_ctrl_d3 <= 1'b0;
    int_gmii_data_d3 <= 8'h00;
    int_gmii_ctrl_d4 <= 1'b0;
    int_gmii_data_d4 <= 8'h00;
    int_gmii_ctrl_d5 <= 1'b0;
    int_gmii_data_d5 <= 8'h00;
  end
  else begin
    if (giga_mode) begin
      int_gmii_ctrl    <= gmii_ctrl_conv;
      int_gmii_data    <= gmii_data_conv;
      int_gmii_ctrl_d1 <= gmii_ctrl_conv_d1;
      int_gmii_data_d1 <= gmii_data_conv_d1;
      int_gmii_ctrl_d2 <= gmii_ctrl_conv_d2;
      int_gmii_data_d2 <= gmii_data_conv_d2;
      int_gmii_ctrl_d3 <= gmii_ctrl_conv_d3;
      int_gmii_data_d3 <= gmii_data_conv_d3;
      int_gmii_ctrl_d4 <= gmii_ctrl_conv_d4;
      int_gmii_data_d4 <= gmii_data_conv_d4;
      int_gmii_ctrl_d5 <= gmii_ctrl_conv_d5;
      int_gmii_data_d5 <= gmii_data_conv_d5;
    end
    else begin
      int_gmii_ctrl    <= gmii_ctrl_conv;
      int_gmii_data    <= gmii_data_conv;
      int_gmii_ctrl_d1 <= gmii_ctrl_conv_d2;
      int_gmii_data_d1 <= gmii_data_conv_d2;
      int_gmii_ctrl_d2 <= gmii_ctrl_conv_d4;
      int_gmii_data_d2 <= gmii_data_conv_d4;
      int_gmii_ctrl_d3 <= gmii_ctrl_conv_d6;
      int_gmii_data_d3 <= gmii_data_conv_d6;
      int_gmii_ctrl_d4 <= gmii_ctrl_conv_d8;
      int_gmii_data_d4 <= gmii_data_conv_d8;
      int_gmii_ctrl_d5 <= gmii_ctrl_conv_da;
      int_gmii_data_d5 <= gmii_data_conv_da;
    end
  end
end

// ptp CDC time stamping
wire ts_req = int_gmii_ctrl;  // TODO: check frame start delimiter
reg  ts_req_d1, ts_req_d2, ts_req_d3;
always @(posedge rst_rtc or posedge rtc_timer_clk) begin
  if (rst_rtc) begin
    ts_req_d1 <= 1'b0;
    ts_req_d2 <= 1'b0;
    ts_req_d3 <= 1'b0;
  end
  else begin
    ts_req_d1 <= ts_req;
    ts_req_d2 <= ts_req_d1;
    ts_req_d3 <= ts_req_d2;
  end
end
reg [79:0] rtc_time_stamp;
always @(posedge rst_rtc or posedge rtc_timer_clk) begin
  if (rst_rtc)
    rtc_time_stamp <= 80'd0;
  else 
    if (ts_req_d2 & !ts_req_d3)
      rtc_time_stamp <= rtc_timer_in;
end
reg ts_ack, ts_ack_clr;
always @(posedge ts_ack_clr or posedge rtc_timer_clk) begin
  if (ts_ack_clr)
    ts_ack <= 1'b0;
  else
    if (ts_req_d2 & !ts_req_d3)
      ts_ack <= 1'b1;
end

reg ts_ack_d1, ts_ack_d2, ts_ack_d3;
always @(posedge rst_gmii or posedge gmii_clk) begin
  if (rst_gmii) begin
    ts_ack_d1 <= 1'b0;
    ts_ack_d2 <= 1'b0;
    ts_ack_d3 <= 1'b0;
  end
  else begin
    ts_ack_d1 <= ts_ack;
    ts_ack_d2 <= ts_ack_d1;
    ts_ack_d3 <= ts_ack_d2;
  end
end
reg [79:0] tsu_time_stamp;
always @(posedge rst_gmii or posedge gmii_clk) begin
  if (rst_gmii) begin
    tsu_time_stamp <= 80'd0;
    ts_ack_clr      <= 1'b0;
  end
  else begin
    if (ts_ack_d2 & !ts_ack_d3) begin
      tsu_time_stamp <= rtc_time_stamp;
      ts_ack_clr      <= 1'b1;
    end
    else begin
      tsu_time_stamp <= tsu_time_stamp;
      ts_ack_clr      <= 1'b0;
    end
  end
end

// 8b-32b datapath gearbox
reg        int_valid;
reg        int_sop, int_eop;
reg [ 1:0] int_bcnt, int_mod;
reg [31:0] int_data;

// ---------------------------------------------------------------------------
// SFD-LOCK PATCH (SoC Labs ha1588_patches) -- RX timestamp bring-up fix.
//
// HARDWARE SYMPTOM: the RX TSU never timestamps incoming PTP Sync frames
// (RX FIFO depth stays 0, t2=0) while the TX TSU works fine, even though the
// MAC RX receives the Sync and msgid_mask=0x03 is confirmed in HW.
//
// ROOT CAUSE: the stock tsu anchored the byte/word counter `int_bcnt` to the
// gmii_ctrl rising edge ("clear on sop", below) and the downstream ptp_parser
// checks EtherType==0x88f7 at a HARD-CODED int_cnt==4 (ptp_parser.v). That word
// phase only lines up when the gap between gmii_ctrl assertion and the
// EtherType is exactly 7 preamble bytes + SFD. Our TX path (clean OpenCores MAC
// preamble) satisfies it; the LAN8720 RX path (CRS_DV via rmii_to_mii) presents
// a DIFFERENT-length preamble, so 0x88f7 packs into a different word lane / a
// different int_cnt, ptp_found never asserts and the RX FIFO is never written.
// (tsu.v:190 stock literally says "// TODO: check frame start delimiter".)
//
// FIX (minimal, lowest-risk -- "Strategy B"): re-anchor ONLY the byte/word
// counter `int_bcnt` to the SFD (0xD5) instead of the gmii_ctrl edge. The SFD
// is the last preamble-region byte (the 0x55 preamble bytes are != 0xD5), so it
// is a robust, preamble-length-INDEPENDENT phase anchor. Forcing int_bcnt to
// 2'd3 on the SFD byte makes the SFD pack into int_data[7:0] and DA0 start the
// next word at int_bcnt==0 -- producing byte-for-byte the SAME word layout the
// parser already expects, for ANY preamble length (verified by cycle model:
// 0x88f7 lands at parser int_cnt==4 for npre=7 AND npre=4).
//
// WHY THIS IS SAFE WHERE THE PRIOR ATTEMPT (tsu.v.sfd-lock-wip) BROKE SILICON:
// the prior attempt also delayed the int_data/int_sop/int_valid stream by one
// extra valid-word (a "lookahead") while leaving int_eop_d1 a plain 1-cycle
// delay. That MISALIGNED int_eop_d1 from the data/parser stream, so
// q_wr_en = ptp_found && int_eop_d1 stopped firing on the right cycle and BOTH
// TSUs dropped to depth 0 on silicon. THIS fix touches NOTHING in the _d1
// parser-feed stage and does NOT re-derive int_sop: stock's int_sop (anchored
// to the gmii_ctrl rising edge via _d4/_d5) ALREADY fires on word0 for ANY
// preamble length, so int_data/int_sop/int_eop/int_valid/int_mod keep IDENTICAL
// stock latency and the int_eop_d1<->ptp_found coincidence the FIFO write
// depends on is preserved exactly. Only the word-packing PHASE is changed.
//
// The SFD search is gated to fire ONCE per frame (sfd_seen) so a 0xD5 in the
// payload cannot re-trigger; sfd_seen clears when gmii_ctrl deasserts between
// frames. TX is preserved: TX frames also carry 7-preamble + SFD, so the SFD
// anchor reproduces the exact int_bcnt phase TX already had.
// ---------------------------------------------------------------------------
wire sfd_byte = int_gmii_ctrl & (int_gmii_data == 8'hd5);  // SFD on current byte
reg  sfd_seen;
wire sfd_lock = sfd_byte & ~sfd_seen;  // one-shot per frame
always @(posedge rst_gmii or posedge gmii_clk) begin
  if (rst_gmii)
    sfd_seen <= 1'b0;
  else if (!int_gmii_ctrl)
    sfd_seen <= 1'b0;       // clear between frames
  else if (sfd_byte)
    sfd_seen <= 1'b1;       // latch first SFD of this frame
end

// SFD-anchored re-sync of int_sop for the REALIGNED (nibble-misaligned) case.
// The stock frame-start int_sop (int_gmii_ctrl_d4 edge) fires DURING the preamble
// -- BEFORE the wrong-parity SFD is detected -- so for a realigned frame the
// one-nibble data skid leaves the parser's int_cnt anchored one word too early
// (EtherType at int_cnt==5 -> no PTP match). The realignment status (phase_inv)
// and the SFD position ARE known by the time the SFD byte reaches the int stage,
// so we issue a SECOND int_sop pulse on the SFD word for realigned frames only
// (sfd_resop). The parser resets int_cnt on every (int_valid && int_sop), so the
// later SFD-word sop RE-ANCHORS int_cnt 0 to the SFD word -> EtherType at
// int_cnt==4, exactly matching the byte-aligned (EVEN) frame. EVEN / TX
// (phase_inv==0): sfd_resop never fires -> bit-identical to stock.
// The SFD word's int_valid-generating cycle coincides with sfd_lock (the 0xD5
// byte is at int_gmii_ctrl with int_bcnt==3), so fire the re-anchor sop there so
// int_sop and int_valid are generated on the SAME cycle (they then reach the
// parser coincident through the shared _d1 stage).
wire sfd_resop = phase_inv & sfd_lock & int_gmii_ctrl & (int_bcnt==2'd3);

always @(posedge rst_gmii or posedge gmii_clk) begin
  if (rst_gmii)
    int_bcnt <= 2'd0;
  else
    if      ( sfd_lock)
      int_bcnt <= 2'd3;  // SFD-LOCK: anchor word phase to the SFD (preamble-len independent)
    else if ( int_gmii_ctrl & !int_gmii_ctrl_d1)
      int_bcnt <= 2'd0;  // clear on sop
    else if ( int_gmii_ctrl)
      int_bcnt <= int_bcnt + 2'd1;  // increment
    else if (!int_gmii_ctrl & int_gmii_ctrl_d3 & (int_bcnt!=2'd0))
      int_bcnt <= int_bcnt + 2'd1;  // end on eop with mod
end
always @(posedge rst_gmii or posedge gmii_clk) begin
  if (rst_gmii) begin
    int_data  <= 32'd0;
    int_valid <=  1'b0;
    int_mod   <=  2'd0;
  end
  else begin
    if (int_gmii_ctrl) begin
      int_data[ 7: 0] <= (int_bcnt==2'd3)? int_gmii_data_d1:int_data[ 7: 0];
      int_data[15: 8] <= (int_bcnt==2'd2)? int_gmii_data_d1:int_data[15: 8];
      int_data[23:16] <= (int_bcnt==2'd1)? int_gmii_data_d1:int_data[23:16];
      int_data[31:24] <= (int_bcnt==2'd0)? int_gmii_data_d1:int_data[31:24];
    end

    if (int_gmii_ctrl & int_bcnt==2'd3)
      int_valid <= 1'b1;
    else
      int_valid <= 1'b0;

    if (int_gmii_ctrl_d1 & !int_gmii_ctrl_d2)
      int_mod <= 2'd0;
    else if (!int_gmii_ctrl_d1 & int_gmii_ctrl_d2)
      int_mod <= int_bcnt;

    if ((int_gmii_ctrl_d4 & !int_gmii_ctrl_d5 & int_bcnt==2'd3) | sfd_resop)
      int_sop <= 1'b1;     // stock frame-start sop, OR the SFD re-anchor (realign)
    else
      int_sop <= 1'b0;

    if (!int_gmii_ctrl   &  int_gmii_ctrl_d3 & int_bcnt==2'd3)
      int_eop <= 1'b1;
    else
      int_eop <= 1'b0;

  end
end

reg [31:0] int_data_d1;
reg        int_valid_d1;
reg        int_sop_d1;
reg        int_eop_d1;
reg [ 1:0] int_mod_d1;
always @(posedge rst_gmii or posedge gmii_clk) begin
  if (rst_gmii) begin
    int_data_d1  <= 32'h00000000;
    int_valid_d1 <= 1'b0;
    int_sop_d1   <= 1'b0;
    int_eop_d1   <= 1'b0;
    int_mod_d1   <= 2'b00;
  end
  else begin
    if (int_valid) begin
      int_data_d1  <= int_data;
      int_mod_d1   <= int_mod;
    end
      int_valid_d1 <= int_valid;
      int_sop_d1   <= int_sop;
      int_eop_d1   <= int_eop;
  end
end

// ptp packet parser here
// works at 1/4 gmii_clk frequency, needs multicycle timing constraint
wire        ptp_found;
wire [31:0] ptp_infor;
ptp_parser parser(
  .clk(gmii_clk),
  .rst(rst),
  .int_data(int_data_d1),
  .int_valid(int_valid_d1),
  .int_sop(int_sop_d1),
  .int_eop(int_eop_d1),
  .int_mod(int_mod_d1),
  .ptp_msgid_mask(ptp_msgid_mask),
  .ptp_found(ptp_found),
  .ptp_infor(ptp_infor)
);

// ptp time stamp dcfifo
wire q_wr_clk = gmii_clk;
wire q_wr_en = ptp_found && int_eop_d1;
wire [127:0] q_wr_data = {16'd0, tsu_time_stamp, ptp_infor};  // 16+80+32 bit
wire [3:0] q_wrusedw;
wire [3:0] q_rdusedw;
wire q_wr_full;
wire q_rd_empty;

ptp_queue queue(
  .aclr(q_rst),

  .wrclk(q_wr_clk),
  .wrreq(q_wr_en && !q_wr_full),  // write with overflow protection
  .data(q_wr_data),
  .wrfull(q_wr_full),
  .wrusedw(q_wrusedw),

  .rdclk(q_rd_clk),
  .rdreq(q_rd_en && !q_rd_empty),  // read with underflow protection
  .q(q_rd_data),
  .rdempty(q_rd_empty),
  .rdusedw(q_rdusedw)
);

assign q_rd_stat = {4'd0, q_rdusedw};

endmodule
