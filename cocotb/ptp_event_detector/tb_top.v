// Cocotb wrapper for ptp_event_detector standalone testing
module tb_top (
    input  wire       clk,
    input  wire       resetn,
    input  wire       mii_dv,
    input  wire [3:0] mii_data,
    output wire       ptp_event
);

    ptp_event_detector u_dut (
        .clk       (clk),
        .resetn    (resetn),
        .mii_dv    (mii_dv),
        .mii_data  (mii_data),
        .ptp_event (ptp_event)
    );

    initial begin
        $dumpfile("waves.vcd");
        $dumpvars(0, tb_top);
    end

endmodule
