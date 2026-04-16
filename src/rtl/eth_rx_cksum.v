//-----------------------------------------------------------------------------
// eth_rx_cksum.v — Area-optimised RX checksum calculator (flags-only mode)
//-----------------------------------------------------------------------------
// Passive MII RX checksum calculator for the SoCLabs Ethernet MAC subsystem.
//
// Snoops the MII RX nibble stream, parses Ethernet + VLAN + IPv4 headers,
// and computes IP header + L4 (UDP/TCP) checksums. Per-frame results are
// reduced to a 40-bit {seqnum, flags} snapshot and queued through a small
// async FIFO so software can check IP_OK / L4_OK in two register reads.
//
// Design philosophy: SW already has the frame in DMA memory — the block
// only needs to say "was the checksum good?" and which protocol was
// detected. Detailed fields (src/dst IP, ports, calculated checksum
// values) are NOT stored; SW reads those from the DMA buffer when needed.
// This keeps the snapshot FIFO narrow (40 bits) and the total area small.
//
// IPv6 is NOT supported in this revision — IPv6 frames are passed through
// with IS_IPV4=0 and no L4 checking. Add IPv6 pseudo-header logic when
// the stack requires it.
//
// Address map (simplified):
//   0x00  ID              RO  0x434B534D ("CKSM")
//   0x04  CTRL            RW  EN, MODE, IRQ_EN_*, CLR_*
//   0x08  STATUS          RO  FIFO level/empty/full/ovf, depth param
//   0x0C  FRAME_COUNT     RO  Frames pushed to FIFO
//   0x10  IP_GOOD_COUNT   RO  IPv4 frames with valid IP header cksum
//   0x14  IP_BAD_COUNT    RO  IPv4 frames with invalid IP header cksum
//   0x18  L4_GOOD_COUNT   RO  UDP/TCP frames with valid L4 cksum
//   0x1C  L4_BAD_COUNT    RO  UDP/TCP frames with invalid L4 cksum
//   0x20  LAST_FLAGS      RO  Flags byte from FIFO head (peek)
//   0x24  LAST_SEQNUM     RO  Seqnum from FIFO head; READING POPS
//   0x28  IRQ_STATUS      RO  Live interrupt pending flags
//
// A joint work commissioned on behalf of SoC Labs, under Arm Academic
// Access license.
// Copyright (C) 2026, SoC Labs (www.soclabs.org)
//-----------------------------------------------------------------------------

