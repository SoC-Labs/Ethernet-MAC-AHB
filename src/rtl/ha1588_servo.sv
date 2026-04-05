//-----------------------------------------------------------------------------
// SoCLabs HA1588 Hardware Servo
// - Periodically compares the HA1588 software-corrected RTC time to the PHC
//   timestamp and applies phase-step or frequency corrections to discipline
//   the PHC to match the HA1588 RTC.
// - Configurable sync interval (like TideLink HW_SYNC_INTERVAL).
// - PI controller for smooth frequency tracking.
// - Toggle-based CDC for safe cross-domain handshake (rtc_clk -> clk).
//
// A joint work commissioned on behalf of SoC Labs, under Arm Academic Access license.
//
// Contributors
//
// David Mapstone (d.a.mapstone@soton.ac.uk)
//
// Copyright 2026, SoC Labs (www.soclabs.org)
//-----------------------------------------------------------------------------

module ha1588_servo #(
    parameter SYS_DATA_W = 32,
    parameter [29:0] DEFAULT_PHASE_STEP_THRESHOLD = 30'd1_000  // 1 us
)(
    // --------------------------------------------------------------------------
    // PHC Clock Domain
    // --------------------------------------------------------------------------
    input  logic                    clk,
    input  logic                    resetn,

    // Control (from APB registers)
    input  logic                    enable,
    input  logic             [29:0] sync_interval,     // Nanoseconds between syncs

    // --------------------------------------------------------------------------
    // HA1588 RTC Inputs (rtc_clk domain)
    // --------------------------------------------------------------------------
    input  logic                    rtc_clk,
    input  logic             [31:0] rtc_time_ptp_ns,   // {2'b0, 30-bit ns}
    input  logic             [47:0] rtc_time_ptp_sec,

    // --------------------------------------------------------------------------
    // PHC Current Time (for interval timer, clk domain)
    // --------------------------------------------------------------------------
    input  logic             [47:0] phc_seconds,
    input  logic             [29:0] phc_nanoseconds,

    // --------------------------------------------------------------------------
    // PHC Hardware Capture Interface (clk domain)
    // --------------------------------------------------------------------------
    output logic                    hw_capture,         // Pulse: trigger PHC snapshot
    input  logic             [47:0] hw_cap_seconds,
    input  logic             [29:0] hw_cap_nanoseconds,
    input  logic [SYS_DATA_W-1:0]   hw_cap_sub_nanoseconds,

    // --------------------------------------------------------------------------
    // PHC Servo Outputs (to clock core via mux, clk domain)
    // --------------------------------------------------------------------------
    output logic                    hw_set_time,
    output logic             [47:0] hw_set_seconds,
    output logic             [29:0] hw_set_nanoseconds,
    output logic                    hw_adj_valid,
    output logic [SYS_DATA_W-1:0]   hw_adj_ns_incr_frac,

    // --------------------------------------------------------------------------
    // Status Outputs (clk domain)
    // --------------------------------------------------------------------------
    output logic                    locked,
    output logic                    phase_step_active
);

    // =========================================================================
    // Constants
    // =========================================================================
    localparam logic [29:0] NS_PER_SECOND = 30'd999_999_999;

    // =========================================================================
    // CDC: Toggle-based handshake (clk -> rtc_clk -> clk)
    // =========================================================================
    // Request side (clk domain -> rtc_clk domain)
    logic capture_req_toggle;       // Toggle in clk domain
    logic [2:0] req_sync_rtc;       // 3-stage sync in rtc_clk domain
    logic req_edge_rtc;             // Edge detect in rtc_clk domain

    // Acknowledge side (rtc_clk domain -> clk domain)
    logic capture_ack_toggle;       // Toggle in rtc_clk domain
    logic [2:0] ack_sync_clk;      // 3-stage sync in clk domain
    logic ack_edge_clk;            // Edge detect in clk domain

    // Snapshot registers (rtc_clk domain, stable after latch)
    logic [47:0] ha_snap_sec;
    logic [29:0] ha_snap_ns;

    // -- Request toggle (clk domain) --
    logic capture_req_pulse;        // FSM drives this for 1 cycle

    always_ff @(posedge clk or negedge resetn) begin
        if (!resetn)
            capture_req_toggle <= 1'b0;
        else if (capture_req_pulse)
            capture_req_toggle <= ~capture_req_toggle;
    end

    // -- Request sync into rtc_clk domain --
    always_ff @(posedge rtc_clk or negedge resetn) begin
        if (!resetn)
            req_sync_rtc <= 3'b0;
        else
            req_sync_rtc <= {req_sync_rtc[1:0], capture_req_toggle};
    end

    assign req_edge_rtc = req_sync_rtc[2] ^ req_sync_rtc[1];

    // -- Snapshot ha1588 time and ack (rtc_clk domain) --
    always_ff @(posedge rtc_clk or negedge resetn) begin
        if (!resetn) begin
            ha_snap_sec        <= 48'b0;
            ha_snap_ns         <= 30'b0;
            capture_ack_toggle <= 1'b0;
        end else if (req_edge_rtc) begin
            ha_snap_sec        <= rtc_time_ptp_sec;
            ha_snap_ns         <= rtc_time_ptp_ns[29:0];
            capture_ack_toggle <= ~capture_ack_toggle;
        end
    end

    // -- Ack sync into clk domain --
    always_ff @(posedge clk or negedge resetn) begin
        if (!resetn)
            ack_sync_clk <= 3'b0;
        else
            ack_sync_clk <= {ack_sync_clk[1:0], capture_ack_toggle};
    end

    assign ack_edge_clk = ack_sync_clk[2] ^ ack_sync_clk[1];

    // =========================================================================
    // Periodic Sync Timer
    // =========================================================================
    // Tracks a target (seconds, nanoseconds) and fires when PHC time reaches it.
    // On fire, advances target by sync_interval with nanosecond rollover.

    logic [47:0] target_seconds;
    logic [29:0] target_nanoseconds;
    logic        timer_armed;
    logic        sync_fire;

    assign sync_fire = enable && timer_armed &&
                       (phc_seconds > target_seconds ||
                        (phc_seconds == target_seconds &&
                         phc_nanoseconds >= target_nanoseconds));

    // Timer target management
    always_ff @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            target_seconds     <= 48'b0;
            target_nanoseconds <= 30'b0;
            timer_armed        <= 1'b0;
        end else if (!enable) begin
            // When disabled, arm timer to fire on first enable
            target_seconds     <= phc_seconds;
            target_nanoseconds <= phc_nanoseconds;
            timer_armed        <= 1'b0;
        end else if (!timer_armed) begin
            // Just enabled: set first target one interval from now
            if ({2'b0, phc_nanoseconds} + {2'b0, sync_interval} > {2'b0, NS_PER_SECOND}) begin
                target_nanoseconds <= phc_nanoseconds + sync_interval - NS_PER_SECOND - 30'd1;
                target_seconds     <= phc_seconds + 48'd1;
            end else begin
                target_nanoseconds <= phc_nanoseconds + sync_interval;
                target_seconds     <= phc_seconds;
            end
            timer_armed <= 1'b1;
        end else if (sync_fire) begin
            // Advance target by sync_interval
            if ({2'b0, target_nanoseconds} + {2'b0, sync_interval} > {2'b0, NS_PER_SECOND}) begin
                target_nanoseconds <= target_nanoseconds + sync_interval - NS_PER_SECOND - 30'd1;
                target_seconds     <= target_seconds + 48'd1;
            end else begin
                target_nanoseconds <= target_nanoseconds + sync_interval;
                target_seconds     <= target_seconds;
            end
        end
    end

    // =========================================================================
    // FSM
    // =========================================================================
    typedef enum logic [2:0] {
        S_IDLE,
        S_CDC_WAIT,
        S_CAPTURE,
        S_COMPUTE,
        S_ADJUST
    } state_t;

    state_t state, state_next;

    // Latched values from capture
    logic [47:0] latched_ha_sec;
    logic [29:0] latched_ha_ns;
    logic [47:0] latched_phc_sec;
    logic [29:0] latched_phc_ns;

    // Offset computation
    logic signed [48:0] offset_sec;     // Signed seconds difference
    logic signed [30:0] offset_ns;      // Signed nanoseconds difference
    logic               offset_large;   // Phase step needed

    // PI controller state
    logic signed [SYS_DATA_W-1:0] ns_incr_frac_accum;  // Running fractional increment
    logic signed [SYS_DATA_W-1:0] integral;             // Integral accumulator

    // Lock detection
    logic [2:0] lock_counter;

    // ── FSM state register ──────────────────────────────────────────────────
    always_ff @(posedge clk or negedge resetn) begin
        if (!resetn)
            state <= S_IDLE;
        else
            state <= state_next;
    end

    // ── FSM next state ──────────────────────────────────────────────────────
    always_comb begin
        state_next = state;
        case (state)
            S_IDLE:     if (sync_fire)    state_next = S_CDC_WAIT;
            S_CDC_WAIT: if (ack_edge_clk) state_next = S_CAPTURE;
            S_CAPTURE:                    state_next = S_COMPUTE;
            S_COMPUTE:                    state_next = S_ADJUST;
            S_ADJUST:                     state_next = S_IDLE;
            default:                      state_next = S_IDLE;
        endcase
    end

    // ── FSM output and datapath ─────────────────────────────────────────────

    // Offset computation wires
    logic signed [30:0] raw_ns_diff;
    logic               ns_borrow;

    assign raw_ns_diff = {1'b0, latched_ha_ns} - {1'b0, latched_phc_ns};
    assign ns_borrow   = raw_ns_diff[30]; // Negative if PHC ns > HA ns

    // PI correction wires
    logic signed [SYS_DATA_W-1:0] proportional;
    logic signed [SYS_DATA_W-1:0] integral_update;
    logic signed [SYS_DATA_W-1:0] correction;

    // Sign-extend offset_ns to SYS_DATA_W for PI arithmetic
    logic signed [SYS_DATA_W-1:0] offset_ns_ext;
    assign offset_ns_ext = {{(SYS_DATA_W-31){offset_ns[30]}}, offset_ns};

    // KP ~= 1/2 (arithmetic right shift 1), KI ~= 1/4 (arithmetic right shift 2)
    assign proportional    = offset_ns_ext >>> 1;
    assign integral_update = offset_ns_ext >>> 2;
    assign correction      = proportional + integral;

    always_ff @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            capture_req_pulse   <= 1'b0;
            hw_capture          <= 1'b0;
            hw_set_time         <= 1'b0;
            hw_set_seconds      <= 48'b0;
            hw_set_nanoseconds  <= 30'b0;
            hw_adj_valid        <= 1'b0;
            hw_adj_ns_incr_frac <= {SYS_DATA_W{1'b0}};
            latched_ha_sec      <= 48'b0;
            latched_ha_ns       <= 30'b0;
            latched_phc_sec     <= 48'b0;
            latched_phc_ns      <= 30'b0;
            offset_sec          <= '0;
            offset_ns           <= '0;
            offset_large        <= 1'b0;
            ns_incr_frac_accum  <= '0;
            integral            <= '0;
            lock_counter        <= 3'b0;
            locked              <= 1'b0;
            phase_step_active   <= 1'b0;
        end else begin
            // Default: deassert single-cycle pulses
            capture_req_pulse <= 1'b0;
            hw_capture        <= 1'b0;
            hw_set_time       <= 1'b0;
            hw_adj_valid      <= 1'b0;

            case (state)
                S_IDLE: begin
                    if (sync_fire) begin
                        // Start CDC handshake and PHC capture simultaneously
                        capture_req_pulse <= 1'b1;
                        hw_capture        <= 1'b1;
                    end
                end

                S_CDC_WAIT: begin
                    // Wait for ack_edge_clk (handled by state transition)
                end

                S_CAPTURE: begin
                    // Latch both snapshots
                    latched_ha_sec  <= ha_snap_sec;
                    latched_ha_ns   <= ha_snap_ns;
                    latched_phc_sec <= hw_cap_seconds;
                    latched_phc_ns  <= hw_cap_nanoseconds;
                end

                S_COMPUTE: begin
                    // Compute signed offset with borrow handling
                    if (ns_borrow) begin
                        // HA ns < PHC ns: borrow 1 second
                        offset_ns  <= {1'b0, latched_ha_ns} - {1'b0, latched_phc_ns}
                                      + {1'b0, NS_PER_SECOND} + 31'sd1;
                        offset_sec <= {1'b0, latched_ha_sec} - {1'b0, latched_phc_sec} - 49'sd1;
                    end else begin
                        offset_ns  <= {1'b0, latched_ha_ns} - {1'b0, latched_phc_ns};
                        offset_sec <= {1'b0, latched_ha_sec} - {1'b0, latched_phc_sec};
                    end

                    // Determine if offset is large enough for phase step
                    // (will be evaluated in S_ADJUST based on computed values)
                end

                S_ADJUST: begin
                    // Check if phase step is needed
                    offset_large = (offset_sec != '0) ||
                                   (offset_ns[30] ? (-offset_ns > {1'b0, DEFAULT_PHASE_STEP_THRESHOLD})
                                                  : ( offset_ns > {1'b0, DEFAULT_PHASE_STEP_THRESHOLD}));

                    if (offset_large) begin
                        // Phase step: load ha1588 time into PHC
                        hw_set_time        <= 1'b1;
                        hw_set_seconds     <= latched_ha_sec;
                        hw_set_nanoseconds <= latched_ha_ns;
                        phase_step_active  <= 1'b1;

                        // Reset PI state
                        ns_incr_frac_accum <= '0;
                        integral           <= '0;
                        lock_counter       <= 3'b0;
                        locked             <= 1'b0;
                    end else begin
                        // Frequency correction via PI controller
                        integral           <= integral + integral_update;
                        ns_incr_frac_accum <= ns_incr_frac_accum - correction;

                        hw_adj_valid        <= 1'b1;
                        hw_adj_ns_incr_frac <= ns_incr_frac_accum - correction;
                        phase_step_active   <= 1'b0;

                        // Lock detection
                        if (lock_counter < 3'd4)
                            lock_counter <= lock_counter + 3'd1;

                        if (lock_counter >= 3'd3)
                            locked <= 1'b1;
                    end
                end

                default: ;
            endcase

            // Force outputs off when disabled
            if (!enable) begin
                hw_set_time  <= 1'b0;
                hw_adj_valid <= 1'b0;
                hw_capture   <= 1'b0;
                locked       <= 1'b0;
            end
        end
    end

endmodule
