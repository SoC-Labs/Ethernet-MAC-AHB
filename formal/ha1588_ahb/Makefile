# VC Formal X-propagation flow for ha1588_ahb

export ETHMAC_AHB_HOME := $(realpath $(dir $(lastword $(MAKEFILE_LIST)))/../..)
export HA1588_IP_DIR   ?= /research/AAA/ip_library/OpenCores-HA1588

MODULE  = ha1588_ahb
SCRIPT  = xprop.tcl
WORKDIR = work
LOGFILE = xprop.log

VC_FORMAL      = vc_formal
VC_FORMAL_FLAGS = -f $(ETHMAC_AHB_HOME)/flist/$(MODULE).flist

.PHONY: xprop clean gui help

xprop:
	$(VC_FORMAL) -sverilog $(VC_FORMAL_FLAGS) \
		-tcl $(SCRIPT) \
		-work $(WORKDIR) \
		-l $(LOGFILE)
	@if grep -q "FAIL\|ERROR" $(LOGFILE) 2>/dev/null; then \
		echo "  >> $(MODULE): FAIL"; \
	else \
		echo "  >> $(MODULE): PASS"; \
	fi

gui:
	$(VC_FORMAL) -sverilog $(VC_FORMAL_FLAGS) \
		-work $(WORKDIR) \
		-gui

clean:
	rm -rf $(WORKDIR) $(LOGFILE) xprop_results.rpt xprop_summary.rpt \
		vc_formal.fsdb vc_formal.log novas.* verdi* *.vpd
	@echo "$(MODULE) formal cleaned"

help:
	@echo "VC Formal X-propagation: $(MODULE)"
	@echo ""
	@echo "  make xprop   - Run X-propagation checks"
	@echo "  make gui     - Open VC Formal GUI"
	@echo "  make clean   - Remove generated files"
