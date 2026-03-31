///////////////////////////////////////////////////////////////////////////////
// AHB3-Lite to Wishbone Bridge
///////////////////////////////////////////////////////////////////////////////
//
// Original author: Vitor Finotti (Copyright (c) 2019)
// Original source: https://github.com/vfinotti/ahb3lite_wb_bridge
//
// Description:
//   Bridge for conversion from an AHB3-Lite slave interface to a Wishbone B3
//   master interface. Inspired by the code at:
//   https://www.valpont.com/ahb-to-wishbone-and-wishbone-to-ahb-bridges-in-verilog/pst/
//
// Modifications (SoCLabs):
//   - Added AHB-compliant two-cycle error response handling. When the
//     Wishbone slave asserts err, the bridge now produces:
//       Cycle 1: HRESP=1, HREADYOUT=0
//       Cycle 2: HRESP=1, HREADYOUT=1
//     and terminates the Wishbone bus cycle. The original code held
//     HREADYOUT low indefinitely on a Wishbone error, violating the
//     AHB protocol and stalling the bus.
//   - Added read-data latching so HRDATA remains stable after a Wishbone
//     acknowledge is deasserted.
//   - Fixed AHB pipeline address integrity: the bridge now latches the
//     incoming AHB address phase into a pending register and only drives
//     it onto the WB bus when the previous WB transaction completes.
//     Previously, back-to-back AHB transfers would overwrite the WB
//     address mid-transaction, causing reads/writes to go to the wrong
//     address.
//
///////////////////////////////////////////////////////////////////////////////
// MIT License
///////////////////////////////////////////////////////////////////////////////
// Permission is hereby granted, free of charge, to any person obtaining a copy of
// this software and associated documentation files (the "Software"), to deal in
// the Software without restriction, including without limitation the rights to
// use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies
// of the Software, and to permit persons to whom the Software is furnished to do
// so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.
///////////////////////////////////////////////////////////////////////////////

module ahb3lite_to_wb (
  clk_i,
  rst_n_i,

  // ahb3lite
  sHADDR,
  sHWDATA,
  sHWRITE,
  sHREADYOUT,
  sHSIZE,
  sHBURST,
  sHSEL,
  sHTRANS,
  sHRDATA,
  sHRESP,
  sHREADY,
  sHPROT,

  // to wishbone
  to_wb_dat_i,
  to_wb_adr_i,
  to_wb_sel_i,
  to_wb_we_i,
  to_wb_cyc_i,
  to_wb_stb_i,
  from_wb_dat_o,
  from_wb_ack_o,
  from_wb_err_o
  );

input           clk_i;
input	        rst_n_i;
input   [31:0]  sHADDR;
input   [31:0]  sHWDATA;
input           sHWRITE;
input   [ 2:0]  sHSIZE;
input   [ 2:0]  sHBURST;
input           sHSEL;
input   [ 1:0]  sHTRANS;
input           sHREADY;
input   [ 3:0]  sHPROT;

output          sHREADYOUT;
output  [31:0]  sHRDATA;
output          sHRESP;

output  [31:0]  to_wb_dat_i;
output  [31:0]  to_wb_adr_i;
output  [ 3:0]  to_wb_sel_i;
output          to_wb_we_i;
output          to_wb_cyc_i;
output          to_wb_stb_i;
input   [31:0]  from_wb_dat_o;
input           from_wb_ack_o;
input           from_wb_err_o;

/////////////////////////////////////////////////////
// WB bus registers
reg [31:0]  wb_adr_r;
reg         wb_we_r;
reg         wb_cyc_r;
reg         wb_stb_r;
reg [ 3:0]  wb_sel_r;

// AHB address-phase latch: holds the next transfer while the current
// WB transaction is in progress.  This is the key to correct AHB
// pipelining — the WB address must not change until the slave ACKs.
reg [31:0]  pend_addr;
reg         pend_write;
reg         pend_valid;    // A new AHB transfer is waiting to start

// Latch read data on WB ack so it remains stable for the AHB data phase
reg [31:0]  rdata_latch;

// AHB error response
reg         isHRESP;
reg         err_resp_pending;

/////////////////////////////////////////////////////
// WB outputs
assign to_wb_adr_i   = wb_adr_r;
assign to_wb_we_i    = wb_we_r;
assign to_wb_dat_i   = sHWDATA;
assign to_wb_sel_i   = wb_sel_r;
assign to_wb_cyc_i   = wb_cyc_r;
assign to_wb_stb_i   = wb_stb_r;

// Forward live WB data when ack is active; use latched data otherwise
assign sHRDATA       = (from_wb_ack_o) ? from_wb_dat_o : rdata_latch;

