# Cocotb Makefile for ptp_event_detector verification
#
# Usage:
#   make                                    # run all tests
#   make TESTCASE=test_ptp_frame_detected   # run single test

TOPLEVEL_LANG = verilog
SIM ?= vcs

VERILOG_SOURCES  = $(CURDIR)/tb_top.v
VERILOG_SOURCES += $(CURDIR)/../../src/rtl/ptp_event_detector.v

TOPLEVEL = tb_top
MODULE   = test_ptp_event_detector

include $(shell cocotb-config --makefiles)/Makefile.sim
