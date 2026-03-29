# VC Formal X-propagation script for wb_to_ahb3lite
# Verifies that no X-state can propagate to AHB master outputs
# from valid reset through normal Wishbone operation.

# ── Analyze design ──────────────────────────────────────────────────────────
set ETHMAC_AHB_HOME [file normalize [file dirname [info script]]/../..]

analyze -format verilog \
    ${ETHMAC_AHB_HOME}/src/rtl/wb_to_ahb3lite.v

# ── Elaborate ───────────────────────────────────────────────────────────────
elaborate -top wb_to_ahb3lite

# ── Clock and reset ─────────────────────────────────────────────────────────
clock clk_i
reset -expression {!rst_n_i}

# ── X-propagation checks ───────────────────────────────────────────────────
set_xprop_check -effort high

# Assume Wishbone master-side inputs are well-formed
assume -name wb_cyc_valid {from_m_wb_cyc_o !== 1'bx}
assume -name wb_stb_valid {from_m_wb_stb_o !== 1'bx}
assume -name wb_we_valid  {from_m_wb_we_o  !== 1'bx}

# Assume AHB slave responses are valid
assume -name ahb_hready_valid {mHREADY !== 1'bx}
assume -name ahb_hresp_valid  {mHRESP  !== 1'bx}

# ── Run ─────────────────────────────────────────────────────────────────────
check_xprop -type {hold reset_value} -time_limit 300

# ── Report ──────────────────────────────────────────────────────────────────
report_xprop -verbose -file xprop_results.rpt
report_xprop -summary -file xprop_summary.rpt

exit