module eth_rx_cksum #(
  parameter SNAPSHOT_FIFO_DEPTH = 2   // Reduced from 8 for area savings
) (
  input  wire        pclk,
  input  wire        presetn,
  input  wire        mrx_clk_i,
  input  wire        mrx_rstn_i,
  input  wire  [3:0] mrxd_i,
  input  wire        mrxdv_i,
  input  wire        mrxerr_i,
  input  wire        psel,
  input  wire        penable,
  input  wire [31:0] paddr,
  input  wire        pwrite,
  input  wire [31:0] pwdata,
  input  wire  [3:0] pstrb,
  output wire [31:0] prdata,
  output wire        pready,
  output wire        pslverr,
  output wire        cksum_int_o
);

  // verilator lint_off UNUSED
  wire _unused = &{1'b0, pstrb, paddr[31:8], 1'b0};
  // verilator lint_on UNUSED

  localparam FIFO_AW = $clog2(SNAPSHOT_FIFO_DEPTH);
  localparam SNAP_W  = 40;  // {seqnum[31:0], flags[7:0]}

  // ── Register offsets ─────────────────────────────────────────────────
  localparam [7:0] OFF_ID             = 8'h00;
  localparam [7:0] OFF_CTRL           = 8'h04;
  localparam [7:0] OFF_STATUS         = 8'h08;
  localparam [7:0] OFF_FRAME_COUNT    = 8'h0C;
  localparam [7:0] OFF_IP_GOOD_COUNT  = 8'h10;
  localparam [7:0] OFF_IP_BAD_COUNT   = 8'h14;
  localparam [7:0] OFF_L4_GOOD_COUNT  = 8'h18;
  localparam [7:0] OFF_L4_BAD_COUNT   = 8'h1C;
  localparam [7:0] OFF_LAST_FLAGS     = 8'h20;
  localparam [7:0] OFF_LAST_SEQNUM   = 8'h24;  // read-pops
  localparam [7:0] OFF_IRQ_STATUS     = 8'h28;

  localparam [31:0] ID_VALUE = 32'h434B534D;
  localparam [1:0]  MODE_LAST_ONLY = 2'b00;
  localparam [1:0]  MODE_DROP_NEW  = 2'b01;
  localparam [1:0]  MODE_DROP_OLD  = 2'b10;

  // ════════════════════════════════════════════════════════════════════
  //  APB CTRL register
  // ════════════════════════════════════════════════════════════════════
  wire access_w = psel & penable & pwrite;
  wire access_r = psel & penable & ~pwrite;
  wire [7:0] off = paddr[7:0] & 8'hFC;

  reg        ctrl_en;
  reg  [1:0] ctrl_mode;
  reg        ctrl_irq_en_frame, ctrl_irq_en_bad, ctrl_irq_en_ovf;
  reg        clr_counters_pulse, clr_fifo_pulse, clr_ovf_pulse;

  always @(posedge pclk or negedge presetn) begin
    if (!presetn) begin
      ctrl_en <= 1'b0; ctrl_mode <= 2'b00;
      ctrl_irq_en_frame <= 1'b0; ctrl_irq_en_bad <= 1'b0; ctrl_irq_en_ovf <= 1'b0;
      clr_counters_pulse <= 1'b0; clr_fifo_pulse <= 1'b0; clr_ovf_pulse <= 1'b0;
    end else begin
      clr_counters_pulse <= 1'b0; clr_fifo_pulse <= 1'b0; clr_ovf_pulse <= 1'b0;
      if (access_w && off == OFF_CTRL) begin
        ctrl_en <= pwdata[0]; ctrl_mode <= pwdata[2:1];
        ctrl_irq_en_frame <= pwdata[8]; ctrl_irq_en_bad <= pwdata[9]; ctrl_irq_en_ovf <= pwdata[10];
        clr_counters_pulse <= pwdata[16]; clr_fifo_pulse <= pwdata[17]; clr_ovf_pulse <= pwdata[18];
      end
    end
  end

  // ════════════════════════════════════════════════════════════════════
  //  EN sync to mrx_clk
  // ════════════════════════════════════════════════════════════════════
  reg [1:0] en_mrx_sync;
  always @(posedge mrx_clk_i or negedge mrx_rstn_i)
    if (!mrx_rstn_i) en_mrx_sync <= 2'b0;
    else             en_mrx_sync <= {en_mrx_sync[0], ctrl_en};
  wire en_mrx = en_mrx_sync[1];

  // ════════════════════════════════════════════════════════════════════
  //  MII nibble→byte assembler
  // ════════════════════════════════════════════════════════════════════
  reg       nib_phase;
  reg [3:0] nib_lo;
  reg [7:0] byte_data;
  reg       byte_valid;

  always @(posedge mrx_clk_i or negedge mrx_rstn_i) begin
    if (!mrx_rstn_i) begin
      nib_phase <= 1'b0; nib_lo <= 4'h0; byte_data <= 8'h0; byte_valid <= 1'b0;
    end else if (mrxdv_i) begin
      if (!nib_phase) begin
        nib_lo <= mrxd_i; nib_phase <= 1'b1; byte_valid <= 1'b0;
      end else begin
        byte_data <= {mrxd_i, nib_lo}; nib_phase <= 1'b0; byte_valid <= 1'b1;
      end
    end else begin
      nib_phase <= 1'b0; byte_valid <= 1'b0;
    end
  end

  // ════════════════════════════════════════════════════════════════════
  //  SFD + byte counter + RX error
  // ════════════════════════════════════════════════════════════════════
  reg        sfd_seen;
  reg [10:0] byte_idx;
  reg        frame_mrxerr_q;

  always @(posedge mrx_clk_i or negedge mrx_rstn_i)
    if (!mrx_rstn_i)             frame_mrxerr_q <= 1'b0;
    else if (!mrxdv_i)           frame_mrxerr_q <= 1'b0;
    else if (mrxdv_i & mrxerr_i) frame_mrxerr_q <= 1'b1;

  always @(posedge mrx_clk_i or negedge mrx_rstn_i) begin
    if (!mrx_rstn_i) begin sfd_seen <= 1'b0; byte_idx <= 11'd0;
    end else if (!mrxdv_i) begin sfd_seen <= 1'b0; byte_idx <= 11'd0;
    end else if (byte_valid) begin
      if (!sfd_seen) begin
        if (byte_data == 8'hD5) begin sfd_seen <= 1'b1; byte_idx <= 11'd0; end
      end else byte_idx <= byte_idx + 11'd1;
    end
  end

  wire post_sfd      = sfd_seen;
  wire post_sfd_byte = post_sfd & byte_valid;
  wire [10:0] cur_idx = byte_idx;

  // ════════════════════════════════════════════════════════════════════
  //  Parser: Ethernet + VLAN + IPv4 header + L4 (UDP/TCP)
  // ════════════════════════════════════════════════════════════════════
  reg [15:0] first_type_q, ethertype_q;
  reg        vlan_q, is_ipv4_q;
  reg  [3:0] ipv4_ihl_q;
  reg [15:0] ipv4_total_len_q;
  reg  [7:0] ipv4_proto_q;
  reg [15:0] ipv4_wire_cksum_q, ipv4_flags_frag_q;
  reg        is_fragment_q;
  reg [16:0] ip_sum;
  reg        ip_pair_phase;
  reg  [7:0] ip_pair_hi;
  reg [16:0] l4_sum;
  reg        l4_pair_phase;
  reg  [7:0] l4_pair_hi;
  reg [15:0] l4_wire_cksum_q;

  wire [10:0] eth_hdr_end  = vlan_q ? 11'd18 : 11'd14;
  wire [10:0] ip_hdr_size  = {5'd0, ipv4_ihl_q, 2'b00};
  wire [10:0] l4_start_idx = eth_hdr_end + ip_hdr_size;
  wire [10:0] l4_end_idx   = eth_hdr_end + ipv4_total_len_q[10:0];
  wire        is_udp_q     = is_ipv4_q & (ipv4_proto_q == 8'd17);
  wire        is_tcp_q     = is_ipv4_q & (ipv4_proto_q == 8'd6);
  wire [10:0] ip_off       = (cur_idx >= eth_hdr_end) ? (cur_idx - eth_hdr_end) : 11'd0;
  wire [10:0] l4_off       = (cur_idx >= l4_start_idx) ? (cur_idx - l4_start_idx) : 11'd0;

  always @(posedge mrx_clk_i or negedge mrx_rstn_i) begin
    if (!mrx_rstn_i) begin
      first_type_q <= 16'h0; ethertype_q <= 16'h0; vlan_q <= 1'b0;
      ipv4_ihl_q <= 4'h0; ipv4_total_len_q <= 16'h0; ipv4_proto_q <= 8'h0;
      ipv4_wire_cksum_q <= 16'h0; ipv4_flags_frag_q <= 16'h0; is_fragment_q <= 1'b0;
      is_ipv4_q <= 1'b0;
      ip_sum <= 17'h0; ip_pair_phase <= 1'b0; ip_pair_hi <= 8'h0;
      l4_sum <= 17'h0; l4_pair_phase <= 1'b0; l4_pair_hi <= 8'h0;
      l4_wire_cksum_q <= 16'h0;
    end else if (!mrxdv_i) begin
      vlan_q <= 1'b0; is_ipv4_q <= 1'b0; is_fragment_q <= 1'b0;
      ip_sum <= 17'h0; ip_pair_phase <= 1'b0;
      l4_sum <= 17'h0; l4_pair_phase <= 1'b0;
    end else if (post_sfd_byte) begin
      // ── Ethernet header ──────────────────────────────────────────
      if (cur_idx == 11'd12) first_type_q[15:8] <= byte_data;
      if (cur_idx == 11'd13) begin
        first_type_q[7:0] <= byte_data;
        if ({first_type_q[15:8], byte_data} == 16'h8100)
          vlan_q <= 1'b1;
        else begin
          ethertype_q <= {first_type_q[15:8], byte_data};
          is_ipv4_q   <= ({first_type_q[15:8], byte_data} == 16'h0800);
        end
      end
      if (vlan_q && cur_idx == 11'd16) ethertype_q[15:8] <= byte_data;
      if (vlan_q && cur_idx == 11'd17) begin
        ethertype_q[7:0] <= byte_data;
        is_ipv4_q <= ({ethertype_q[15:8], byte_data} == 16'h0800);
      end

      // ── IPv4 header parse + IP checksum ──────────────────────────
      if (cur_idx >= eth_hdr_end && is_ipv4_q) begin
        case (ip_off)
          11'd0:  ipv4_ihl_q <= byte_data[3:0];
          11'd2:  ipv4_total_len_q[15:8] <= byte_data;
          11'd3:  ipv4_total_len_q[7:0]  <= byte_data;
          11'd6:  ipv4_flags_frag_q[15:8] <= byte_data;
          11'd7:  begin
            ipv4_flags_frag_q[7:0] <= byte_data;
            is_fragment_q <= ({ipv4_flags_frag_q[15:8], byte_data} & 16'h3FFF) != 16'h0;
          end
          11'd9:  ipv4_proto_q <= byte_data;
          11'd10: ipv4_wire_cksum_q[15:8] <= byte_data;
          11'd11: ipv4_wire_cksum_q[7:0]  <= byte_data;
          default: ;
        endcase
        if (!ip_pair_phase) begin
          ip_pair_hi <= byte_data; ip_pair_phase <= 1'b1;
        end else begin
          ip_pair_phase <= 1'b0;
          if (ip_off == 11'd11) begin /* skip wire cksum */ end
          else if (ip_off < ip_hdr_size)
            ip_sum <= {1'b0, ip_sum[15:0]} + {1'b0, ip_pair_hi, byte_data}
                                           + {16'h0, ip_sum[16]};
        end
      end

      // ── L4 (UDP/TCP) accumulator ─────────────────────────────────
      if ((is_udp_q | is_tcp_q) && !(is_ipv4_q & is_fragment_q)
          && (cur_idx >= l4_start_idx) && (cur_idx < l4_end_idx)) begin
        if (is_udp_q && l4_off == 11'd6) l4_wire_cksum_q[15:8] <= byte_data;
        if (is_udp_q && l4_off == 11'd7) l4_wire_cksum_q[7:0]  <= byte_data;
        if (is_tcp_q && l4_off == 11'd16) l4_wire_cksum_q[15:8] <= byte_data;
        if (is_tcp_q && l4_off == 11'd17) l4_wire_cksum_q[7:0]  <= byte_data;
        if (!l4_pair_phase) begin
          l4_pair_hi <= byte_data; l4_pair_phase <= 1'b1;
        end else begin
          l4_pair_phase <= 1'b0;
          if ((is_udp_q && l4_off == 11'd7) || (is_tcp_q && l4_off == 11'd17))
            begin /* skip wire cksum */ end
          else
            l4_sum <= {1'b0, l4_sum[15:0]} + {1'b0, l4_pair_hi, byte_data}
                                           + {16'h0, l4_sum[16]};
        end
      end
    end
  end

  // ════════════════════════════════════════════════════════════════════
  //  Checksum finalisation (combinational)
  // ════════════════════════════════════════════════════════════════════
  // IP header checksum
  wire [16:0] ip_fold0 = {1'b0, ip_sum[15:0]} + {16'h0, ip_sum[16]};
  wire [15:0] ip_calc  = ~ip_fold0[15:0];
  wire        ip_ok    = is_ipv4_q & (ip_calc == ipv4_wire_cksum_q);

  // L4 pseudo-header (IPv4 only — IPv6 removed for area)
  wire [15:0] ipv4_l4_len = ipv4_total_len_q - {10'h0, ipv4_ihl_q, 2'b00};
  // We need src/dst IP for the pseudo-header. Capture them in the parser
  // (kept as working regs, NOT stored in the snapshot).
  reg [31:0] ipv4_src_ip_q, ipv4_dst_ip_q;
  always @(posedge mrx_clk_i or negedge mrx_rstn_i) begin
    if (!mrx_rstn_i) begin ipv4_src_ip_q <= 32'h0; ipv4_dst_ip_q <= 32'h0; end
    else if (post_sfd_byte && cur_idx >= eth_hdr_end && is_ipv4_q) begin
      case (ip_off)
        11'd12: ipv4_src_ip_q[31:24] <= byte_data;
        11'd13: ipv4_src_ip_q[23:16] <= byte_data;
        11'd14: ipv4_src_ip_q[15:8]  <= byte_data;
        11'd15: ipv4_src_ip_q[7:0]   <= byte_data;
        11'd16: ipv4_dst_ip_q[31:24] <= byte_data;
        11'd17: ipv4_dst_ip_q[23:16] <= byte_data;
        11'd18: ipv4_dst_ip_q[15:8]  <= byte_data;
        11'd19: ipv4_dst_ip_q[7:0]   <= byte_data;
        default: ;
      endcase
    end
  end

  wire [18:0] pseudo_sum =
      {3'b0, ipv4_src_ip_q[31:16]} + {3'b0, ipv4_src_ip_q[15:0]}
    + {3'b0, ipv4_dst_ip_q[31:16]} + {3'b0, ipv4_dst_ip_q[15:0]}
    + {3'b0, 8'h0, ipv4_proto_q}   + {3'b0, ipv4_l4_len};
  wire [16:0] pseudo_fold0 = {1'b0, pseudo_sum[15:0]} + {14'h0, pseudo_sum[18:16]};
  wire [15:0] pseudo_fold  = pseudo_fold0[15:0] + {15'h0, pseudo_fold0[16]};

  wire [15:0] l4_tail_word = l4_pair_phase ? {l4_pair_hi, 8'h0} : 16'h0;
  wire [16:0] l4_payload_fold0 = {1'b0, l4_sum[15:0]} + {16'h0, l4_sum[16]};
  wire [15:0] l4_payload_fold  = l4_payload_fold0[15:0] + {15'h0, l4_payload_fold0[16]};
  wire [17:0] l4_combined = {2'b0, l4_payload_fold} + {2'b0, pseudo_fold} + {2'b0, l4_tail_word};
  wire [16:0] l4_cfold0   = {1'b0, l4_combined[15:0]} + {15'h0, l4_combined[17:16]};
  wire [15:0] l4_cfold    = l4_cfold0[15:0] + {15'h0, l4_cfold0[16]};
  wire [15:0] l4_calc     = ~l4_cfold;

  wire l4_supported   = (is_udp_q | is_tcp_q) & ~(is_ipv4_q & is_fragment_q);
  wire l4_match       = (l4_calc == l4_wire_cksum_q);
  wire l4_udp_zero    = is_udp_q & (l4_wire_cksum_q == 16'h0);
  wire l4_ok          = l4_supported & (l4_match | l4_udp_zero);

  // ════════════════════════════════════════════════════════════════════
  //  EOF + snapshot construction (40 bits)
  // ════════════════════════════════════════════════════════════════════
  reg mrxdv_d;
  always @(posedge mrx_clk_i or negedge mrx_rstn_i)
    if (!mrx_rstn_i) mrxdv_d <= 1'b0;
    else             mrxdv_d <= mrxdv_i;
  wire eof_pulse = mrxdv_d & ~mrxdv_i;

  wire [10:0] byte_idx_at_eof = byte_idx + (byte_valid ? 11'd1 : 11'd0);

  reg [31:0] seqnum_mrx;
  always @(posedge mrx_clk_i or negedge mrx_rstn_i)
    if (!mrx_rstn_i) seqnum_mrx <= 32'h0;
    else if (eof_pulse && sfd_seen && byte_idx_at_eof >= 11'd14 && !frame_mrxerr_q)
      seqnum_mrx <= seqnum_mrx + 32'h1;

  wire [7:0] eof_flags = {
    is_ipv4_q & is_fragment_q,  // [7] IP_FRAG
    l4_ok,                      // [6] L4_OK
    ip_ok,                      // [5] IP_OK
    is_tcp_q,                   // [4] IS_TCP
    is_udp_q,                   // [3] IS_UDP
    1'b0,                       // [2] IS_IPV6 (removed)
    is_ipv4_q,                  // [1] IS_IPV4
    vlan_q                      // [0] VLAN
  };

  reg       snap_push;
  reg [7:0] snap_flags;
  reg [31:0] snap_seqnum;

  always @(posedge mrx_clk_i or negedge mrx_rstn_i) begin
    if (!mrx_rstn_i) begin
      snap_push <= 1'b0; snap_flags <= 8'h0; snap_seqnum <= 32'h0;
    end else begin
      snap_push <= 1'b0;
      if (eof_pulse && en_mrx && sfd_seen
          && byte_idx_at_eof >= 11'd14 && !frame_mrxerr_q) begin
        snap_push   <= 1'b1;
        snap_flags  <= eof_flags;
        snap_seqnum <= seqnum_mrx + 32'h1;
      end
    end
  end

  wire [SNAP_W-1:0] snap_word = {snap_seqnum, snap_flags};

  // ════════════════════════════════════════════════════════════════════
  //  Async FIFO (mrx_clk → pclk) — narrow (40 bits × depth 2)
  // ════════════════════════════════════════════════════════════════════
  reg [SNAP_W-1:0] fifo_mem [0:SNAPSHOT_FIFO_DEPTH-1];

  wire [FIFO_AW:0] rptr_gray_pclk;  // forward declaration

  reg [FIFO_AW:0] wptr_bin_mrx, wptr_gray_mrx;
  reg [FIFO_AW:0] rptr_gray_mrx_s0, rptr_gray_mrx_s1;
  reg [1:0] mode_mrx_s0, mode_mrx_s1;

  always @(posedge mrx_clk_i or negedge mrx_rstn_i) begin
    if (!mrx_rstn_i) begin
      rptr_gray_mrx_s0 <= 0; rptr_gray_mrx_s1 <= 0;
      mode_mrx_s0 <= 0; mode_mrx_s1 <= 0;
    end else begin
      rptr_gray_mrx_s0 <= rptr_gray_pclk;
      rptr_gray_mrx_s1 <= rptr_gray_mrx_s0;
      mode_mrx_s0 <= ctrl_mode; mode_mrx_s1 <= mode_mrx_s0;
    end
  end

  // rptr gray→bin in mrx_clk
  reg [FIFO_AW:0] rptr_bin_mrx;
  integer ig;
  always @(*) begin
    rptr_bin_mrx[FIFO_AW] = rptr_gray_mrx_s1[FIFO_AW];
    for (ig = FIFO_AW-1; ig >= 0; ig = ig-1)
      rptr_bin_mrx[ig] = rptr_bin_mrx[ig+1] ^ rptr_gray_mrx_s1[ig];
  end

  wire [FIFO_AW:0] occ_mrx = wptr_bin_mrx - rptr_bin_mrx;
  wire fifo_full_mrx = (mode_mrx_s1 == MODE_LAST_ONLY)
                      ? (occ_mrx >= {{FIFO_AW{1'b0}}, 1'b1})
                      : (occ_mrx == SNAPSHOT_FIFO_DEPTH[FIFO_AW:0]);

  reg ovf_toggle_mrx;
  wire [FIFO_AW:0] wptr_bin_mrx_nxt = wptr_bin_mrx + {{FIFO_AW{1'b0}}, 1'b1};
  wire [FIFO_AW:0] wptr_gray_mrx_nxt = wptr_bin_mrx_nxt
                                      ^ {1'b0, wptr_bin_mrx_nxt[FIFO_AW:1]};

  always @(posedge mrx_clk_i or negedge mrx_rstn_i) begin
    if (!mrx_rstn_i) begin
      wptr_bin_mrx <= 0; wptr_gray_mrx <= 0; ovf_toggle_mrx <= 1'b0;
    end else if (snap_push) begin
      case (mode_mrx_s1)
        MODE_LAST_ONLY: begin
          fifo_mem[0] <= snap_word;
          if (occ_mrx == 0) begin
            wptr_bin_mrx <= wptr_bin_mrx_nxt; wptr_gray_mrx <= wptr_gray_mrx_nxt;
          end else
            ovf_toggle_mrx <= ~ovf_toggle_mrx;
        end
        MODE_DROP_NEW: begin
          if (!fifo_full_mrx) begin
            fifo_mem[wptr_bin_mrx[FIFO_AW-1:0]] <= snap_word;
            wptr_bin_mrx <= wptr_bin_mrx_nxt; wptr_gray_mrx <= wptr_gray_mrx_nxt;
          end else
            ovf_toggle_mrx <= ~ovf_toggle_mrx;
        end
        MODE_DROP_OLD: begin
          fifo_mem[wptr_bin_mrx[FIFO_AW-1:0]] <= snap_word;
          wptr_bin_mrx <= wptr_bin_mrx_nxt; wptr_gray_mrx <= wptr_gray_mrx_nxt;
          if (fifo_full_mrx) ovf_toggle_mrx <= ~ovf_toggle_mrx;
        end
        default: ;
      endcase
    end
  end

  // ════════════════════════════════════════════════════════════════════
  //  pclk side: read pointer, sync, FIFO head, counters
  // ════════════════════════════════════════════════════════════════════
  reg [FIFO_AW:0] rptr_bin_pclk;
  assign rptr_gray_pclk = rptr_bin_pclk ^ {1'b0, rptr_bin_pclk[FIFO_AW:1]};

  reg [FIFO_AW:0] wptr_gray_pclk_s0, wptr_gray_pclk_s1;
  reg ovf_tog_pclk_s0, ovf_tog_pclk_s1, ovf_tog_pclk_s2;

  always @(posedge pclk or negedge presetn) begin
    if (!presetn) begin
      wptr_gray_pclk_s0 <= 0; wptr_gray_pclk_s1 <= 0;
      ovf_tog_pclk_s0 <= 0; ovf_tog_pclk_s1 <= 0; ovf_tog_pclk_s2 <= 0;
    end else begin
      wptr_gray_pclk_s0 <= wptr_gray_mrx; wptr_gray_pclk_s1 <= wptr_gray_pclk_s0;
      ovf_tog_pclk_s0 <= ovf_toggle_mrx; ovf_tog_pclk_s1 <= ovf_tog_pclk_s0;
      ovf_tog_pclk_s2 <= ovf_tog_pclk_s1;
    end
  end

  reg [FIFO_AW:0] wptr_bin_pclk;
  integer ip;
  always @(*) begin
    wptr_bin_pclk[FIFO_AW] = wptr_gray_pclk_s1[FIFO_AW];
    for (ip = FIFO_AW-1; ip >= 0; ip = ip-1)
      wptr_bin_pclk[ip] = wptr_bin_pclk[ip+1] ^ wptr_gray_pclk_s1[ip];
  end

  wire [FIFO_AW:0] occ_pclk = wptr_bin_pclk - rptr_bin_pclk;
  wire fifo_empty_pclk = (occ_pclk == 0);
  wire fifo_full_pclk  = (occ_pclk == SNAPSHOT_FIFO_DEPTH[FIFO_AW:0]);

  wire [SNAP_W-1:0] head_data = fifo_empty_pclk ? {SNAP_W{1'b0}}
                                                : fifo_mem[rptr_bin_pclk[FIFO_AW-1:0]];
  wire [31:0] head_seqnum = head_data[39:8];
  wire  [7:0] head_flags  = head_data[7:0];

  // Pop: reading LAST_SEQNUM pops the FIFO head.
  wire pop_request = access_r && (off == OFF_LAST_SEQNUM) && !fifo_empty_pclk;

  always @(posedge pclk or negedge presetn) begin
    if (!presetn)        rptr_bin_pclk <= 0;
    else if (clr_fifo_pulse) rptr_bin_pclk <= wptr_bin_pclk;
    else if (pop_request)    rptr_bin_pclk <= rptr_bin_pclk + 1;
  end

  // ── Counters (push-event based in pclk) ─────────────────────────────
  reg [FIFO_AW:0] wptr_bin_pclk_prev;
  wire push_event = (wptr_bin_pclk != wptr_bin_pclk_prev);

  wire [SNAP_W-1:0] pushed_data = fifo_mem[wptr_bin_pclk_prev[FIFO_AW-1:0]];
  wire pushed_is_ipv4 = pushed_data[1];
  wire pushed_ip_ok   = pushed_data[5];
  wire pushed_l4_ok   = pushed_data[6];
  wire pushed_is_udp  = pushed_data[3];
  wire pushed_is_tcp  = pushed_data[4];
  wire pushed_frag    = pushed_data[7];

  reg [31:0] frame_count_q, ip_good_q, ip_bad_q, l4_good_q, l4_bad_q;
  reg        ovf_sticky_q;

  always @(posedge pclk or negedge presetn) begin
    if (!presetn) begin
      wptr_bin_pclk_prev <= 0;
      frame_count_q <= 0; ip_good_q <= 0; ip_bad_q <= 0;
      l4_good_q <= 0; l4_bad_q <= 0; ovf_sticky_q <= 0;
    end else begin
      wptr_bin_pclk_prev <= wptr_bin_pclk;
      if (clr_counters_pulse) begin
        frame_count_q <= 0; ip_good_q <= 0; ip_bad_q <= 0;
        l4_good_q <= 0; l4_bad_q <= 0;
      end else if (push_event) begin
        frame_count_q <= frame_count_q + 1;
        if (pushed_is_ipv4) begin
          if (pushed_ip_ok) ip_good_q <= ip_good_q + 1;
          else              ip_bad_q  <= ip_bad_q  + 1;
        end
        if ((pushed_is_udp | pushed_is_tcp) & ~pushed_frag) begin
          if (pushed_l4_ok) l4_good_q <= l4_good_q + 1;
          else              l4_bad_q  <= l4_bad_q  + 1;
        end
      end
      if (clr_ovf_pulse) ovf_sticky_q <= 1'b0;
      else if (ovf_tog_pclk_s2 ^ ovf_tog_pclk_s1) ovf_sticky_q <= 1'b1;
    end
  end

  // ════════════════════════════════════════════════════════════════════
  //  Read mux + IRQ
  // ════════════════════════════════════════════════════════════════════
  wire [31:0] ctrl_rb = {13'b0, 3'b0, 5'b0, ctrl_irq_en_ovf, ctrl_irq_en_bad,
                         ctrl_irq_en_frame, 5'b0, ctrl_mode, ctrl_en};
  wire [31:0] status_rb = {8'b0, SNAPSHOT_FIFO_DEPTH[7:0], 8'h0,
                           1'b0, ovf_sticky_q, fifo_full_pclk, fifo_empty_pclk,
                           {{(4-FIFO_AW-1){1'b0}}, occ_pclk}};

  wire frame_pending = ~fifo_empty_pclk & ctrl_irq_en_frame;
  wire bad_pending   = (ip_bad_q != 0 || l4_bad_q != 0) & ctrl_irq_en_bad;
  wire ovf_pending   = ovf_sticky_q & ctrl_irq_en_ovf;

  reg [31:0] prdata_q;
  always @(*) begin
    case (off)
      OFF_ID:            prdata_q = ID_VALUE;
      OFF_CTRL:          prdata_q = ctrl_rb;
      OFF_STATUS:        prdata_q = status_rb;
      OFF_FRAME_COUNT:   prdata_q = frame_count_q;
      OFF_IP_GOOD_COUNT: prdata_q = ip_good_q;
      OFF_IP_BAD_COUNT:  prdata_q = ip_bad_q;
      OFF_L4_GOOD_COUNT: prdata_q = l4_good_q;
      OFF_L4_BAD_COUNT:  prdata_q = l4_bad_q;
      OFF_LAST_FLAGS:    prdata_q = {24'h0, head_flags};
      OFF_LAST_SEQNUM:   prdata_q = head_seqnum;
      OFF_IRQ_STATUS:    prdata_q = {29'b0, ovf_pending, bad_pending, frame_pending};
      default:           prdata_q = 32'h0;
    endcase
  end

  assign prdata     = access_r ? prdata_q : 32'h0;
  assign pready     = 1'b1;
  assign pslverr    = 1'b0;
  assign cksum_int_o = frame_pending | bad_pending | ovf_pending;

endmodule
