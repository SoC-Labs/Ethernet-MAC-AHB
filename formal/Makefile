# Top-level VC Formal X-propagation regression Makefile
# Usage:
#   make regression              Run xprop on all modules
#   make ethmac_ahb              Run xprop on a single module
#   make clean                   Clean all modules

# OpenCores-dependent modules
ETHMAC_ENVS = ethmac_ahb ha1588_ahb ha1588_apb

ENVS = $(ETHMAC_ENVS)

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
.PHONY: regression regression-summary

regression: $(ENVS) regression-summary

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
	@echo "  make ethmac_ahb              Run xprop on a single module"
	@echo "  make clean                   Remove all generated files"
	@echo ""
	@echo "Modules:"
	@echo "  $(ENVS)"
	@echo ""
	@echo "Note: Bridge formal tests are in the amba_wb_bridges/ submodule."
