TOPLEVEL_LANG = verilog
SIM ?= vcs

# Source files
VERILOG_SOURCES  = $(PWD)/wb_to_ahb3lite_tb.v
VERILOG_SOURCES += $(PWD)/../../src/rtl/bridges/wb_to_ahb3lite.v
VERILOG_SOURCES += $(PWD)/../../formal/wb_to_ahb3lite/wb_to_ahb3lite_props.sv

# Enable SystemVerilog for SVA assertions
COMPILE_ARGS += -sverilog

# Enable VCS code coverage (statement, branch, condition, toggle, FSM)
COMPILE_ARGS += -cm line+cond+tgl+fsm+branch
SIM_ARGS     += -cm line+cond+tgl+fsm+branch

TOPLEVEL = wb_to_ahb3lite_tb
MODULE   = test_wb_to_ahb3lite

include $(shell cocotb-config --makefiles)/Makefile.sim

# Coverage report generation
.PHONY: coverage
coverage:
	urg -dir sim_build/simv.vdb -report coverage_report -format text
	@echo "Coverage report generated in coverage_report/"
	@cat coverage_report/dashboard.txt 2>/dev/null || true
