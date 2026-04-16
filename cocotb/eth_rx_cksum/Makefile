# Cocotb Makefile for eth_rx_cksum unit-level verification
#
# Usage:
#   source ../../set_env.sh
#   make                                  # run all tests
#   make TESTCASE=test_id_ctrl            # run a single test
#   make EXTRA_ARGS=+dump                 # dump waves to eth_rx_cksum.vcd

TOPLEVEL_LANG = verilog
SIM ?= vcs

# RTL: just the new block — no dependency on the OpenCores MAC, HA1588,
# CMSDK, or the wb/ahb bridges. Stage 0 is fully self-contained, which
# is the whole point of the unit TB.
VERILOG_SOURCES  = $(CURDIR)/tb_eth_rx_cksum.v
VERILOG_SOURCES += $(CURDIR)/../../src/rtl/eth_rx_cksum.v

TOPLEVEL = tb_eth_rx_cksum
MODULE  ?= test_eth_rx_cksum

# X-propagation check on by default — every output has a defined reset
# and the read mux has a default arm.
#
# +vcs+initreg+0 / +vcs+initmem+0 zero-initialise all flops and memory
# arrays at time 0. The snapshot FIFO storage is intentionally left
# uninitialised in RTL (no reset fanout to the storage array) — this
# runtime init keeps simulation X-clean before the first frame.
ifeq ($(SIM),vcs)
  COMPILE_ARGS += -xprop=tmerge
  COMPILE_ARGS += -cm line+cond+tgl+fsm+branch
  SIM_ARGS     += -cm line+cond+tgl+fsm+branch
  SIM_ARGS     += +vcs+initreg+0 +vcs+initmem+0
endif

include $(shell cocotb-config --makefiles)/Makefile.sim

.PHONY: coverage
coverage:
	urg -dir sim_build/simv.vdb -report coverage_report -format text
	@echo "Coverage report generated in coverage_report/"
	@cat coverage_report/dashboard.txt 2>/dev/null || true