// AHB two-cycle error response:
//   Cycle 1 (from_wb_err_o): HREADYOUT=0, HRESP=1
//   Cycle 2 (err_resp_pending): HREADYOUT=1, HRESP=1
// HREADYOUT must be low while:
//   - WB transaction pending ACK (wb_stb_r && !from_wb_ack_o)
//   - WB error first cycle
//   - Pending transfer waiting to launch (pend_valid && !wb_completing)
// HREADYOUT is high when:
//   - WB ACK arrives (from_wb_ack_o)
//   - Error response second cycle (err_resp_pending)
//   - Bus is idle with nothing pending
assign sHREADYOUT    = (from_wb_err_o && wb_stb_r)  ? 1'b0 :
                       (err_resp_pending)            ? 1'b1 :
                       (wb_stb_r && !from_wb_ack_o)  ? 1'b0 :
                       (wb_stb_r && from_wb_ack_o)   ? 1'b1 :
                       (pend_valid)                   ? 1'b0 : 1'b1;

assign sHRESP        = (from_wb_err_o && wb_stb_r) ? 1'b1 :
                       (err_resp_pending)           ? 1'b1 : isHRESP;

/////////////////////////////////////////////////////
// Detect a valid AHB address phase
wire ahb_addr_valid = sHSEL && sHREADY &&
                      (sHSIZE == 3'b010) &&
                      (sHTRANS == 2'b10 || sHTRANS == 2'b11);

// Detect IDLE/invalid address phase (used to clear pending state)
wire ahb_addr_idle  = !sHSEL ||
                      (sHSEL && sHREADY && (sHTRANS == 2'b00));

// Detect unsupported transfer size (for error response)
wire ahb_size_err   = sHSEL && sHREADY && (sHSIZE != 3'b010) &&
                      (sHTRANS != 2'b00);

// WB transaction completing this cycle
wire wb_completing  = wb_stb_r && from_wb_ack_o;
wire wb_error       = wb_stb_r && from_wb_err_o;

/////////////////////////////////////////////////////
always @(posedge clk_i or negedge rst_n_i)
begin
  if (!rst_n_i)
    begin
      wb_adr_r         <= 32'b0;
      wb_we_r          <= 1'b0;
      wb_cyc_r         <= 1'b0;
      wb_stb_r         <= 1'b0;
      wb_sel_r         <= 4'b0;
      pend_addr        <= 32'b0;
      pend_write       <= 1'b0;
      pend_valid       <= 1'b0;
      rdata_latch      <= 32'b0;
      isHRESP          <= 1'b0;
      err_resp_pending <= 1'b0;
    end
  else if (wb_error)
    begin
      // WB error: terminate cycle, start AHB two-cycle error response
      err_resp_pending <= 1'b1;
      wb_cyc_r         <= 1'b0;
      wb_stb_r         <= 1'b0;
      wb_we_r          <= 1'b0;
      wb_adr_r         <= 32'b0;
      wb_sel_r         <= 4'b0;
      isHRESP          <= 1'b0;
      // Clear any pending transfer (it was in the error cycle's addr phase)
      pend_valid       <= 1'b0;
    end
  else
    begin
      err_resp_pending <= 1'b0;

      // Latch read data when WB ACKs
      if (from_wb_ack_o)
        rdata_latch <= from_wb_dat_o;

      // ----------------------------------------------------------
      // AHB address phase capture: latch new transfer requests
      // ----------------------------------------------------------
      if (ahb_addr_valid)
        begin
          pend_addr  <= sHADDR;
          pend_write <= sHWRITE;
          pend_valid <= 1'b1;
          isHRESP    <= 1'b0;
        end
      else if (ahb_size_err)
        begin
          isHRESP    <= 1'b1;
          pend_valid <= 1'b0;
        end
      else if (ahb_addr_idle)
        begin
          // IDLE or deselected — no new transfer pending
          // Only clear if we're not holding a transfer that hasn't
          // been launched yet
          if (!pend_valid || wb_completing)
            begin
              pend_valid <= 1'b0;
              isHRESP    <= 1'b0;
            end
        end

      // ----------------------------------------------------------
      // WB transaction launch / completion
      // ----------------------------------------------------------
      if (wb_completing)
        begin
          // Current WB transaction done.  Launch pending if available.
          if (pend_valid)
            begin
              wb_adr_r   <= pend_addr;
              wb_we_r    <= pend_write;
              wb_cyc_r   <= 1'b1;
              wb_stb_r   <= 1'b1;
              wb_sel_r   <= 4'b1111;
              pend_valid <= 1'b0;
            end
          else
            begin
              // Nothing pending — go idle
              wb_cyc_r <= 1'b0;
              wb_stb_r <= 1'b0;
              wb_we_r  <= 1'b0;
              wb_adr_r <= 32'b0;
              wb_sel_r <= 4'b0;
            end
        end
      else if (!wb_stb_r && pend_valid)
        begin
          // WB bus is idle and we have a pending transfer — launch it
          wb_adr_r   <= pend_addr;
          wb_we_r    <= pend_write;
          wb_cyc_r   <= 1'b1;
          wb_stb_r   <= 1'b1;
          wb_sel_r   <= 4'b1111;
          pend_valid <= 1'b0;
        end
      else if (!wb_stb_r && !pend_valid)
        begin
          // Idle: ensure WB signals are clean
          wb_cyc_r <= 1'b0;
          wb_stb_r <= 1'b0;
          wb_we_r  <= 1'b0;
        end
      // else: WB transaction in progress, not yet ACK'd — hold stable
    end
end

endmodule
