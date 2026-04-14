# Cocotb Makefile for ethmac_ahb verification
#
# Usage:
#   source ../../set_env.sh          # set ETHMAC_IP_DIR
#   make                             # run all tests
#   make TESTCASE=test_reg_defaults  # run single test

TOPLEVEL_LANG = verilog
SIM ?= vcs

ETHMAC_IP_DIR  ?= /research/AAA/ip_library/OpenCores-EthMAC
ETHMAC_RTL      = $(ETHMAC_IP_DIR)/rtl/verilog
ETHMAC_PATCHES  = $(CURDIR)/../../src/rtl/ethmac_patches

# Include path for `include directives within eth_top
COMPILE_ARGS += +incdir+$(ETHMAC_RTL)

# Enable WISHBONE B3 burst support (required for WB-to-AHB bridge CTI/BTE)
COMPILE_ARGS += +define+ETH_WISHBONE_B3

# RAM selection — all defines below are OFF by default in eth_defines.v,
# which selects the generic behavioural RAM (reg-based) for the TX/RX FIFOs.
# The BD SPRAM implementation is now selected via the ethmac_sram wrapper
# (see src/rtl/ethmac_patches/README.md). For simulation, the generic
# variant (src/rtl/generic/ethmac_sram.v) is used.
# To target Xilinx FIFOs, uncomment:
#   COMPILE_ARGS += +define+ETH_FIFO_XILINX          # Xilinx distributed RAM for FIFOs

# Source files: testbench wrapper
VERILOG_SOURCES  = $(CURDIR)/tb_ethmac_ahb_swap.v

# Wrapper RTL
VERILOG_SOURCES += $(CURDIR)/../../src/rtl/ethmac_ahb.v

# Bridge IPs (from submodule)
VERILOG_SOURCES += $(CURDIR)/../../amba_wb_bridges/src/rtl/ahb3lite_to_wb.v
VERILOG_SOURCES += $(CURDIR)/../../amba_wb_bridges/src/rtl/wb_to_ahb3lite.v

# OpenCores Ethernet MAC IP — unmodified files from external repo
VERILOG_SOURCES += $(ETHMAC_RTL)/eth_top.v
VERILOG_SOURCES += $(ETHMAC_RTL)/eth_registers.v
VERILOG_SOURCES += $(ETHMAC_RTL)/eth_register.v
VERILOG_SOURCES += $(ETHMAC_RTL)/eth_maccontrol.v
VERILOG_SOURCES += $(ETHMAC_RTL)/eth_macstatus.v
VERILOG_SOURCES += $(ETHMAC_RTL)/eth_miim.v
VERILOG_SOURCES += $(ETHMAC_RTL)/eth_shiftreg.v
VERILOG_SOURCES += $(ETHMAC_RTL)/eth_clockgen.v
VERILOG_SOURCES += $(ETHMAC_RTL)/eth_outputcontrol.v
VERILOG_SOURCES += $(ETHMAC_RTL)/eth_random.v
VERILOG_SOURCES += $(ETHMAC_RTL)/eth_receivecontrol.v
VERILOG_SOURCES += $(ETHMAC_RTL)/eth_transmitcontrol.v
VERILOG_SOURCES += $(ETHMAC_RTL)/eth_txcounters.v
VERILOG_SOURCES += $(ETHMAC_RTL)/eth_txethmac.v
VERILOG_SOURCES += $(ETHMAC_RTL)/eth_txstatem.v
VERILOG_SOURCES += $(ETHMAC_RTL)/eth_rxcounters.v
VERILOG_SOURCES += $(ETHMAC_RTL)/eth_rxethmac.v
VERILOG_SOURCES += $(ETHMAC_RTL)/eth_rxstatem.v
VERILOG_SOURCES += $(ETHMAC_RTL)/eth_rxaddrcheck.v
VERILOG_SOURCES += $(ETHMAC_RTL)/eth_crc.v
VERILOG_SOURCES += $(ETHMAC_RTL)/eth_cop.v
VERILOG_SOURCES += $(ETHMAC_RTL)/eth_fifo.v

# Patched ethmac files — 'do' port renamed to 'do_o' for VCS -sverilog compat
# (see src/rtl/ethmac_patches/README.md)
VERILOG_SOURCES += $(ETHMAC_PATCHES)/eth_spram_256x32.v
VERILOG_SOURCES += $(ETHMAC_PATCHES)/eth_wishbone.v

# SRAM wrapper — generic (reg-based) for simulation
VERILOG_SOURCES += $(CURDIR)/../../src/rtl/generic/ethmac_sram.v

TOPLEVEL = tb_ethmac_ahb_swap
MODULE   = test_ethmac_ahb_swap_dma

# ── C Driver Shared Library (for driver-in-the-loop testing) ────────────
ETHMAC_SW    := $(CURDIR)/../../src/sw
CC_HOST      := gcc
CFLAGS_HOST  := -shared -fPIC -DHAL_TEST_MODE -O0 -g -Wall -Wextra

# Default target: build C driver then run cocotb simulation
all: libethmac_driver.so sim

# Ensure generated headers exist (from RDL sources) before compiling
.PHONY: generate-headers
generate-headers:
	$(MAKE) -C $(ETHMAC_SW) generate

libethmac_driver.so: generate-headers $(ETHMAC_SW)/ethmac.c ethmac_test_wrappers.c \
                     $(ETHMAC_SW)/ethmac.h $(ETHMAC_SW)/hal_io.h
	$(CC_HOST) $(CFLAGS_HOST) -I$(ETHMAC_SW) -include $(ETHMAC_SW)/hal_io.h \
	    $(ETHMAC_SW)/ethmac.c ethmac_test_wrappers.c -o $@

.PHONY: driver-so clean-driver
driver-so: libethmac_driver.so

clean-driver:
	rm -f libethmac_driver.so

include $(shell cocotb-config --makefiles)/Makefile.sim
