// Cocotb wrapper for ha1588_servo standalone testing
//
// Provides independent clk (PHC domain) and rtc_clk (HA1588 domain)
// for verifying the CDC handshake and servo behaviour.

`timescale 1ns/1ps

module tb_ha1588_servo #(
    parameter SYS_DATA_W = 32
)(
    // PHC clock domain
    input  logic                    clk,
    input  logic                    rtc_clk,
    input  logic                    resetn,

    // Control
    input  logic                    enable,
    input  logic             [29:0] sync_interval,

    // HA1588 RTC inputs (rtc_clk domain)
    input  logic             [31:0] rtc_time_ptp_ns,
    input  logic             [47:0] rtc_time_ptp_sec,

    // PHC current time (clk domain)
    input  logic             [47:0] phc_seconds,
    input  logic             [29:0] phc_nanoseconds,

    // PHC hw_capture interface (clk domain)
    output logic                    hw_capture,
    input  logic             [47:0] hw_cap_seconds,
    input  logic             [29:0] hw_cap_nanoseconds,
    input  logic [SYS_DATA_W-1:0]   hw_cap_sub_nanoseconds,

    // Servo outputs
    output logic                    hw_set_time,
    output logic             [47:0] hw_set_seconds,
    output logic             [29:0] hw_set_nanoseconds,
    output logic                    hw_adj_valid,
    output logic [SYS_DATA_W-1:0]   hw_adj_ns_incr_frac,

    // Status
    output logic                    locked,
    output logic                    phase_step_active
);

    ha1588_servo #(
        .SYS_DATA_W (SYS_DATA_W)
    ) u_dut (
        .clk                    (clk),
        .resetn                 (resetn),
        .enable                 (enable),
        .sync_interval          (sync_interval),
        .rtc_clk                (rtc_clk),
        .rtc_time_ptp_ns        (rtc_time_ptp_ns),
        .rtc_time_ptp_sec       (rtc_time_ptp_sec),
        .phc_seconds            (phc_seconds),
        .phc_nanoseconds        (phc_nanoseconds),
        .hw_capture             (hw_capture),
        .hw_cap_seconds         (hw_cap_seconds),
        .hw_cap_nanoseconds     (hw_cap_nanoseconds),
        .hw_cap_sub_nanoseconds (hw_cap_sub_nanoseconds),
        .hw_set_time            (hw_set_time),
        .hw_set_seconds         (hw_set_seconds),
        .hw_set_nanoseconds     (hw_set_nanoseconds),
        .hw_adj_valid           (hw_adj_valid),
        .hw_adj_ns_incr_frac    (hw_adj_ns_incr_frac),
        .locked                 (locked),
        .phase_step_active      (phase_step_active)
    );

    initial begin
        $dumpfile("waves.vcd");
        $dumpvars(0, tb_ha1588_servo);
    end

endmodule
