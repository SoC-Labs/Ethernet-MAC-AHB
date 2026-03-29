# Top-level VC Formal X-propagation regression Makefile
# Usage:
#   make regression              Run xprop on all modules
#   make ahb3lite_to_wb          Run xprop on a single module
#   make standalone              Run only standalone modules (no OpenCores IP)
#   make clean                   Clean all modules

# Standalone modules (no OpenCores dependency)
STANDALONE_ENVS = ahb3lite_to_wb wb_to_ahb3lite rmii_to_mii

# OpenCores-dependent modules
ETHMAC_ENVS = ethmac_ahb

ENVS = $(STANDALONE_ENVS) $(ETHMAC_ENVS)

# ── Per-module targets ─────────────────────────────────────────────────────
define run_env
.PHONY: $(1)
$(1):
	@echo "========================================"
	@echo " VC Formal xprop: $(1)"
	@echo "========================================"
	@$$(MAKE) -C $(1) clean > /dev/null 2>&1; \
	 $$(MAKE) -C $(1) xprop 2>&1 | tee $(1)/run.log; \
	 if grep -q "FAIL\|ERROR" $(1)/run.log 2>/dev/null; then \
	   echo "  >> $(1): FAIL"; \
	   echo "FAIL" > $(1)/.result; \
	 else \
	   echo "  >> $(1): PASS"; \
	   echo "PASS" > $(1)/.result; \
	 fi
	@echo ""
endef

$(foreach env,$(ENVS),$(eval $(call run_env,$(env))))

# ── Regression targets ─────────────────────────────────────────────────────
.PHONY: regression standalone regression-summary

regression: $(ENVS) regression-summary

standalone: $(STANDALONE_ENVS) regression-summary-standalone

regression-summary:
	@echo "========================================"
	@echo " Formal Regression Summary"
	@echo "========================================"
	@pass=0; fail=0; \
	for env in $(ENVS); do \
	  result=$$(cat $$env/.result 2>/dev/null || echo "FAIL"); \
	  printf "  %-30s %s\n" "$$env" "$$result"; \
	  if [ "$$result" = "PASS" ]; then pass=$$((pass + 1)); else fail=$$((fail + 1)); fi; \
	done; \
	echo "----------------------------------------"; \
	echo "  PASS=$$pass  FAIL=$$fail  TOTAL=$$(( pass + fail ))"; \
	echo "========================================"; \
	[ "$$fail" -eq 0 ]

regression-summary-standalone:
	@echo "========================================"
	@echo " Formal Regression Summary (standalone)"
	@echo "========================================"
	@pass=0; fail=0; \
	for env in $(STANDALONE_ENVS); do \
	  result=$$(cat $$env/.result 2>/dev/null || echo "FAIL"); \
	  printf "  %-30s %s\n" "$$env" "$$result"; \
	  if [ "$$result" = "PASS" ]; then pass=$$((pass + 1)); else fail=$$((fail + 1)); fi; \
	done; \
	echo "----------------------------------------"; \
	echo "  PASS=$$pass  FAIL=$$fail  TOTAL=$$(( pass + fail ))"; \
	echo "========================================"; \
	[ "$$fail" -eq 0 ]

# ── Clean ──────────────────────────────────────────────────────────────────
.PHONY: clean
clean:
	@for env in $(ENVS); do \
	  $(MAKE) -C $$env clean > /dev/null 2>&1; \
	  rm -f $$env/run.log $$env/.result; \
	done
	@echo "All formal environments cleaned"

# ── Help ───────────────────────────────────────────────────────────────────
.PHONY: help
help:
	@echo "Ethernet MAC AHB VC Formal X-propagation Flow"
	@echo ""
	@echo "Usage:"
	@echo "  make regression              Run xprop on all modules"
	@echo "  make standalone              Run standalone modules only (no OpenCores IP)"
	@echo "  make ahb3lite_to_wb          Run xprop on a single module"
	@echo "  make clean                   Remove all generated files"
	@echo ""
	@echo "Standalone modules (no OpenCores dependency):"
	@echo "  $(STANDALONE_ENVS)"
	@echo ""
	@echo "OpenCores-dependent modules:"
	@echo "  $(ETHMAC_ENVS)"
