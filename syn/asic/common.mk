# Common ASIC synthesis definitions
# Included by all flow Makefiles under syn/asic/

export ETHMAC_AHB_HOME := $(realpath $(dir $(lastword $(MAKEFILE_LIST)))/../..)

# ── External IP path ──────────────────────────────────────────────────────
# OpenCores Ethernet MAC IP (required for eth_top and submodules)
export ETHMAC_IP_DIR ?= /research/AAA/ip_library/OpenCores-EthMAC

# ── Target module ──────────────────────────────────────────────────────────
export MODULE ?= ethmac_ahb

# ── File lists ─────────────────────────────────────────────────────────────
# Use ASIC filelist if it exists (instantiates compiled SRAM macro),
# otherwise fall back to the default filelist (bridge-only modules).
FLIST_ASIC    := $(ETHMAC_AHB_HOME)/flist/$(MODULE)_asic.flist
FLIST_DEFAULT := $(ETHMAC_AHB_HOME)/flist/$(MODULE).flist
export FLIST  := $(if $(wildcard $(FLIST_ASIC)),$(FLIST_ASIC),$(FLIST_DEFAULT))

# ── Cell libraries (update paths to match your PDK installation) ───────────
# Target library (.db) — used for mapping and optimization
# Defaultly using the 65nm Library
export TARGET_LIB     ?= /research/AAA/phys_ip_library/arm/tsmc/cln65lp/sc12_base_rvt/r0p0/db/sc12_cln65lp_base_rvt_ss_typical_max_1p08v_125c.db

# Compiled SRAM macro library (rf_08k — 2048x32, TSMC 65nm)
export MEM_PATH       ?= /research/precompiled_mems/TSMC65/rf_08k
export MEM_DB_SS      ?= $(MEM_PATH)/rf_08k_ss_1p08v_1p08v_125c.db

# Link libraries — target + any additional macro/IP libs
export LINK_LIBS      ?= $(TARGET_LIB) $(MEM_DB_SS)

# TF/Milkyway — physical reference for floorplan estimation (TSMC 65nm, 1p9m_6x2z)
export PHYS_IP_PATH   ?= /research/AAA/phys_ip_library/arm/tsmc/cln65lp

# Standard cell Verilog simulation models (for gate-level simulation)
export STDCELL_VERILOG ?= $(PHYS_IP_PATH)/sc12_base_rvt/r0p0
export TF_FILE        ?= $(PHYS_IP_PATH)/arm_tech/r2p0/milkyway/1p9m_6x2z/sc12_tech.tf
export MW_REF_LIB     ?= $(PHYS_IP_PATH)/sc12_base_rvt/r0p0/milkyway/1p9m_6x2z/sc12_cln65lp_base_rvt

# ── RTLA Reference Methodology ────────────────────────────────────────────
export RTLA_RM_PATH   ?= /research/synopsys/RTLA-RM_U-2022.12

# ── Multi-corner .db libraries (for RTLA CLIB on-the-fly creation) ────────
export DB_PATH        ?= $(PHYS_IP_PATH)/sc12_base_rvt/r0p0/db
export DB_SS          ?= $(DB_PATH)/sc12_cln65lp_base_rvt_ss_typical_max_1p08v_125c.db
export DB_FF          ?= $(DB_PATH)/sc12_cln65lp_base_rvt_ff_typical_min_1p32v_m40c.db

# ── TLU+ parasitic extraction models ─────────────────────────────────────
export TLUPLUS_PATH   ?= $(PHYS_IP_PATH)/arm_tech/r2p0/synopsys_tluplus/1p9m_6x2z
export TLUPLUS_MAP    ?= $(TLUPLUS_PATH)/tluplus.map

# ── Design constraints ─────────────────────────────────────────────────────
export CLK_NAME        ?= hclk
export CLK_PERIOD      ?= 4.0
export CLK_UNCERTAINTY ?= 0.35
export RST_NAME        ?= hresetn

# ── Available modules ──────────────────────────────────────────────────────
MODULES = ethmac_ahb ethmac_ahb_rmii rmii_to_mii ahb3lite_to_wb wb_to_ahb3lite
