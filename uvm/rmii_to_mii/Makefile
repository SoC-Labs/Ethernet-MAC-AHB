###############################################################################
# Makefile for rmii_to_mii UVM Testbench
###############################################################################
# Uses Synopsys VCS with UVM.  No VC-VIP required — MII/RMII agents are
# custom (no commercial VIP exists for these simple interfaces).
###############################################################################

# Tool paths
VCS_HOME    ?= /eda/synopsys/2022-23/RHELx86/VCS_2022.06-SP2
VERDI_HOME  ?= /eda/synopsys/2022-23/RHELx86/VERDI_2022.06-SP2

# Project paths
PROJ_HOME   ?= $(realpath ../..)
RTL_DIR      = $(PROJ_HOME)/src/rtl
TB_DIR       = $(CURDIR)/tb
ENV_DIR      = $(CURDIR)/env
MII_AGENT    = $(CURDIR)/agents/mii_agent
RMII_AGENT   = $(CURDIR)/agents/rmii_agent
SEQ_DIR      = $(CURDIR)/sequences
TEST_DIR     = $(CURDIR)/tests

# Simulation output
SIM_DIR      = sim_build
COV_DIR      = coverage_report

# Default test
TEST        ?= rmii_mii_tx_test
SEED        ?= random
VERBOSITY   ?= UVM_MEDIUM

# ---------------------------------------------------------------
# VCS compile flags
# ---------------------------------------------------------------
VCS  = $(VCS_HOME)/bin/vcs

VCS_FLAGS  = -full64 -sverilog
VCS_FLAGS += -ntb_opts uvm-1.2
VCS_FLAGS += -timescale=1ns/1ps
VCS_FLAGS += -l $(SIM_DIR)/compile.log
VCS_FLAGS += -o $(SIM_DIR)/simv

# Coverage
VCS_FLAGS += -cm line+cond+tgl+fsm+branch
VCS_FLAGS += -cm_dir $(SIM_DIR)/simv.vdb

# UVM include path
UVM_HOME     = $(VCS_HOME)/etc/uvm-1.2
VCS_FLAGS += +incdir+$(UVM_HOME)

# Include paths
VCS_FLAGS += +incdir+$(RTL_DIR)
VCS_FLAGS += +incdir+$(TB_DIR)
VCS_FLAGS += +incdir+$(ENV_DIR)
VCS_FLAGS += +incdir+$(MII_AGENT)
VCS_FLAGS += +incdir+$(RMII_AGENT)
VCS_FLAGS += +incdir+$(SEQ_DIR)
VCS_FLAGS += +incdir+$(TEST_DIR)

# DUT source
VCS_FLAGS += $(RTL_DIR)/rmii_to_mii.v

# Top-level testbench
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
	@echo "Usage:"
	@echo "  make compile                    - Compile the testbench"
	@echo "  make run TEST=<test_name>       - Compile and run a specific test"
	@echo "  make run_all                    - Run all tests"
	@echo "  make coverage                   - Generate coverage report"
	@echo "  make waves                      - Compile with waveform dumping"
	@echo "  make clean                      - Clean build artifacts"
	@echo ""
	@echo "Available tests:"
	@echo "  rmii_mii_tx_test               - TX path (MII → RMII) directed"
	@echo "  rmii_mii_rx_test               - RX path (RMII → MII) directed"
	@echo "  rmii_mii_collision_test         - Collision detection"
	@echo "  rmii_mii_random_test            - Constrained-random TX+RX"
	@echo ""
	@echo "Variables:"
	@echo "  TEST=<name>                     - Test to run (default: rmii_mii_tx_test)"
	@echo "  SEED=<value|random>             - Random seed (default: random)"
	@echo "  VERBOSITY=<UVM_NONE|...|UVM_DEBUG> - UVM verbosity (default: UVM_MEDIUM)"

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

TESTS = rmii_mii_tx_test \
        rmii_mii_rx_test \
        rmii_mii_collision_test \
        rmii_mii_random_test

run_all: compile
	@fail=0; \
	for test in $(TESTS); do \
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
