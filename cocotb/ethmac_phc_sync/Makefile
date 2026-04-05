# Cocotb Makefile for ethmac + PHC synchronisation integration test
#
# Usage:
#   source ../../set_env.sh
#   make                                        # run all tests
#   make TESTCASE=test_sync_01_rx_event_capture  # run single test

TOPLEVEL_LANG = verilog
SIM ?= vcs

ETHMAC_IP_DIR  ?= /research/AAA/ip_library/OpenCores-EthMAC
HA1588_IP_DIR  ?= /research/AAA/ip_library/OpenCores-HA1588
CMSDK_DIR      ?= /research/AAA/ip_library/BP210/BP210-BU-00000-r1p1-00rel0
PHC_HOME       ?= $(PWD)/../../../ptp-hardware-clock-ahb

ETHMAC_RTL      = $(ETHMAC_IP_DIR)/rtl/verilog
ETHMAC_PATCHES  = $(PWD)/../../src/rtl/ethmac_patches

# Include paths
COMPILE_ARGS += +incdir+$(ETHMAC_RTL)
COMPILE_ARGS += +incdir+$(HA1588_IP_DIR)/rtl/tsu

# Defines
COMPILE_ARGS += +define+ETH_WISHBONE_B3

# Testbench
VERILOG_SOURCES  = $(PWD)/tb_top.sv

# Ethernet MAC subsystem
VERILOG_SOURCES += $(PWD)/../../src/rtl/ethmac_subsystem_apb.v
VERILOG_SOURCES += $(PWD)/../../src/rtl/ptp_event_detector.v
VERILOG_SOURCES += $(CMSDK_DIR)/logical/cmsdk_apb_slave_mux/verilog/cmsdk_apb_slave_mux.v
VERILOG_SOURCES += $(PWD)/../../amba_wb_bridges/src/rtl/apb_to_wb.v
VERILOG_SOURCES += $(PWD)/../../amba_wb_bridges/src/rtl/wb_to_ahb3lite.v

# OpenCores Ethernet MAC
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

# PHC
VERILOG_SOURCES += $(PHC_HOME)/src/rtl/phc.sv
VERILOG_SOURCES += $(PHC_HOME)/src/rtl/phc_apb_regs.sv
VERILOG_SOURCES += $(PHC_HOME)/src/rtl/phc_clock_core.sv

TOPLEVEL = tb_top
MODULE   = test_ethmac_phc_sync

include $(shell cocotb-config --makefiles)/Makefile.sim
