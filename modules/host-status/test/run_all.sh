#!/usr/bin/env bash
set -uo pipefail  # Note: no -e, so all tests run even if some fail

# Test runner - executes all test files

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "======================================"
echo "Running host-status test suite"
echo "======================================"
echo ""

FAILED=0

# Run each test file
for test_file in "$SCRIPT_DIR"/test_*.sh; do
  if [[ -f "$test_file" ]]; then
    echo "Running $(basename "$test_file")..."
    echo "--------------------------------------"
    
    if bash "$test_file"; then
      echo "✓ $(basename "$test_file") passed"
    else
      echo "✗ $(basename "$test_file") failed"
      ((FAILED++))
    fi
    
    echo ""
  fi
done

echo "======================================"
if [[ $FAILED -eq 0 ]]; then
  echo "✓ All test suites passed!"
  exit 0
else
  echo "✗ $FAILED test suite(s) failed"
  exit 1
fi
