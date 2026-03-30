#!/bin/bash
# Run all UVM test suites
# Usage: ./run_all.sh [suite_dir]
# If suite_dir is specified, only that suite runs.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Suite name → space-separated list of UVM test names
declare -A SUITE_TESTS
SUITE_TESTS[ahb3lite_to_wb]="ahb_wb_bridge_single_test ahb_wb_bridge_error_test ahb_wb_bridge_wait_state_test ahb_wb_bridge_random_test"
SUITE_TESTS[wb_to_ahb3lite]="wb_ahb_bridge_single_test wb_ahb_bridge_burst_test wb_ahb_bridge_error_test wb_ahb_bridge_wait_state_test wb_ahb_bridge_random_test"
SUITE_TESTS[rmii_to_mii]="rmii_mii_tx_test rmii_mii_rx_test rmii_mii_collision_test rmii_mii_random_test"

SUITES=(ahb3lite_to_wb wb_to_ahb3lite rmii_to_mii)

if [ -n "$1" ]; then
    SUITES=("$1")
fi

PASS=0
FAIL=0

for suite in "${SUITES[@]}"; do
    suite_dir="$SCRIPT_DIR/$suite"
    echo "============================================"
    echo "  Compiling: $suite"
    echo "============================================"
    if ! make -C "$suite_dir" compile 2>&1; then
        echo "  FAILED: $suite (compilation)"
        ((FAIL++))
        continue
    fi

    for test in ${SUITE_TESTS[$suite]}; do
        echo "--------------------------------------------"
        echo "  Running: $suite / $test"
        echo "--------------------------------------------"
        if make -C "$suite_dir" run TEST="$test" SEED=1 2>&1; then
            echo "  PASSED: $test"
            ((PASS++))
        else
            echo "  FAILED: $test"
            ((FAIL++))
        fi
    done
    echo ""
done

echo "============================================"
echo "  UVM Results: $PASS passed, $FAIL failed"
echo "============================================"

exit $FAIL
