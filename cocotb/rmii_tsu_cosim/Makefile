# Makefile -- HIGH-FIDELITY rmii_to_mii -> HA1588 RX-TSU co-simulation.
#
# Composes the REAL rmii_to_mii RX adapter with the HA1588 RX TSU exactly as
# ethmac_subsystem_apb.v wires them on silicon, and drives the rmii_to_mii RMII
# pins with realistic LAN8720-style stimulus. Reads RX_TSU_STAT depth over APB.
#
# Usage:
#   source ../../set_env.sh
#
#   # Against the CURRENT patched tsu.v (default -- the one that passes the
#   # gmii-direct oracle but fails on silicon):
#   make
#
#   # Single test:
#   make TESTCASE=test_rmii_tsu_phase_sweep
#   make TESTCASE=test_rmii_tsu_sanity_even_phase
#
#   # Against STOCK OpenCores tsu.v (read-only IP) for comparison:
#   make TSU_VARIANT=stock
#
# TSU_VARIANT selects which tsu.v is compiled (default: patched):
#   patched -> $(PATCH_DIR)/tsu.v            (local SFD-lock fix -- the silicon RTL)
#   stock   -> $(HA1588_RTL)/tsu/tsu.v       (read-only OpenCores IP)
#   sfdwip  -> $(PATCH_DIR)/tsu.v.sfd-lock-wip (preserved failed attempt)

TOPLEVEL_LANG = verilog
SIM ?= vcs

HA1588_IP_DIR   ?= /research/AAA/ip_library/OpenCores-HA1588
HA1588_RTL       = $(HA1588_IP_DIR)/rtl
PATCH_DIR        = $(CURDIR)/../../src/rtl/ha1588_patches
RTL_DIR          = $(CURDIR)/../../src/rtl
WB_BRIDGES       = $(CURDIR)/../../amba_wb_bridges/src/rtl

# --- tsu.v variant selection (default: patched == silicon RTL) ---------------
TSU_VARIANT ?= patched
ifeq ($(TSU_VARIANT),patched)
  TSU_SRC ?= $(PATCH_DIR)/tsu.v
endif
ifeq ($(TSU_VARIANT),stock)
  TSU_SRC ?= $(HA1588_RTL)/tsu/tsu.v
endif
ifeq ($(TSU_VARIANT),sfdwip)
  TSU_SRC ?= $(PATCH_DIR)/tsu.v.sfd-lock-wip
endif
TSU_SRC ?= $(PATCH_DIR)/tsu.v

# ptp_parser: use the local ha1588_patches copy (differs from stock only by a
# CDC async-reset bridge; no alignment/EtherType change) -- same as the oracle.
PTP_PARSER_SRC ?= $(PATCH_DIR)/ptp_parser.v

COMPILE_ARGS += +incdir+$(HA1588_RTL)/tsu
COMPILE_ARGS += -sverilog

# --- TB top + composed RTL ---------------------------------------------------
VERILOG_SOURCES  = $(CURDIR)/tb_rmii_tsu_cosim.v

# REAL rmii_to_mii RX adapter (the silicon RX front-end)
VERILOG_SOURCES += $(WB_BRIDGES)/rmii_to_mii.v

# HA1588 APB wrapper + bridge + HA1588 core
VERILOG_SOURCES += $(RTL_DIR)/ha1588_apb.v
VERILOG_SOURCES += $(WB_BRIDGES)/apb_to_wb.v
VERILOG_SOURCES += $(HA1588_RTL)/bus/wishbone/wb_slv_wrapper.v
VERILOG_SOURCES += $(HA1588_RTL)/top/ha1588.v
VERILOG_SOURCES += $(HA1588_RTL)/reg/reg.v
VERILOG_SOURCES += $(HA1588_RTL)/rtc/rtc.v
VERILOG_SOURCES += $(TSU_SRC)
VERILOG_SOURCES += $(PTP_PARSER_SRC)
VERILOG_SOURCES += $(PATCH_DIR)/ptp_queue.v

TOPLEVEL = tb_rmii_tsu_cosim
MODULE   = test_rmii_tsu_cosim

$(info Makefile(rmii_tsu_cosim): TSU_VARIANT=$(TSU_VARIANT)  TSU_SRC=$(TSU_SRC))

include $(shell cocotb-config --makefiles)/Makefile.sim
