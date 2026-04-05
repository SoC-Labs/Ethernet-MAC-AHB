#!/bin/bash
# Set up environment variables for the Ethernet MAC AHB project

export ETHMAC_IP_DIR=/research/AAA/ip_library/OpenCores-EthMAC
export HA1588_IP_DIR=/research/AAA/ip_library/OpenCores-HA1588

# CMSDK (ARM Cortex-M System Design Kit)
export CMSDK_DIR=/research/AAA/ip_library/BP210/BP210-BU-00000-r1p1-00rel0

# AHB-WB Bridges submodule
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export AHB_BRIDGES_HOME="${SCRIPT_DIR}/amba_wb_bridges"

# PTP Hardware Clock (expected alongside this repo for integration tests)
export PHC_HOME="${SCRIPT_DIR}/../ptp-hardware-clock-ahb"
