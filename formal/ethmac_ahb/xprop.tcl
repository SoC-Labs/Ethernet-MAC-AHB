# VC Formal X-propagation script for ethmac_ahb (top-level)
# Verifies that no X-state can propagate to any external output
# (AHB master, AHB slave, MII, MDIO, IRQ) from valid reset.
#
# Full hierarchy including all submodules and OpenCores Ethernet MAC IP.

# ── Analyze design ──────────────────────────────────────────────────────────
set ETHMAC_AHB_HOME [file normalize [file dirname [info script]]/../..]
set ETHMAC_IP_DIR   $::env(ETHMAC_IP_DIR)

analyze -format verilog \
    ${ETHMAC_IP_DIR}/rtl/verilog/eth_defines.v \
    ${ETHMAC_IP_DIR}/rtl/verilog/timescale.v \
    ${ETHMAC_IP_DIR}/rtl/verilog/eth_clockgen.v \
    ${ETHMAC_IP_DIR}/rtl/verilog/eth_cop.v \
    ${ETHMAC_IP_DIR}/rtl/verilog/eth_crc.v \
    ${ETHMAC_IP_DIR}/rtl/verilog/eth_fifo.v \
    ${ETHMAC_IP_DIR}/rtl/verilog/eth_maccontrol.v \
    ${ETHMAC_IP_DIR}/rtl/verilog/eth_macstatus.v \
    ${ETHMAC_IP_DIR}/rtl/verilog/eth_miim.v \
    ${ETHMAC_IP_DIR}/rtl/verilog/eth_outputcontrol.v \
    ${ETHMAC_IP_DIR}/rtl/verilog/eth_random.v \
    ${ETHMAC_IP_DIR}/rtl/verilog/eth_receivecontrol.v \
    ${ETHMAC_IP_DIR}/rtl/verilog/eth_register.v \
    ${ETHMAC_IP_DIR}/rtl/verilog/eth_registers.v \
    ${ETHMAC_IP_DIR}/rtl/verilog/eth_rxaddrcheck.v \
    ${ETHMAC_IP_DIR}/rtl/verilog/eth_rxcounters.v \
    ${ETHMAC_IP_DIR}/rtl/verilog/eth_rxethmac.v \
    ${ETHMAC_IP_DIR}/rtl/verilog/eth_rxstatem.v \
    ${ETHMAC_IP_DIR}/rtl/verilog/eth_shiftreg.v \
    ${ETHMAC_IP_DIR}/rtl/verilog/eth_transmitcontrol.v \
    ${ETHMAC_IP_DIR}/rtl/verilog/eth_txcounters.v \
    ${ETHMAC_IP_DIR}/rtl/verilog/eth_txethmac.v \
    ${ETHMAC_IP_DIR}/rtl/verilog/eth_txstatem.v \
    ${ETHMAC_AHB_HOME}/src/rtl/ethmac_patches/eth_spram_256x32.v \
    ${ETHMAC_AHB_HOME}/src/rtl/ethmac_patches/eth_wishbone.v \
    ${ETHMAC_IP_DIR}/rtl/verilog/eth_top.v \
    ${ETHMAC_AHB_HOME}/src/rtl/ahb3lite_wb_bridge/ahb3lite_to_wb.v \
    ${ETHMAC_AHB_HOME}/src/rtl/wb_to_ahb3lite.v \
    ${ETHMAC_AHB_HOME}/src/rtl/ethmac_ahb.v

# ── Elaborate ───────────────────────────────────────────────────────────────
elaborate -top ethmac_ahb

# ── Clock and reset ─────────────────────────────────────────────────────────
clock hclk
reset -expression {!hresetn}

# ── X-propagation checks ───────────────────────────────────────────────────
set_xprop_check -effort high

# Assume AHB slave inputs are well-formed
assume -name ahbs_htrans_valid {htrans_s inside {2'b00, 2'b10}}
assume -name ahbs_hsel_valid   {hsel_s   !== 1'bx}
assume -name ahbs_hready_valid {hready_s !== 1'bx}

# Assume AHB master slave-side responses are valid
assume -name ahbm_hready_valid {hready !== 1'bx}
assume -name ahbm_hresp_valid  {hresp  !== 1'bx}

# Assume MII inputs are valid
assume -name mii_mrxdv_valid  {mrxdv_pad_i !== 1'bx}
assume -name mii_mrxerr_valid {mrxerr_pad_i !== 1'bx}
assume -name mii_mcoll_valid  {mcoll_pad_i !== 1'bx}
assume -name mii_mcrs_valid   {mcrs_pad_i  !== 1'bx}

# ── Run ─────────────────────────────────────────────────────────────────────
check_xprop -type {hold reset_value} -time_limit 900

# ── Report ──────────────────────────────────────────────────────────────────
report_xprop -verbose -file xprop_results.rpt
report_xprop -summary -file xprop_summary.rpt

exit
