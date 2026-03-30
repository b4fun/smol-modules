#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

PASS=0
FAIL=0

for test_file in test_*.sh; do
  echo "=== Running $test_file ==="
  if bash "$test_file"; then
    (( PASS++ )) || true
  else
    (( FAIL++ )) || true
  fi
  echo ""
done

echo "============================="
echo "Total: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
