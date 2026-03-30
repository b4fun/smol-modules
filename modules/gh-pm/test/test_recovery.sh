#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source ./helpers.sh
TEST_NAME="recovery"
echo "Running recovery tests..."

# --- Test: completed task gets reported ---
setup_test_env; write_test_config; config_load; log_init
task_dir="${TEST_WORKSPACE_DIR}/test-org-test-repo-issue-10"
write_task_json "$task_dir" "test-org/test-repo" 10
write_dispatch_json "$task_dir" 0 1 3600
write_result_json "$task_dir" "done" "Task finished"
output="$(recovery_run 2>&1)"
assert_contains "$output" "Recovered 1 task" "recovery found 1 task"
teardown_test_env

# --- Test: undispatched task gets dispatched ---
setup_test_env; write_test_config; config_load; log_init
task_dir="${TEST_WORKSPACE_DIR}/test-org-test-repo-issue-20"
write_task_json "$task_dir" "test-org/test-repo" 20
# No dispatch.json - should be dispatched
output="$(recovery_run 2>&1)"
assert_contains "$output" "never dispatched" "recovery detected undispatched task"
assert_file_exists "$task_dir/dispatch.json" "dispatch.json created by recovery"
teardown_test_env

# --- Test: in-flight with dead PID gets timeout ---
setup_test_env; write_test_config; config_load; log_init
task_dir="${TEST_WORKSPACE_DIR}/test-org-test-repo-issue-30"
write_task_json "$task_dir" "test-org/test-repo" 30
write_dispatch_json "$task_dir" 99999 1 3600  # PID that doesn't exist
output="$(recovery_run 2>&1)"
assert_contains "$output" "dead" "recovery detected dead process"
teardown_test_env

# --- Test: empty workspace is fine ---
setup_test_env; write_test_config; config_load; log_init
recovery_run 2>/dev/null
assert_eq "0" "$?" "empty workspace recovery succeeds"
teardown_test_env

print_test_summary
