# VC Formal X-propagation script for ahb3lite_to_wb
# Verifies that no X-state can propagate to Wishbone outputs
# from valid reset through normal AHB operation.

# ── Analyze design ──────────────────────────────────────────────────────────
set ETHMAC_AHB_HOME [file normalize [file dirname [info script]]/../..]

analyze -format verilog \
    ${ETHMAC_AHB_HOME}/src/rtl/ahb3lite_wb_bridge/ahb3lite_to_wb.v

# ── Elaborate ───────────────────────────────────────────────────────────────
elaborate -top ahb3lite_to_wb

# ── Clock and reset ─────────────────────────────────────────────────────────
clock clk_i
reset -expression {!rst_n_i}

# ── X-propagation checks ───────────────────────────────────────────────────
set_xprop_check -effort high

# Assume AHB slave-side inputs are well-formed
assume -name ahb_htrans_valid  {sHTRANS inside {2'b00, 2'b10}}
assume -name ahb_hsel_valid    {sHSEL   !== 1'bx}
assume -name ahb_hwrite_valid  {sHWRITE !== 1'bx}

# ── Run ─────────────────────────────────────────────────────────────────────
check_xprop -type {hold reset_value} -time_limit 300

# ── Report ──────────────────────────────────────────────────────────────────
report_xprop -verbose -file xprop_results.rpt
report_xprop -summary -file xprop_summary.rpt

exit
