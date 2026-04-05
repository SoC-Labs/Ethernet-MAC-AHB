# Cocotb Makefile for ethmac_subsystem_apb verification
#
# Usage:
#   source ../../set_env.sh
#   make                                       # run all tests
#   make TESTCASE=test_cp1_apb_mux_eth_access  # run single test

TOPLEVEL_LANG = verilog
SIM ?= vcs

ETHMAC_IP_DIR  ?= /research/AAA/ip_library/OpenCores-EthMAC
HA1588_IP_DIR  ?= /research/AAA/ip_library/OpenCores-HA1588
CMSDK_DIR      ?= /research/AAA/ip_library/BP210/BP210-BU-00000-r1p1-00rel0

ETHMAC_RTL      = $(ETHMAC_IP_DIR)/rtl/verilog
ETHMAC_PATCHES  = $(PWD)/../../src/rtl/ethmac_patches

# Include paths
COMPILE_ARGS += +incdir+$(ETHMAC_RTL)
COMPILE_ARGS += +incdir+$(HA1588_IP_DIR)/rtl/tsu

# Defines
COMPILE_ARGS += +define+ETH_WISHBONE_B3

# Enable xprop for X-propagation verification (CP9)
COMPILE_ARGS += -xprop=tmerge

# Enable VCS code coverage
COMPILE_ARGS += -cm line+cond+tgl+fsm+branch
SIM_ARGS     += -cm line+cond+tgl+fsm+branch

# Testbench wrapper
VERILOG_SOURCES  = $(PWD)/tb_ethmac_subsystem_apb.v

# DUT: subsystem wrapper + PTP event detector
VERILOG_SOURCES += $(PWD)/../../src/rtl/ptp_event_detector.v
VERILOG_SOURCES += $(PWD)/../../src/rtl/ethmac_subsystem_apb.v

# CMSDK APB slave mux
VERILOG_SOURCES += $(CMSDK_DIR)/logical/cmsdk_apb_slave_mux/verilog/cmsdk_apb_slave_mux.v

# Bridge IPs (from submodule)
VERILOG_SOURCES += $(PWD)/../../amba_wb_bridges/src/rtl/apb_to_wb.v
VERILOG_SOURCES += $(PWD)/../../amba_wb_bridges/src/rtl/wb_to_ahb3lite.v

# OpenCores Ethernet MAC IP
VERILOG_SOURCES += $(ETHMAC_RTL)/eth_top.v
VERILOG_SOURCES += $(ETHMAC_RTL)/eth_registers.v
VERILOG_SOURCES += $(ETHMAC_RTL)/eth_register.v
VERILOG_SOURCES += $(ETHMAC_RTL)/eth_maccontrol.v
VERILOG_SOURCES += $(ETHMAC_RTL)/eth_macstatus.v
VERILOG_SOURCES += $(ETHMAC_RTL)/eth_miim.v
VERILOG_SOURCES += $(ETHMAC_RTL)/eth_shiftreg.v
VERILOG_SOURCES += $(ETHMAC_RTL)/eth_clockgen.v
VERILOG_SOURCES += $(ETHMAC_RTL)/eth_outputcontrol.v
VERILOG_SOURCES += $(ETHMAC_RTL)/eth_random.v
VERILOG_SOURCES += $(ETHMAC_RTL)/eth_receivecontrol.v
VERILOG_SOURCES += $(ETHMAC_RTL)/eth_transmitcontrol.v
VERILOG_SOURCES += $(ETHMAC_RTL)/eth_txcounters.v
VERILOG_SOURCES += $(ETHMAC_RTL)/eth_txethmac.v
VERILOG_SOURCES += $(ETHMAC_RTL)/eth_txstatem.v
VERILOG_SOURCES += $(ETHMAC_RTL)/eth_rxcounters.v
VERILOG_SOURCES += $(ETHMAC_RTL)/eth_rxethmac.v
VERILOG_SOURCES += $(ETHMAC_RTL)/eth_rxstatem.v
VERILOG_SOURCES += $(ETHMAC_RTL)/eth_rxaddrcheck.v
VERILOG_SOURCES += $(ETHMAC_RTL)/eth_crc.v
VERILOG_SOURCES += $(ETHMAC_RTL)/eth_cop.v
VERILOG_SOURCES += $(ETHMAC_RTL)/eth_fifo.v
VERILOG_SOURCES += $(ETHMAC_PATCHES)/eth_spram_256x32.v
VERILOG_SOURCES += $(ETHMAC_PATCHES)/eth_wishbone.v
VERILOG_SOURCES += $(PWD)/../../src/rtl/generic/ethmac_sram.v

# HA1588 PTP IP (patched reg, rtc, ha1588 for reset hygiene)
VERILOG_SOURCES += $(PWD)/../../src/rtl/ha1588_patches/ha1588.v
VERILOG_SOURCES += $(PWD)/../../src/rtl/ha1588_patches/reg.v
VERILOG_SOURCES += $(PWD)/../../src/rtl/ha1588_patches/rtc.v
VERILOG_SOURCES += $(HA1588_IP_DIR)/rtl/tsu/tsu.v
VERILOG_SOURCES += $(HA1588_IP_DIR)/rtl/tsu/ptp_parser.v
VERILOG_SOURCES += $(PWD)/../../src/rtl/ha1588_patches/ptp_queue.v
VERILOG_SOURCES += $(HA1588_IP_DIR)/rtl/bus/wishbone/wb_slv_wrapper.v
VERILOG_SOURCES += $(PWD)/../../src/rtl/ha1588_servo.sv

TOPLEVEL = tb_ethmac_subsystem_apb
MODULE  ?= test_ethmac_subsystem_apb

include $(shell cocotb-config --makefiles)/Makefile.sim

.PHONY: coverage
coverage:
	urg -dir sim_build/simv.vdb -report coverage_report -format text
	@echo "Coverage report generated in coverage_report/"
	@cat coverage_report/dashboard.txt 2>/dev/null || true
