###############################################################################
# Makefile for eth_rx_cksum UVM Testbench
###############################################################################
# Minimal UVM env — no VC-VIP dependencies. Uses a native SV APB driver
# and MII source so it runs with any VCS + UVM install.
###############################################################################

VCS_HOME    ?= /eda/synopsys/2022-23/RHELx86/VCS_2022.06-SP2
UVM_HOME     = $(VCS_HOME)/etc/uvm-1.2

PROJ_HOME   ?= $(realpath ../..)

RTL_DIR      = $(PROJ_HOME)/src/rtl
TB_DIR       = $(CURDIR)/tb
ENV_DIR      = $(CURDIR)/env
SEQ_DIR      = $(CURDIR)/sequences
TEST_DIR     = $(CURDIR)/tests

SIM_DIR      = sim_build
COV_DIR      = coverage_report

TEST        ?= eth_rx_cksum_smoke_test
SEED        ?= random
VERBOSITY   ?= UVM_MEDIUM

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

# Coverage
VCS_FLAGS += -cm line+cond+tgl+fsm+branch
VCS_FLAGS += -cm_dir $(SIM_DIR)/simv.vdb

# Include paths
VCS_FLAGS += +incdir+$(UVM_HOME)
VCS_FLAGS += +incdir+$(TB_DIR)
VCS_FLAGS += +incdir+$(ENV_DIR)
VCS_FLAGS += +incdir+$(SEQ_DIR)
VCS_FLAGS += +incdir+$(TEST_DIR)

# ---------------------------------------------------------------
# Source files
# ---------------------------------------------------------------
SRC  = $(TB_DIR)/eth_rx_cksum_if.sv
SRC += $(RTL_DIR)/eth_rx_cksum.v
SRC += $(ENV_DIR)/eth_rx_cksum_pkg.sv
SRC += $(TB_DIR)/top.sv

# ---------------------------------------------------------------
# Sim run flags
# ---------------------------------------------------------------
RUN_FLAGS  = +vcs+initreg+0 +vcs+initmem+0
RUN_FLAGS += +UVM_TESTNAME=$(TEST)
RUN_FLAGS += +UVM_VERBOSITY=$(VERBOSITY)
RUN_FLAGS += +ntb_random_seed=$(SEED)
RUN_FLAGS += -cm line+cond+tgl+fsm+branch
RUN_FLAGS += -cm_dir $(SIM_DIR)/simv.vdb
RUN_FLAGS += -l $(SIM_DIR)/$(TEST).log

# ---------------------------------------------------------------
# Targets
# ---------------------------------------------------------------
.PHONY: all compile run clean coverage

all: compile run

compile:
	@mkdir -p $(SIM_DIR)
	$(VCS) $(VCS_FLAGS) $(SRC)

run: compile
	cd $(SIM_DIR) && ./simv $(RUN_FLAGS)

clean:
	rm -rf $(SIM_DIR) $(COV_DIR) csrc simv* ucli.key vc_hdrs.h

coverage:
	urg -dir $(SIM_DIR)/simv.vdb -report $(COV_DIR) -format text
	@echo "Coverage report generated in $(COV_DIR)/"
	@cat $(COV_DIR)/dashboard.txt 2>/dev/null || true
