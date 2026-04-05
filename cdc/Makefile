export ETHMAC_AHB_HOME := $(realpath $(dir $(lastword $(MAKEFILE_LIST)))/..)
export ETHMAC_IP_DIR   ?= /research/AAA/ip_library/OpenCores-EthMAC
export HA1588_IP_DIR   ?= /research/AAA/ip_library/OpenCores-HA1588
export CMSDK_DIR       ?= /research/AAA/ip_library/BP210/BP210-BU-00000-r1p1-00rel0

# ── SpyGlass tool ────────────────────────────────────────────────────────────
SPYGLASS_HOME ?= /eda/synopsys/2022-23/RHELx86/SPYGLASS_2022.06-SP2/SPYGLASS_HOME
SPYGLASS      := $(SPYGLASS_HOME)/bin/spyglass

# ── Target module (override: make cdc MODULE=ethmac_ahb) ─────────────────────
MODULE ?= ethmac_subsystem_apb

# ── All CDC-lintable modules ─────────────────────────────────────────────────
CDC_MODULES = ethmac_subsystem_apb ethmac_ahb

# ── Paths ────────────────────────────────────────────────────────────────────
export FLIST  := $(ETHMAC_AHB_HOME)/flist/$(MODULE).flist
export SGDC   := $(ETHMAC_AHB_HOME)/cdc/$(MODULE).sgdc
export SWL    := $(ETHMAC_AHB_HOME)/cdc/waiver.swl
export SG_TOP := $(MODULE)
PRJ           := $(ETHMAC_AHB_HOME)/cdc/ethmac.prj

# SpyGlass output directory
SG_WORK := $(MODULE)_spyglass
RPTDIR  := $(SG_WORK)/cdc_verify/spyglass_reports

# Report files
RPT_SUMMARY := $(MODULE)_cdc_summary.rpt

# ── SpyGlass flags ───────────────────────────────────────────────────────────
SG_FLAGS := -batch \
            -project $(PRJ) \
            -reportdir $(RPTDIR) \
            -work_dir $(SG_WORK)

.PHONY: cdc cdc-each cdc-report clean help

# ── Default target: run CDC analysis ─────────────────────────────────────────
cdc:
	@echo "══════════════════════════════════════════════════════════"
	@echo "  SpyGlass CDC: $(MODULE)"
	@echo "══════════════════════════════════════════════════════════"
	$(SPYGLASS) $(SG_FLAGS)
	@echo ""
	@echo "CDC analysis complete. Results in $(RPTDIR)/"
	@$(MAKE) --no-print-directory cdc-report

# ── Run CDC on all modules ───────────────────────────────────────────────────
cdc-each:
	@for mod in $(CDC_MODULES); do \
		echo "══════════════════════════════════════════════════════════"; \
		echo "  CDC: $$mod"; \
		echo "══════════════════════════════════════════════════════════"; \
		$(MAKE) cdc MODULE=$$mod || exit 1; \
	done

# ── Extract summary report ───────────────────────────────────────────────────
cdc-report:
	@{ \
	echo "══════════════════════════════════════════════════════════"; \
	echo "  SpyGlass CDC Report: $(MODULE)"; \
	echo "══════════════════════════════════════════════════════════"; \
	echo ""; \
	echo "── Violation Summary ─────────────────────────────────────"; \
	if ls $(RPTDIR)/*summary* 1>/dev/null 2>&1; then \
		cat $(RPTDIR)/*summary*; \
	elif ls $(RPTDIR)/*.rpt 1>/dev/null 2>&1; then \
		grep -h -E '(Error|Warning|Info|Total)' $(RPTDIR)/*.rpt 2>/dev/null || echo "  (no summary lines found)"; \
	else \
		echo "  (no report files found — run 'make cdc' first)"; \
	fi; \
	echo ""; \
	echo "── CDC Crossings (SoCLabs RTL) ───────────────────────────"; \
	if ls $(RPTDIR)/*.rpt 1>/dev/null 2>&1; then \
		grep -h -E 'ethmac_|ha1588_|ptp_event' $(RPTDIR)/*.rpt 2>/dev/null | head -50 || echo "  (none found)"; \
	else \
		echo "  (no report files)"; \
	fi; \
	echo ""; \
	} | tee $(RPT_SUMMARY)
	@echo "Report saved to: $(RPT_SUMMARY)"

# ── Clean ────────────────────────────────────────────────────────────────────
clean:
	rm -rf *_spyglass *_cdc_summary.rpt \
	       spyglass_output spyglass.log sg_shell.log

# ── Help ─────────────────────────────────────────────────────────────────────
help:
	@echo "Ethernet MAC AHB SpyGlass CDC Flow"
	@echo ""
	@echo "Usage:"
	@echo "  make cdc                                - Run CDC analysis (default: $(MODULE))"
	@echo "  make cdc MODULE=ethmac_ahb              - Run CDC for MII-only variant"
	@echo "  make cdc-each                           - Run CDC on all modules"
	@echo "  make cdc-report                         - Re-extract summary from last run"
	@echo "  make clean                              - Remove SpyGlass work directories"
	@echo ""
	@echo "CDC modules:"
	@echo "  $(CDC_MODULES)"
	@echo ""
	@echo "Prerequisites:"
	@echo "  SPYGLASS_HOME: $(SPYGLASS_HOME)"
	@echo "  ETHMAC_IP_DIR: $(ETHMAC_IP_DIR)"
	@echo "  HA1588_IP_DIR: $(HA1588_IP_DIR)"
	@echo "  CMSDK_DIR:     $(CMSDK_DIR)"
	@echo ""
	@echo "Examples:"
	@echo "  make cdc                                - CDC lint ethmac_subsystem_apb (4 clock domains)"
	@echo "  make cdc MODULE=ethmac_ahb              - CDC lint ethmac_ahb (3 clock domains)"
