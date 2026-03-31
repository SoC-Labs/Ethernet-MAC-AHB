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
reg         NextsHRESP;
reg         isHRESP;

reg         Nextto_wb_cyc_i;
reg         ito_wb_cyc_i;

reg         Nextto_wb_stb_i;
reg         ito_wb_stb_i;

reg [ 3:0]  Nextto_wb_sel_i;
reg [ 3:0]  ito_wb_sel_i;

reg [31:0]  Nextto_wb_adr_i;
reg [31:0]  ito_wb_adr_i;

reg         Nextto_wb_we_i;
reg         ito_wb_we_i;

// Latch read data on WB ack so it remains stable for the AHB data phase
reg [31:0]  rdata_latch;

// AHB two-cycle error response state
reg         err_resp_pending;  // High during second cycle of error response
/////////////////////////////////////////////////////
assign to_wb_adr_i   = ito_wb_adr_i;
assign to_wb_we_i    = ito_wb_we_i;
assign to_wb_dat_i   = sHWDATA;
assign to_wb_sel_i   = ito_wb_sel_i;
// Forward live WB data when ack is active; use latched data otherwise
assign sHRDATA       = (from_wb_ack_o) ? from_wb_dat_o : rdata_latch;
// AHB two-cycle error response:
//   Cycle 1 (from_wb_err_o): HREADYOUT=0, HRESP=1
//   Cycle 2 (err_resp_pending): HREADYOUT=1, HRESP=1
assign sHREADYOUT    = (from_wb_err_o && ito_wb_stb_i) ? 1'b0 :
                       (err_resp_pending)               ? 1'b1 :
                       (to_wb_stb_i)                    ? from_wb_ack_o : 1'b1;
assign sHRESP        = (from_wb_err_o && ito_wb_stb_i) ? 1'b1 :
                       (err_resp_pending)               ? 1'b1 : isHRESP;
assign to_wb_cyc_i   = ito_wb_cyc_i;
assign to_wb_stb_i   = ito_wb_stb_i;

always @(*)
begin
  NextsHRESP      = isHRESP;
  Nextto_wb_cyc_i = ito_wb_cyc_i;
  Nextto_wb_stb_i = ito_wb_stb_i;
  Nextto_wb_adr_i = ito_wb_adr_i;
  Nextto_wb_we_i  = ito_wb_we_i;
  Nextto_wb_sel_i = ito_wb_sel_i;

  if(sHSEL)
    begin
      if(sHREADY)
        begin
          if(sHSIZE != 3'b010)
            begin
              Nextto_wb_we_i  = 1'b0;
              Nextto_wb_cyc_i = 1'b0;
              Nextto_wb_stb_i = 1'b0;
              Nextto_wb_adr_i = 32'b0;
              Nextto_wb_sel_i = 4'b0;
              if(sHTRANS == 2'b00)
                NextsHRESP    = 1'b0;
              else
                NextsHRESP    = 1'b1;
            end
          else
            begin
              case(sHTRANS)
                2'b00:
                  begin
                    NextsHRESP      = 1'b0;
                    Nextto_wb_cyc_i = 1'b0;
                    Nextto_wb_stb_i = 1'b0;
                    Nextto_wb_adr_i = 32'b0;
                    Nextto_wb_sel_i = 4'b0;
                  end
                2'b01:
                  begin
                    Nextto_wb_cyc_i = 1'b1;
                    Nextto_wb_stb_i = 1'b0;
                  end
                2'b10,2'b11:
                  begin
                    NextsHRESP      = 1'b0;
                    Nextto_wb_cyc_i = 1'b1;
                    Nextto_wb_stb_i = 1'b1;
                    Nextto_wb_adr_i = sHADDR;
                    Nextto_wb_we_i  = sHWRITE;
                    Nextto_wb_sel_i = 4'b1111;
                  end
              endcase
            end
        end
      else
        begin

        end
    end
  else
    begin
      // HSEL deasserted — this may be a new address phase targeting a
      // different slave while the current data phase is still in progress.
      // Keep the Wishbone cycle alive until the slave acknowledges;
      // only clear state when the WB side is idle or has just acked.
      if (ito_wb_stb_i && !from_wb_ack_o)
        begin
          // Active WB transaction still in progress — hold signals stable
        end
      else
        begin
          NextsHRESP      = 1'b0;
          Nextto_wb_we_i  = 1'b0;
          Nextto_wb_cyc_i = 1'b0;
          Nextto_wb_stb_i = 1'b0;
          Nextto_wb_adr_i = 32'b0;
          Nextto_wb_sel_i = 4'b0;
        end
    end

end

always @(posedge clk_i or negedge rst_n_i)
begin
  if(!rst_n_i)
    begin
      isHRESP          <= 1'b0;
      ito_wb_cyc_i     <= 1'b0;
      ito_wb_stb_i     <= 1'b0;
      ito_wb_adr_i     <= 32'b0;
      ito_wb_we_i      <= 1'b0;
      ito_wb_sel_i     <= 4'b0;
      rdata_latch      <= 32'b0;
      err_resp_pending <= 1'b0;
    end
  else if(from_wb_err_o && ito_wb_stb_i)
    begin
      // WB error received: terminate WB cycle, start AHB two-cycle error response
      err_resp_pending <= 1'b1;
      ito_wb_cyc_i     <= 1'b0;
      ito_wb_stb_i     <= 1'b0;
      ito_wb_we_i      <= 1'b0;
      ito_wb_adr_i     <= 32'b0;
      ito_wb_sel_i     <= 4'b0;
    end
  else
    begin
      err_resp_pending <= 1'b0;
      isHRESP      <= NextsHRESP;
      ito_wb_cyc_i <= Nextto_wb_cyc_i;
      ito_wb_stb_i <= Nextto_wb_stb_i;
      ito_wb_adr_i <= Nextto_wb_adr_i;
      ito_wb_we_i  <= Nextto_wb_we_i;
      ito_wb_sel_i <= Nextto_wb_sel_i;
      if(from_wb_ack_o)
        rdata_latch <= from_wb_dat_o;
    end
end

endmodule
