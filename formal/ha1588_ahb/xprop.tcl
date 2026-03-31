# VC Formal X-propagation script for ha1588_ahb (top-level)
# Verifies that no X-state can propagate to any external output
# (AHB slave, RTC time, one-PPS) from valid reset through normal operation.
#
# Full hierarchy including all submodules and OpenCores HA1588 IP.

# ── Analyze design ──────────────────────────────────────────────────────────
set ETHMAC_AHB_HOME [file normalize [file dirname [info script]]/../..]
set HA1588_IP_DIR   $::env(HA1588_IP_DIR)

analyze -format verilog \
    ${HA1588_IP_DIR}/rtl/rtc/rtc.v \
    ${HA1588_IP_DIR}/rtl/tsu/ptp_parser.v \
    ${ETHMAC_AHB_HOME}/src/rtl/ha1588_patches/ptp_queue.v \
    ${HA1588_IP_DIR}/rtl/tsu/tsu.v \
    ${HA1588_IP_DIR}/rtl/reg/reg.v \
    ${HA1588_IP_DIR}/rtl/top/ha1588.v \
    ${HA1588_IP_DIR}/rtl/bus/wishbone/wb_slv_wrapper.v \
    ${ETHMAC_AHB_HOME}/amba_wb_bridges/src/rtl/ahb3lite_to_wb.v \
    ${ETHMAC_AHB_HOME}/src/rtl/ha1588_ahb.v

# ── Elaborate ───────────────────────────────────────────────────────────────
elaborate -top ha1588_ahb

# ── Clock and reset ─────────────────────────────────────────────────────────
clock hclk
clock rtc_clk
clock rx_gmii_clk
clock tx_gmii_clk
reset -expression {!hresetn}

# ── X-propagation checks ───────────────────────────────────────────────────
set_xprop_check -effort high

# Assume AHB slave inputs are well-formed
assume -name ahbs_htrans_valid  {htrans_s inside {2'b00, 2'b10}}
assume -name ahbs_hsel_valid    {hsel_s   !== 1'bx}
assume -name ahbs_hready_valid  {hready_s !== 1'bx}
assume -name ahbs_hwrite_valid  {hwrite_s !== 1'bx}

# Assume GMII monitoring inputs are valid
assume -name rx_gmii_ctrl_valid {rx_gmii_ctrl !== 1'bx}
assume -name tx_gmii_ctrl_valid {tx_gmii_ctrl !== 1'bx}
assume -name rx_giga_valid      {rx_giga_mode !== 1'bx}
assume -name tx_giga_valid      {tx_giga_mode !== 1'bx}

# ── Run ─────────────────────────────────────────────────────────────────────
check_xprop -type {hold reset_value} -time_limit 900

# ── Report ──────────────────────────────────────────────────────────────────
report_xprop -verbose -file xprop_results.rpt
report_xprop -summary -file xprop_summary.rpt

exit
