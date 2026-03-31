#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source ./helpers.sh
TEST_NAME="completion_update"
echo "Running completion update tests..."

# --- Test: report_completion updates tracking comment ---
setup_test_env; write_test_config; config_load; log_init
task_dir="${TEST_WORKSPACE_DIR}/test-org-test-repo-issue-42"
mkdir -p "$task_dir"

# Simulate a completed task
write_result_json "$task_dir" "done" "Feature implemented successfully"

# Test that completion report contains all required elements
output="$(report_completion "test-org/test-repo" 42 "test-org-test-repo-issue-42" "$task_dir/result.json" 2>&1)"

assert_contains "$output" "<!-- gh-pm:test-org-test-repo-issue-42 -->" "completion has marker"
assert_contains "$output" "Task Completed" "completion has title"
assert_contains "$output" "✅ Completed" "completion has success icon"
assert_contains "$output" "Finished" "completion has finished timestamp"
assert_contains "$output" "Feature implemented successfully" "completion has summary"
teardown_test_env

# --- Test: report_completion with failure state ---
setup_test_env; write_test_config; config_load; log_init
task_dir="${TEST_WORKSPACE_DIR}/test-org-test-repo-issue-99"
mkdir -p "$task_dir"

cat > "$task_dir/result.json" <<'JSON'
{
  "state": "failed",
  "summary": "Task failed due to missing dependencies",
  "error": "Module 'xyz' not found",
  "completed_at": "2024-01-01T00:00:00Z"
}
JSON

output="$(report_completion "test-org/test-repo" 99 "test-org-test-repo-issue-99" "$task_dir/result.json" 2>&1)"

assert_contains "$output" "Task Failed" "failed completion has title"
assert_contains "$output" "❌ Failed" "failed completion has failure icon"
assert_contains "$output" "Task failed due to missing dependencies" "failed completion has summary"
assert_contains "$output" "Module 'xyz' not found" "failed completion has error"
teardown_test_env

# --- Test: monitor_inflight detects completion and reports ---
setup_test_env; write_test_config; config_load; log_init

task_dir="${TEST_WORKSPACE_DIR}/test-org-test-repo-issue-50"
mkdir -p "$task_dir"

# Create task.json
cat > "$task_dir/task.json" <<'JSON'
{
  "id": "test-org-test-repo-issue-50",
  "source": {"type": "issue", "repo": "test-org/test-repo", "number": 50, "url": "https://github.com/test-org/test-repo/issues/50"},
  "title": "Test issue",
  "body": "Test body",
  "analysis": "Test analysis",
  "policy": "",
  "created_at": "2024-01-01T00:00:00Z"
}
JSON

# Create dispatch.json (simulate dispatched task)
cat > "$task_dir/dispatch.json" <<'JSON'
{
  "pid": 999999,
  "dispatched_at": "2024-01-01T00:00:00Z",
  "attempt": 1,
  "timeout_seconds": 3600
}
JSON

# Create result.json (simulate completion)
write_result_json "$task_dir" "done" "All checks passed"

# dispatch_check_status should return "done"
status="$(dispatch_check_status "$task_dir")"
assert_eq "done" "$status" "status is done when result.json exists"

teardown_test_env

# --- Test: Tracking marker is unique per task ---
setup_test_env; write_test_config; config_load; log_init

task_dir_1="${TEST_WORKSPACE_DIR}/test-org-test-repo-issue-10"
task_dir_2="${TEST_WORKSPACE_DIR}/test-org-test-repo-issue-20"
mkdir -p "$task_dir_1" "$task_dir_2"

write_result_json "$task_dir_1" "done" "Task 10 complete"
write_result_json "$task_dir_2" "done" "Task 20 complete"

output_1="$(report_completion "test-org/test-repo" 10 "test-org-test-repo-issue-10" "$task_dir_1/result.json" 2>&1)"
output_2="$(report_completion "test-org/test-repo" 20 "test-org-test-repo-issue-20" "$task_dir_2/result.json" 2>&1)"

assert_contains "$output_1" "gh-pm:test-org-test-repo-issue-10" "task 10 has correct marker"
assert_contains "$output_2" "gh-pm:test-org-test-repo-issue-20" "task 20 has correct marker"

# Ensure markers are different
if echo "$output_1" | grep -q "gh-pm:test-org-test-repo-issue-20"; then
  echo "[0;31m✗[0m task markers not unique" >&2
  exit 1
fi

echo "[0;32m✓[0m task markers are unique"

teardown_test_env

print_test_summary
