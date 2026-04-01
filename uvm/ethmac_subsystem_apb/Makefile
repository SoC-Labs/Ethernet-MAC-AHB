###############################################################################
# Makefile for ethmac_subsystem_apb UVM Testbench
###############################################################################
# Uses Synopsys VCS with VC VIP AMBA suite (APB + AHB).
# xprop enabled for X-propagation verification (CP9).
###############################################################################

# Tool paths
VCS_HOME    ?= /eda/synopsys/2022-23/RHELx86/VCS_2022.06-SP2
VERDI_HOME  ?= /eda/synopsys/2022-23/RHELx86/VERDI_2022.06-SP2
VIP_HOME    ?= /eda/synopsys/2022-23/RHELx86/VC-VIP-SOC_2022.12
AMBA_HOME    = $(VIP_HOME)/vip/svt/amba_svt/latest
SVT_HOME     = $(VIP_HOME)/vip/svt/common/latest

# Project paths
PROJ_HOME     ?= $(realpath ../..)
ETHMAC_IP_DIR ?= /research/AAA/ip_library/OpenCores-EthMAC
HA1588_IP_DIR ?= /research/AAA/ip_library/OpenCores-HA1588
CMSDK_DIR     ?= /research/AAA/ip_library/BP210/BP210-BU-00000-r1p1-00rel0

RTL_DIR    = $(PROJ_HOME)/src/rtl
BRIDGE_DIR = $(PROJ_HOME)/amba_wb_bridges/src/rtl
TB_DIR     = $(CURDIR)/tb
ENV_DIR    = $(CURDIR)/env
SEQ_DIR    = $(CURDIR)/sequences
TEST_DIR   = $(CURDIR)/tests

SIM_DIR    = sim_build
COV_DIR    = coverage_report

export DESIGNWARE_HOME := $(VIP_HOME)

TEST       ?= subsystem_register_test
SEED       ?= random
VERBOSITY  ?= UVM_MEDIUM

# ---------------------------------------------------------------
# VCS compile flags
# ---------------------------------------------------------------
VCS  = $(VCS_HOME)/bin/vcs

VCS_FLAGS  = -full64 -sverilog
VCS_FLAGS += -ntb_opts uvm-1.2
VCS_FLAGS += -xprop=tmerge
VCS_FLAGS += -timescale=1ns/1ps
VCS_FLAGS += -l $(SIM_DIR)/compile.log
VCS_FLAGS += -o $(SIM_DIR)/simv

# VIP defines
VCS_FLAGS += +define+DESIGNWARE_INCDIR=$(VIP_HOME)
VCS_FLAGS += +define+UVM_DISABLE_AUTO_ITEM_RECORDING
VCS_FLAGS += +define+SVT_APB_DISABLE_IMPLICIT_BUS_CONNECTION
VCS_FLAGS += +define+SVT_AHB_DISABLE_IMPLICIT_BUS_CONNECTION
VCS_FLAGS += +define+ETH_WISHBONE_B3

# Coverage
VCS_FLAGS += -cm line+cond+tgl+fsm+branch
VCS_FLAGS += -cm_dir $(SIM_DIR)/simv.vdb

# Include paths
UVM_HOME = $(VCS_HOME)/etc/uvm-1.2
VCS_FLAGS += +incdir+$(UVM_HOME)
VCS_FLAGS += +incdir+$(SVT_HOME)/sverilog/include
VCS_FLAGS += +incdir+$(AMBA_HOME)/sverilog/include
VCS_FLAGS += +incdir+$(RTL_DIR)
VCS_FLAGS += +incdir+$(ETHMAC_IP_DIR)/rtl/verilog
VCS_FLAGS += +incdir+$(HA1588_IP_DIR)/rtl/tsu
VCS_FLAGS += +incdir+$(TB_DIR)
VCS_FLAGS += +incdir+$(ENV_DIR)
VCS_FLAGS += +incdir+$(SEQ_DIR)
VCS_FLAGS += +incdir+$(TEST_DIR)

# VIP search paths
VCS_FLAGS += -y $(SVT_HOME)/sverilog/src/vcs
VCS_FLAGS += -y $(SVT_HOME)/sverilog/src/com
VCS_FLAGS += -y $(AMBA_HOME)/sverilog/src/vcs
VCS_FLAGS += -y $(AMBA_HOME)/sverilog/src/com
VCS_FLAGS += +libext+.svp+.sv+.svi+.svh

