# VC Formal X-propagation script for rmii_to_mii
# Verifies that no X-state can propagate to MII/RMII outputs
# from valid reset through normal operation.

# ── Analyze design ──────────────────────────────────────────────────────────
set ETHMAC_AHB_HOME [file normalize [file dirname [info script]]/../..]

analyze -format verilog \
    ${ETHMAC_AHB_HOME}/src/rtl/rmii_to_mii.v

# ── Elaborate ───────────────────────────────────────────────────────────────
elaborate -top rmii_to_mii

# ── Clock and reset ─────────────────────────────────────────────────────────
clock rmii_ref_clk
reset -expression {!RESETn}

# ── X-propagation checks ───────────────────────────────────────────────────
set_xprop_check -effort high

# Assume RMII receive inputs are valid
assume -name rmii_rxd_valid    {rmii_rxd    !== 2'bxx}
assume -name rmii_crs_dv_valid {rmii_crs_dv !== 1'bx}

# Assume MII transmit inputs are valid
assume -name mii_mtxd_valid  {mtxd  !== 4'bxxxx}
assume -name mii_mtxen_valid {mtxen !== 1'bx}
assume -name mii_mtxerr_valid {mtxerr !== 1'bx}

# ── Run ─────────────────────────────────────────────────────────────────────
check_xprop -type {hold reset_value} -time_limit 300

# ── Report ──────────────────────────────────────────────────────────────────
report_xprop -verbose -file xprop_results.rpt
report_xprop -summary -file xprop_summary.rpt

exit
