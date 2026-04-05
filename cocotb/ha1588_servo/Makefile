SIM             = vcs
TOPLEVEL_LANG   = verilog

VERILOG_SOURCES  = $(PWD)/tb_ha1588_servo.sv
VERILOG_SOURCES += $(PWD)/../../src/rtl/ha1588_servo.sv

TOPLEVEL = tb_ha1588_servo
MODULE   = test_ha1588_servo

COMPILE_ARGS += -full64 -sverilog -timescale=1ns/1ps -debug_access+all -kdb
SIM_ARGS     += +vcs+dumpvars+waves.vcd

ifdef COVERAGE
  CM_METRICS    ?= line+cond+fsm+tgl+branch
  COMPILE_ARGS  += -cm $(CM_METRICS)
  SIM_ARGS      += -cm $(CM_METRICS) -cm_dir $(CURDIR)/coverage.vdb
endif

include $(shell cocotb-config --makefiles)/Makefile.sim
