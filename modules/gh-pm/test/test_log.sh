#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source ./helpers.sh
TEST_NAME="log"
echo "Running log tests..."

# --- Test: log format ---
setup_test_env; write_test_config; config_load; log_init
output="$(log_info "poll" "test message" 2>&1)"
assert_contains "$output" "INFO" "log line has level"
assert_contains "$output" "poll" "log line has component"
assert_contains "$output" "test message" "log line has message"
assert_contains "$output" "T" "log line has ISO timestamp"
teardown_test_env

# --- Test: DEBUG hidden at INFO level ---
setup_test_env; write_minimal_config; config_load; log_init
# minimal config doesn't set log_level, so it's INFO by default
# But dry-run forces DEBUG. Let's override:
export GH_PM_DRY_RUN="0"
log_init  # re-init without dry-run
output="$(log_debug "poll" "should be hidden" 2>&1)"
assert_eq "" "$output" "DEBUG hidden at INFO level"
output="$(log_info "poll" "should show" 2>&1)"
assert_contains "$output" "should show" "INFO shows at INFO level"
export GH_PM_DRY_RUN="1"
teardown_test_env

# --- Test: task log file ---
setup_test_env; write_test_config; config_load; log_init
log_task_init "test-org-repo-issue-1"
log_info "analyze" "task log entry" 2>/dev/null
assert_file_exists "${GH_PM_WORKSPACE}/test-org-repo-issue-1/gh-pm.log" "task log file created"
local_content="$(cat "${GH_PM_WORKSPACE}/test-org-repo-issue-1/gh-pm.log")"
assert_contains "$local_content" "task log entry" "task log has entry"
log_task_reset
teardown_test_env

# --- Test: log file output ---
setup_test_env
cat > "${TEST_CONFIG_FILE}" <<TOML
[settings]
repos = ["test-org/repo"]
log_level = "DEBUG"
log_file = "${TEST_TMP_DIR}/test.log"
workflow_command = "echo noop"

[profiles.default]
model = "gpt-4o"
api_url = "https://api.openai.com/v1"
TOML
config_load; log_init
log_info "main" "file log test" 2>/dev/null
assert_file_exists "${TEST_TMP_DIR}/test.log" "log file created"
local_content="$(cat "${TEST_TMP_DIR}/test.log")"
assert_contains "$local_content" "file log test" "log file has entry"
teardown_test_env

print_test_summary
