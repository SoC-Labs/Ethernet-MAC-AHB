export ETHMAC_AHB_HOME := $(realpath $(dir $(lastword $(MAKEFILE_LIST)))/..)
export ETHMAC_IP_DIR   ?= /research/AAA/ip_library/OpenCores-EthMAC

# ── Target module (override on command line: make MODULE=wb_to_ahb3lite) ──
MODULE ?= wb_to_ahb3lite

# ── All lintable modules ─────────────────────────────────────────
# Bridge modules (no external IP dependencies)
BRIDGE_MODULES = wb_to_ahb3lite ahb3lite_to_wb rmii_to_mii

# Top-level modules requiring Ethernet MAC IP
ETHMAC_MODULES = ethmac_ahb ethmac_ahb_rmii

# ── Paths ─────────────────────────────────────────────────────────
FLIST   = $(ETHMAC_AHB_HOME)/flist/$(MODULE).flist
LOGFILE = $(MODULE)_hal.log
XMLFILE = $(MODULE)_hal.xml
RPTFILE = $(MODULE)_hal_report.txt

# ── HAL flags ─────────────────────────────────────────────────────
HAL       = hal
HAL_FLAGS = -64bit \
            -sv \
            -top $(MODULE) \
            -check ALL_RTL \
            -logfile $(LOGFILE) \
            -xmlfile $(XMLFILE) \
            -messages \
            -stats \
            -lintpragma

# Add any waivers from the rule file
HAL_FLAGS += -file $(ETHMAC_AHB_HOME)/lint/hal.tcl

.PHONY: lint lint-synth lint-all lint-bridges lint-each report gui clean help

# Default target: RTL lint checks for a single module
lint:
	$(HAL) $(HAL_FLAGS) -f $(FLIST)

# Synthesizability-focused checks only
lint-synth:
	$(HAL) $(HAL_FLAGS) -nohalcheck -f $(FLIST)

# All checks (RTL + structural + synthesizability) for a single module
lint-all:
	$(HAL) $(HAL_FLAGS) -check ALL -f $(FLIST)

# Lint all bridge modules (no Ethernet MAC dependency)
lint-bridges:
	@for mod in $(BRIDGE_MODULES); do \
		echo "══════════════════════════════════════════════════════════"; \
		echo "  Linting: $$mod"; \
		echo "══════════════════════════════════════════════════════════"; \
		$(MAKE) lint MODULE=$$mod || exit 1; \
	done

# Lint every module individually (bridges + top-level)
lint-each:
	@for mod in $(BRIDGE_MODULES) $(ETHMAC_MODULES); do \
		echo "══════════════════════════════════════════════════════════"; \
		echo "  Linting: $$mod"; \
		echo "══════════════════════════════════════════════════════════"; \
		$(MAKE) lint MODULE=$$mod || exit 1; \
	done

# Generate a warnings/errors report from the lint log
report: $(LOGFILE)
	@{ \
	echo "══════════════════════════════════════════════════════════"; \
	echo "  HAL Lint Report: $(MODULE)"; \
	echo "  Source: $(LOGFILE)"; \
	echo "══════════════════════════════════════════════════════════"; \
	echo ""; \
	echo "── Summary ─────────────────────────────────────────────"; \
	grep -E 'Total (errors|warnings)' $(LOGFILE) || true; \
	echo ""; \
	echo "── Errors (Bridge RTL) ───────────────────────────────────"; \
	grep '\*E' $(LOGFILE) | grep -v 'OpenCores' | grep -v 'eth_' || echo "  (none)"; \
	echo ""; \
	echo "── Warnings (Bridge RTL) ─────────────────────────────────"; \
	grep '\*W' $(LOGFILE) | grep -v 'OpenCores' | grep -v 'eth_' | grep -v 'xmelab' || echo "  (none)"; \
	echo ""; \
	echo "── Warning Breakdown (Bridge RTL) ────────────────────────"; \
	grep '\*W' $(LOGFILE) | grep -v 'OpenCores' | grep -v 'eth_' | grep -v 'xmelab' \
	  | sed 's/.*\*W,\([A-Z]*\).*/\1/' | sort | uniq -c | sort -rn || true; \
	echo ""; \
	echo "── Errors (Ethernet MAC IP) ──────────────────────────────"; \
	grep '\*E' $(LOGFILE) | grep -E 'eth_|OpenCores' || echo "  (none)"; \
	echo ""; \
	echo "── Warnings (Ethernet MAC IP) ────────────────────────────"; \
	ethmac_count=$$(grep '\*W' $(LOGFILE) | grep -cE 'eth_|OpenCores' 2>/dev/null || echo 0); \
	echo "  $$ethmac_count warnings (suppressed — third-party IP)"; \
	echo ""; \
	} | tee $(RPTFILE)
	@echo "Report saved to: $(RPTFILE)"

# Open results in Cadence report browser
gui:
	$(HAL) $(HAL_FLAGS) -gui -f $(FLIST)

clean:
	rm -rf *_hal.log *_hal.xml *_hal_report.txt hal.design_facts hal.log INCA_libs xcelium.d *.log.bak .hal-irun.history

help:
	@echo "Ethernet MAC AHB HAL Lint Flow"
	@echo ""
	@echo "Usage:"
	@echo "  make lint                      - Lint single module (default: $(MODULE))"
	@echo "  make lint MODULE=<name>        - Lint a specific module"
	@echo "  make lint-synth                - Synthesizability checks only"
	@echo "  make lint-all                  - All checks (RTL + structural + synth)"
	@echo "  make lint-bridges              - Lint all bridge modules"
	@echo "  make lint-each                 - Lint every module (needs ETHMAC_IP_DIR for some)"
	@echo "  make report                    - Extract warnings/errors from lint log"
	@echo "  make gui                       - Open report browser"
	@echo "  make clean                     - Remove generated files"
	@echo ""
	@echo "Bridge modules (no external deps):"
	@echo "  $(BRIDGE_MODULES)"
	@echo ""
	@echo "Ethernet MAC-dependent modules:"
	@echo "  $(ETHMAC_MODULES)"
	@echo ""
	@echo "ETHMAC_IP_DIR: $(ETHMAC_IP_DIR)"
	@echo ""
	@echo "Examples:"
	@echo "  make lint MODULE=wb_to_ahb3lite"
	@echo "  make lint-bridges"
	@echo "  make lint report               - Lint then show warnings/errors"