# DUT source
VCS_FLAGS += $(CMSDK_DIR)/logical/cmsdk_apb_slave_mux/verilog/cmsdk_apb_slave_mux.v
VCS_FLAGS += $(BRIDGE_DIR)/apb_to_wb.v
VCS_FLAGS += $(BRIDGE_DIR)/wb_to_ahb3lite.v
VCS_FLAGS += $(ETHMAC_IP_DIR)/rtl/verilog/eth_top.v
VCS_FLAGS += $(ETHMAC_IP_DIR)/rtl/verilog/eth_registers.v
VCS_FLAGS += $(ETHMAC_IP_DIR)/rtl/verilog/eth_register.v
VCS_FLAGS += $(ETHMAC_IP_DIR)/rtl/verilog/eth_maccontrol.v
VCS_FLAGS += $(ETHMAC_IP_DIR)/rtl/verilog/eth_macstatus.v
VCS_FLAGS += $(ETHMAC_IP_DIR)/rtl/verilog/eth_miim.v
VCS_FLAGS += $(ETHMAC_IP_DIR)/rtl/verilog/eth_shiftreg.v
VCS_FLAGS += $(ETHMAC_IP_DIR)/rtl/verilog/eth_clockgen.v
VCS_FLAGS += $(ETHMAC_IP_DIR)/rtl/verilog/eth_outputcontrol.v
VCS_FLAGS += $(ETHMAC_IP_DIR)/rtl/verilog/eth_random.v
VCS_FLAGS += $(ETHMAC_IP_DIR)/rtl/verilog/eth_receivecontrol.v
VCS_FLAGS += $(ETHMAC_IP_DIR)/rtl/verilog/eth_transmitcontrol.v
VCS_FLAGS += $(ETHMAC_IP_DIR)/rtl/verilog/eth_txcounters.v
VCS_FLAGS += $(ETHMAC_IP_DIR)/rtl/verilog/eth_txethmac.v
VCS_FLAGS += $(ETHMAC_IP_DIR)/rtl/verilog/eth_txstatem.v
VCS_FLAGS += $(ETHMAC_IP_DIR)/rtl/verilog/eth_rxcounters.v
VCS_FLAGS += $(ETHMAC_IP_DIR)/rtl/verilog/eth_rxethmac.v
VCS_FLAGS += $(ETHMAC_IP_DIR)/rtl/verilog/eth_rxstatem.v
VCS_FLAGS += $(ETHMAC_IP_DIR)/rtl/verilog/eth_rxaddrcheck.v
VCS_FLAGS += $(ETHMAC_IP_DIR)/rtl/verilog/eth_crc.v
VCS_FLAGS += $(ETHMAC_IP_DIR)/rtl/verilog/eth_cop.v
VCS_FLAGS += $(ETHMAC_IP_DIR)/rtl/verilog/eth_fifo.v
VCS_FLAGS += $(RTL_DIR)/ethmac_patches/eth_spram_256x32.v
VCS_FLAGS += $(RTL_DIR)/ethmac_patches/eth_wishbone.v
VCS_FLAGS += $(RTL_DIR)/generic/ethmac_sram.v
VCS_FLAGS += $(HA1588_IP_DIR)/rtl/rtc/rtc.v
VCS_FLAGS += $(HA1588_IP_DIR)/rtl/tsu/ptp_parser.v
VCS_FLAGS += $(RTL_DIR)/ha1588_patches/ptp_queue.v
VCS_FLAGS += $(HA1588_IP_DIR)/rtl/tsu/tsu.v
VCS_FLAGS += $(HA1588_IP_DIR)/rtl/reg/reg.v
VCS_FLAGS += $(HA1588_IP_DIR)/rtl/top/ha1588.v
VCS_FLAGS += $(HA1588_IP_DIR)/rtl/bus/wishbone/wb_slv_wrapper.v
VCS_FLAGS += $(RTL_DIR)/ethmac_subsystem_apb.v

# Testbench
VCS_FLAGS += $(TB_DIR)/top.sv

# ---------------------------------------------------------------
# Simulation run flags
# ---------------------------------------------------------------
SIM_FLAGS  = +UVM_TESTNAME=$(TEST)
SIM_FLAGS += +UVM_VERBOSITY=$(VERBOSITY)
SIM_FLAGS += -cm line+cond+tgl+fsm+branch
SIM_FLAGS += -cm_dir $(SIM_DIR)/simv.vdb
SIM_FLAGS += -l $(TEST).log

ifneq ($(SEED),random)
  SIM_FLAGS += +ntb_random_seed=$(SEED)
else
  SIM_FLAGS += +ntb_random_seed_automatic
endif

# ---------------------------------------------------------------
# Targets
# ---------------------------------------------------------------
.PHONY: compile run clean coverage run_all help waves

help:
	@echo "ethmac_subsystem_apb UVM Testbench"
	@echo ""
	@echo "  make run TEST=<name>  - Compile and run"
	@echo "  make run_all          - Run all tests"
	@echo "  make coverage         - Generate coverage report"
	@echo "  make clean            - Clean"
	@echo ""
	@echo "Tests: subsystem_register_test subsystem_random_test subsystem_reset_test subsystem_rtc_test subsystem_dma_test"

compile: | $(SIM_DIR)
	$(VCS) $(VCS_FLAGS)

$(SIM_DIR):
	mkdir -p $(SIM_DIR)

run: compile
	cd $(SIM_DIR) && ./simv $(SIM_FLAGS)

waves: VCS_FLAGS += +define+WAVES_VCD
waves: run

coverage:
	$(VCS_HOME)/bin/urg -dir $(SIM_DIR)/simv.vdb -report $(COV_DIR) -format text

TESTS = subsystem_register_test \
        subsystem_random_test \
        subsystem_reset_test \
        subsystem_rtc_test \
        subsystem_dma_test

run_all: compile
	@fail=0; \
	for test in $(TESTS); do \
		echo ""; \
		echo "======== Running $$test ========"; \
		if cd $(SIM_DIR) && ./simv +UVM_TESTNAME=$$test +UVM_VERBOSITY=$(VERBOSITY) \
			-cm line+cond+tgl+fsm+branch -cm_dir simv.vdb \
			+ntb_random_seed_automatic -l $$test.log; then \
			echo "  PASSED: $$test"; \
		else \
			echo "  FAILED: $$test"; \
			fail=$$((fail + 1)); \
		fi; \
		cd ..; \
	done; \
	echo "======== All tests complete ($$fail failure(s)) ========"; \
	exit $$fail

clean:
	rm -rf $(SIM_DIR) $(COV_DIR) csrc *.log ucli.key vc_hdrs.h
