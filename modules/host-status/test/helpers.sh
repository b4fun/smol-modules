#!/usr/bin/env bash
# test/helpers.sh — Common test utilities

declare -g -i TEST_COUNT=0
declare -g -i TEST_PASS=0
declare -g -i TEST_FAIL=0

# assert_eq EXPECTED ACTUAL [MESSAGE]
assert_eq() {
  local expected="$1"
  local actual="$2"
  local message="${3:-Assertion failed}"
  
  ((TEST_COUNT++))
  
  if [[ "$expected" == "$actual" ]]; then
    ((TEST_PASS++))
    echo "  ✓ $message"
    return 0
  else
    ((TEST_FAIL++))
    echo "  ✗ $message"
    echo "    Expected: $expected"
    echo "    Actual:   $actual"
    return 1
  fi
}

# assert_contains HAYSTACK NEEDLE [MESSAGE]
assert_contains() {
  local haystack="$1"
  local needle="$2"
  local message="${3:-Should contain substring}"
  
  ((TEST_COUNT++))
  
  if [[ "$haystack" == *"$needle"* ]]; then
    ((TEST_PASS++))
    echo "  ✓ $message"
    return 0
  else
    ((TEST_FAIL++))
    echo "  ✗ $message"
    echo "    Haystack: $haystack"
    echo "    Needle:   $needle"
    return 1
  fi
}

# assert_json_valid JSON [MESSAGE]
assert_json_valid() {
  local json="$1"
  local message="${2:-JSON should be valid}"
  
  ((TEST_COUNT++))
  
  if echo "$json" | jq empty 2>/dev/null; then
    ((TEST_PASS++))
    echo "  ✓ $message"
    return 0
  else
    ((TEST_FAIL++))
    echo "  ✗ $message"
    echo "    Invalid JSON: $json"
    return 1
  fi
}

# test_summary
test_summary() {
  echo ""
  echo "=========================================="
  echo "Test Summary:"
  echo "  Total:  $TEST_COUNT"
  echo "  Passed: $TEST_PASS"
  echo "  Failed: $TEST_FAIL"
  echo "=========================================="
  
  if [[ $TEST_FAIL -gt 0 ]]; then
    return 1
  else
    return 0
  fi
}
