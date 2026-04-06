# Cocotb Makefile for ha1588_apb verification
#
# Usage:
#   source ../../set_env.sh             # set HA1588_IP_DIR
#   make                                # run all tests
#   make TESTCASE=test_scratch_register # run single test

TOPLEVEL_LANG = verilog
SIM ?= vcs

HA1588_IP_DIR   ?= /research/AAA/ip_library/OpenCores-HA1588
HA1588_RTL       = $(HA1588_IP_DIR)/rtl

# Include path for `include directives within the HA1588 IP
COMPILE_ARGS += +incdir+$(HA1588_RTL)/tsu

# Enable SystemVerilog for SVA assertions
COMPILE_ARGS += -sverilog

# Note: X-propagation analysis is done via VC Formal (formal/ha1588_ahb/xprop.tcl).
# VCS -xprop=tmerge is NOT used here because reg.v has no reset logic, causing
# false failures in simulation. The formal xprop flow is the ASIC sign-off method.

# Enable VCS code coverage (line, condition, toggle, FSM, branch)
COMPILE_ARGS += -cm line+cond+tgl+fsm+branch
SIM_ARGS     += -cm line+cond+tgl+fsm+branch

# Source files: testbench wrapper
VERILOG_SOURCES  = $(CURDIR)/tb_ha1588_apb.v

# Wrapper RTL
VERILOG_SOURCES += $(CURDIR)/../../src/rtl/ha1588_apb.v

# Bridge IP (from submodule)
VERILOG_SOURCES += $(CURDIR)/../../amba_wb_bridges/src/rtl/apb_to_wb.v

# WB slave wrapper (from HA1588 IP)
VERILOG_SOURCES += $(HA1588_RTL)/bus/wishbone/wb_slv_wrapper.v

# HA1588 core IP
VERILOG_SOURCES += $(HA1588_RTL)/top/ha1588.v
VERILOG_SOURCES += $(HA1588_RTL)/reg/reg.v
VERILOG_SOURCES += $(HA1588_RTL)/rtc/rtc.v
VERILOG_SOURCES += $(HA1588_RTL)/tsu/tsu.v
VERILOG_SOURCES += $(HA1588_RTL)/tsu/ptp_parser.v

# Generic ptp_queue replacement (no vendor FIFO dependency)
VERILOG_SOURCES += $(CURDIR)/../../src/rtl/ha1588_patches/ptp_queue.v

TOPLEVEL = tb_ha1588_apb
MODULE   = test_ha1588_apb

include $(shell cocotb-config --makefiles)/Makefile.sim

# Coverage report generation
.PHONY: coverage
coverage:
	urg -dir sim_build/simv.vdb -report coverage_report -format text
	@echo "Coverage report generated in coverage_report/"
	@cat coverage_report/dashboard.txt 2>/dev/null || true
