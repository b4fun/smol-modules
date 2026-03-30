#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source ./helpers.sh
TEST_NAME="report"
echo "Running report tests..."

# --- Test: report_dispatch includes marker tag ---
setup_test_env; write_test_config; config_load; log_init
output="$(report_dispatch "test-org/test-repo" 42 "test-org-test-repo-issue-42" 2>&1)"
assert_contains "$output" "<!-- gh-pm:test-org-test-repo-issue-42 -->" "dispatch comment has marker"
assert_contains "$output" "Task Dispatched" "dispatch comment has title"
assert_contains "$output" "test-org-test-repo-issue-42" "dispatch comment has task ID"
teardown_test_env

# --- Test: report_completion includes summary ---
setup_test_env; write_test_config; config_load; log_init
task_dir="${TEST_WORKSPACE_DIR}/test-org-test-repo-issue-42"
mkdir -p "$task_dir"
write_result_json "$task_dir" "done" "All tests passed"
# In dry-run, gh_find_tracking_comment returns "", so report_completion falls back to post
output="$(report_completion "test-org/test-repo" 42 "test-org-test-repo-issue-42" "$task_dir/result.json" 2>&1)"
assert_contains "$output" "All tests passed" "completion has summary"
assert_contains "$output" "Completed" "completion shows completed status"
assert_contains "$output" "<!-- gh-pm:test-org-test-repo-issue-42 -->" "completion has marker"
teardown_test_env

# --- Test: report_completion with failed state ---
setup_test_env; write_test_config; config_load; log_init
task_dir="${TEST_WORKSPACE_DIR}/test-org-test-repo-issue-99"
mkdir -p "$task_dir"
cat > "$task_dir/result.json" <<'EOF'
{"state":"failed","summary":"Build broke","error":"exit code 1","completed_at":"2024-01-01T00:00:00Z"}
EOF
output="$(report_completion "test-org/test-repo" 99 "test-org-test-repo-issue-99" "$task_dir/result.json" 2>&1)"
assert_contains "$output" "Failed" "failed completion shows Failed"
assert_contains "$output" "exit code 1" "failed completion shows error"
teardown_test_env

print_test_summary
