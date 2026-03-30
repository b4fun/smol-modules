#!/usr/bin/env bash
set -uo pipefail  # Note: no -e, so tests continue after failures

# Test configuration loading

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULE_DIR="$(dirname "$SCRIPT_DIR")"

source "$SCRIPT_DIR/helpers.sh"
source "$MODULE_DIR/lib/log.sh"
source "$MODULE_DIR/lib/config.sh"

echo "Testing configuration loading..."

# Test 1: Load config without file (should use defaults)
config_load
assert_eq "$_HOSTSTATUS_DEFAULTS_PUSH_INTERVAL" "$(config_get_setting push_interval)" "Default push interval"
assert_eq "$_HOSTSTATUS_DEFAULTS_PULL_PORT" "$(config_get_setting pull_port)" "Default pull port"
assert_eq "false" "$(config_get_setting push_enabled)" "Default push disabled"
assert_eq "true" "$(config_get_setting pull_enabled)" "Default pull enabled"

# Test 2: Create temporary config and load it
TEMP_CONFIG="$(mktemp)"
trap "rm -f '$TEMP_CONFIG'" EXIT

cat > "$TEMP_CONFIG" << 'EOF'
[settings]
hostname = "test-host"
push_enabled = true
push_url = "https://test.example.com/status"
push_interval = 60
pull_enabled = false
pull_port = 9090
log_level = "DEBUG"

[[providers]]
name = "test-provider"
command = "/usr/bin/test"
enabled = true

[[providers]]
name = "disabled-provider"
command = "/usr/bin/disabled"
enabled = false
EOF

export HOST_STATUS_CONFIG="$TEMP_CONFIG"
config_load

assert_eq "test-host" "$(config_get_setting hostname)" "Custom hostname"
assert_eq "true" "$(config_get_setting push_enabled)" "Push enabled from config"
assert_eq "https://test.example.com/status" "$(config_get_setting push_url)" "Push URL from config"
assert_eq "60" "$(config_get_setting push_interval)" "Custom push interval"
assert_eq "false" "$(config_get_setting pull_enabled)" "Pull disabled from config"
assert_eq "9090" "$(config_get_setting pull_port)" "Custom pull port"
assert_eq "DEBUG" "$(config_get_setting log_level)" "Custom log level"

# Test 3: Check provider count
provider_count="$(config_get_provider_count)"
assert_eq "2" "$provider_count" "Provider count"

# Test 4: Verify providers can be retrieved
providers="$(config_get_providers)"
provider_names="$(echo "$providers" | jq -r '.name')"
assert_contains "$provider_names" "test-provider" "First provider name"
assert_contains "$provider_names" "disabled-provider" "Second provider name"

test_summary
