TOPLEVEL_LANG = verilog
SIM ?= vcs

# Source files
VERILOG_SOURCES  = $(PWD)/wb_to_ahb3lite_tb.v
VERILOG_SOURCES += $(PWD)/../../src/rtl/ahb3lite_wb_bridge/wb_to_ahb3lite.v

TOPLEVEL = wb_to_ahb3lite_tb
MODULE   = test_wb_to_ahb3lite

include $(shell cocotb-config --makefiles)/Makefile.sim
