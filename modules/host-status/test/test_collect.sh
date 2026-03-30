#!/usr/bin/env bash
set -uo pipefail  # Note: no -e, so tests continue after failures

# Test provider execution and collection

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULE_DIR="$(dirname "$SCRIPT_DIR")"

source "$SCRIPT_DIR/helpers.sh"
source "$MODULE_DIR/lib/log.sh"
source "$MODULE_DIR/lib/config.sh"
source "$MODULE_DIR/lib/collect.sh"

echo "Testing provider execution and collection..."

# Create a temporary directory for mock providers
TEMP_DIR="$(mktemp -d)"
trap "rm -rf '$TEMP_DIR'" EXIT

# Test 1: Create a successful mock provider
MOCK_PROVIDER="$TEMP_DIR/mock-success"
cat > "$MOCK_PROVIDER" << 'EOF'
#!/usr/bin/env bash
echo '{"name":"mock","status":"ok","value":42,"unit":"test","message":"Test successful"}'
EOF
chmod +x "$MOCK_PROVIDER"

# Initialize config with mock provider
TEMP_CONFIG="$TEMP_DIR/config.toml"
cat > "$TEMP_CONFIG" << EOF
[settings]
collection_timeout = 5

[[providers]]
name = "mock"
command = "$MOCK_PROVIDER"
enabled = true
EOF

export HOST_STATUS_CONFIG="$TEMP_CONFIG"
config_load
log_init

# Test provider execution
echo "Testing successful provider..."
provider_json="$(config_get_providers | head -1)"
result="$(execute_provider "$provider_json")"
assert_json_valid "$result" "Provider returns valid JSON"
assert_contains "$result" '"name":"mock"' "Result contains provider name"
assert_contains "$result" '"status":"ok"' "Result contains status"

# Test 2: Create a failing mock provider
MOCK_FAIL="$TEMP_DIR/mock-fail"
cat > "$MOCK_FAIL" << 'EOF'
#!/usr/bin/env bash
exit 1
EOF
chmod +x "$MOCK_FAIL"

echo "Testing failing provider..."
fail_provider_json='{"name":"fail","command":"'"$MOCK_FAIL"'","enabled":true}'
fail_result="$(execute_provider "$fail_provider_json")"
assert_json_valid "$fail_result" "Failing provider returns valid JSON"
assert_contains "$fail_result" '"status":"error"' "Failing provider has error status"

# Test 3: Create a timeout mock provider
MOCK_TIMEOUT="$TEMP_DIR/mock-timeout"
cat > "$MOCK_TIMEOUT" << 'EOF'
#!/usr/bin/env bash
sleep 30
EOF
chmod +x "$MOCK_TIMEOUT"

echo "Testing timeout provider..."
timeout_provider_json='{"name":"timeout","command":"'"$MOCK_TIMEOUT"'","enabled":true}'
timeout_result="$(execute_provider "$timeout_provider_json")"
assert_json_valid "$timeout_result" "Timeout provider returns valid JSON"
assert_contains "$timeout_result" '"status":"unknown"' "Timeout provider has unknown status"
assert_contains "$timeout_result" 'timed out' "Timeout message present"

# Test 4: Test disabled provider
echo "Testing disabled provider..."
disabled_provider_json='{"name":"disabled","command":"'"$MOCK_PROVIDER"'","enabled":false}'
disabled_result="$(execute_provider "$disabled_provider_json")"
assert_eq "" "$disabled_result" "Disabled provider returns empty result"

test_summary
