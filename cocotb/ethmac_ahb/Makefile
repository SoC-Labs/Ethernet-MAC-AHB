# Cocotb Makefile for ethmac_ahb verification
#
# Usage:
#   source ../../set_env.sh          # set ETHMAC_IP_DIR
#   make                             # run all tests
#   make TESTCASE=test_reg_defaults  # run single test

TOPLEVEL_LANG = verilog
SIM ?= vcs

ETHMAC_IP_DIR  ?= $(HOME)/SoCLabs/ethmac/tags/rel_27
ETHMAC_RTL      = $(ETHMAC_IP_DIR)/rtl/verilog
ETHMAC_PATCHES  = $(PWD)/../../src/rtl/ethmac_patches

# Include path for `include directives within eth_top
COMPILE_ARGS += +incdir+$(ETHMAC_RTL)

# Enable WISHBONE B3 burst support (required for WB-to-AHB bridge CTI/BTE)
COMPILE_ARGS += +define+ETH_WISHBONE_B3

# RAM selection — all defines below are OFF by default in eth_defines.v,
# which selects the generic behavioural RAM (reg-based) for both the BD
# SPRAM and the TX/RX FIFOs.  This is the correct choice for simulation.
# To target a specific technology, uncomment ONE of the following:
#   COMPILE_ARGS += +define+ETH_XILINX_RAMB4        # Xilinx RAMB4 for BD SPRAM
#   COMPILE_ARGS += +define+ETH_VIRTUAL_SILICON_RAM  # VS ASIC RAM for BD SPRAM
#   COMPILE_ARGS += +define+ETH_ARTISAN_RAM          # Artisan ASIC RAM for BD SPRAM
#   COMPILE_ARGS += +define+ETH_FIFO_XILINX          # Xilinx distributed RAM for FIFOs

# Source files: testbench wrapper
VERILOG_SOURCES  = $(PWD)/tb_ethmac_ahb.v

# Wrapper RTL
VERILOG_SOURCES += $(PWD)/../../src/rtl/generic/ethmac_ahb.v

# Bridge IPs
VERILOG_SOURCES += $(PWD)/../../src/rtl/ahb3lite_wb_bridge/ahb3lite_to_wb.v
VERILOG_SOURCES += $(PWD)/../../src/rtl/ahb3lite_wb_bridge/wb_to_ahb3lite.v

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

TOPLEVEL = tb_ethmac_ahb
MODULE   = test_ethmac_ahb

include $(shell cocotb-config --makefiles)/Makefile.sim
