# VC Formal X-propagation script for ha1588_apb
# Verifies that no X-state can propagate to any external output
# (APB slave, RTC outputs) from valid reset through normal APB operation.
#
# Full hierarchy including apb_to_wb bridge, wb_slv_wrapper, and HA1588 core.

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
    ${ETHMAC_AHB_HOME}/amba_wb_bridges/src/rtl/apb_to_wb.v \
    ${ETHMAC_AHB_HOME}/src/rtl/ha1588_apb.v

# ── Elaborate ───────────────────────────────────────────────────────────────
elaborate -top ha1588_apb

# ── Clock and reset ─────────────────────────────────────────────────────────
clock pclk
reset -expression {!presetn}

# ── X-propagation checks ───────────────────────────────────────────────────
set_xprop_check -effort high

# Assume APB slave-side inputs are well-formed
assume -name apb_psel_valid    {psel    !== 1'bx}
assume -name apb_penable_valid {penable !== 1'bx}
assume -name apb_pwrite_valid  {pwrite  !== 1'bx}

# Assume GMII monitoring inputs are valid (not X)
assume -name gmii_rx_ctrl_valid {rx_gmii_ctrl !== 1'bx}
assume -name gmii_tx_ctrl_valid {tx_gmii_ctrl !== 1'bx}
assume -name gmii_rx_giga_valid {rx_giga_mode !== 1'bx}
assume -name gmii_tx_giga_valid {tx_giga_mode !== 1'bx}

# ── Run ─────────────────────────────────────────────────────────────────────
check_xprop -type {hold reset_value} -time_limit 600

# ── Report ──────────────────────────────────────────────────────────────────
report_xprop -verbose -file xprop_results.rpt
report_xprop -summary -file xprop_summary.rpt

exit
