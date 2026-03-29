#!/bin/bash
# Run all cocotb test suites
# Usage: ./run_all.sh [test_dir]
# If test_dir is specified, only that suite runs.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

SUITES=(
    "rmii_to_mii"
    "ahb3lite_to_wb"
    "wb_to_ahb3lite"
    "ethmac_ahb"
)

if [ -n "$1" ]; then
    SUITES=("$1")
fi

PASS=0
FAIL=0

for suite in "${SUITES[@]}"; do
    echo "============================================"
    echo "  Running: $suite"
    echo "============================================"
    if make -C "$SCRIPT_DIR/$suite" 2>&1; then
        echo "  PASSED: $suite"
        ((PASS++))
    else
        echo "  FAILED: $suite"
        ((FAIL++))
    fi
    echo ""
done

echo "============================================"
echo "  Results: $PASS passed, $FAIL failed"
echo "============================================"

exit $FAIL
