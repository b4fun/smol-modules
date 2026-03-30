#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source ./helpers.sh
TEST_NAME="dispatch"
echo "Running dispatch tests..."

# --- Test: dispatch_task writes dispatch.json in dry-run ---
setup_test_env; write_test_config; config_load; log_init
task_dir="${TEST_WORKSPACE_DIR}/test-issue-1"
mkdir -p "$task_dir"
write_task_json "$task_dir" "test-org/test-repo" 1
dispatch_task "$task_dir" 2>/dev/null
assert_file_exists "$task_dir/dispatch.json" "dispatch.json created"
pid="$(jq -r '.pid' "$task_dir/dispatch.json")"
assert_eq "0" "$pid" "dry-run PID is 0"
attempt="$(jq -r '.attempt' "$task_dir/dispatch.json")"
assert_eq "1" "$attempt" "attempt is 1"
assert_contains "$(jq -r '.timeout_seconds' "$task_dir/dispatch.json")" "1800" "timeout from config"
teardown_test_env

# --- Test: dispatch_check_status = done ---
setup_test_env; write_test_config; config_load; log_init
task_dir="${TEST_WORKSPACE_DIR}/test-issue-2"
mkdir -p "$task_dir"
write_task_json "$task_dir" "test-org/test-repo" 2
write_dispatch_json "$task_dir" 0 1 3600
write_result_json "$task_dir" "done" "All good"
status="$(dispatch_check_status "$task_dir")"
assert_eq "done" "$status" "status is done when result.json state=done"
teardown_test_env

# --- Test: dispatch_check_status = failed ---
setup_test_env; write_test_config; config_load; log_init
task_dir="${TEST_WORKSPACE_DIR}/test-issue-3"
mkdir -p "$task_dir"
write_task_json "$task_dir" "test-org/test-repo" 3
write_dispatch_json "$task_dir" 0 1 3600
write_result_json "$task_dir" "failed" "Something broke"
status="$(dispatch_check_status "$task_dir")"
assert_eq "failed" "$status" "status is failed when result.json state=failed"
teardown_test_env

# --- Test: dispatch_check_status = failed when process dead, no result ---
setup_test_env; write_test_config; config_load; log_init
task_dir="${TEST_WORKSPACE_DIR}/test-issue-4"
mkdir -p "$task_dir"
write_task_json "$task_dir" "test-org/test-repo" 4
write_dispatch_json "$task_dir" 99999 1 3600  # PID that doesn't exist
status="$(dispatch_check_status "$task_dir")"
assert_eq "failed" "$status" "dead process without result = failed"
teardown_test_env

# --- Test: dispatch_check_status = timeout ---
setup_test_env; write_test_config; config_load; log_init
task_dir="${TEST_WORKSPACE_DIR}/test-issue-5"
mkdir -p "$task_dir"
write_task_json "$task_dir" "test-org/test-repo" 5
# Write dispatch.json with a time far in the past and tiny timeout
cat > "$task_dir/dispatch.json" <<EOF
{"pid":0,"dispatched_at":"2020-01-01T00:00:00Z","attempt":1,"timeout_seconds":1}
EOF
status="$(dispatch_check_status "$task_dir")"
assert_eq "timeout" "$status" "expired dispatch = timeout"
teardown_test_env

# --- Test: dispatch_is_process_alive ---
setup_test_env; write_test_config; config_load; log_init
export GH_PM_DRY_RUN="0"  # need real process check
dispatch_is_process_alive 0 && r=alive || r=dead
assert_eq "dead" "$r" "PID 0 is not alive"
dispatch_is_process_alive $$ && r=alive || r=dead
assert_eq "alive" "$r" "own PID is alive"
export GH_PM_DRY_RUN="1"
teardown_test_env

print_test_summary
