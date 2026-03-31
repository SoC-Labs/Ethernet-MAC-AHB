#!/bin/bash
# Set up environment variables for the Ethernet MAC AHB project

export ETHMAC_IP_DIR=/research/AAA/ip_library/OpenCores-EthMAC
export HA1588_IP_DIR=/research/AAA/ip_library/OpenCores-HA1588

# AHB-WB Bridges submodule
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export AHB_BRIDGES_HOME="${SCRIPT_DIR}/bridges"
