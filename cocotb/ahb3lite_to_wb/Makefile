TOPLEVEL_LANG = verilog
SIM ?= vcs

# Source files
VERILOG_SOURCES  = $(PWD)/ahb3lite_to_wb_tb.v
VERILOG_SOURCES += $(PWD)/../../src/rtl/bridges/ahb3lite_to_wb.v

TOPLEVEL = ahb3lite_to_wb_tb
MODULE   = test_ahb3lite_to_wb

include $(shell cocotb-config --makefiles)/Makefile.sim
