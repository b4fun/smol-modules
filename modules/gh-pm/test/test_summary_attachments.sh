#!/usr/bin/env bash
# Test summary attachments in GitHub comments

set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$TEST_DIR/helpers.sh"

TEST_NAME="Summary Attachments"

test_format_summary() {
  setup_test_env
  
  local content="This is a test summary"
  local result
  result="$(_format_summary "$content" 1000 "false" "Test")"
  
  assert_contains "$result" "This is a test summary" "Basic summary formatting works"
  
  teardown_test_env
}

test_format_summary_truncation() {
  setup_test_env
  
  local content="This is a very long summary that should be truncated"
  local result
  result="$(_format_summary "$content" 30 "false" "Test")"
  
  assert_contains "$result" "truncated" "Summary truncation works"
  
  teardown_test_env
}

test_format_summary_collapsible() {
  setup_test_env
  
  local content="This is a test summary"
  local result
  result="$(_format_summary "$content" 1000 "true" "Test Details")"
  
  assert_contains "$result" "<details>" "Contains details tag"
  assert_contains "$result" "<summary>Test Details</summary>" "Contains summary tag"
  assert_contains "$result" "</details>" "Contains closing details tag"
  
  teardown_test_env
}

test_config_defaults() {
  setup_test_env
  write_minimal_config
  config_load
  
  local attach_summaries
  attach_summaries="$(config_get_setting attach_summaries)"
  assert_eq "false" "$attach_summaries" "Default attach_summaries should be false"
  
  local summary_analyze
  summary_analyze="$(config_get_setting summary_analyze)"
  assert_eq "true" "$summary_analyze" "Default summary_analyze should be true"
  
  local summary_use_collapsible
  summary_use_collapsible="$(config_get_setting summary_use_collapsible)"
  assert_eq "true" "$summary_use_collapsible" "Default summary_use_collapsible should be true"
  
  teardown_test_env
}

test_config_parsing() {
  setup_test_env
  
  cat > "${TEST_CONFIG_FILE}" <<'EOF'
[settings]
repos = ["test/repo"]
workflow_command = "echo test"
attach_summaries = true
summary_analyze = false
summary_running = false
summary_format = "compact"
summary_use_collapsible = false
summary_max_length = 5000

[profiles.default]
model = "gpt-4o"
api_url = "https://api.openai.com/v1"
api_key_env = "OPENAI_API_KEY"
EOF

  config_load
  
  local attach_summaries summary_analyze summary_running summary_format summary_use_collapsible summary_max_length
  attach_summaries="$(config_get_setting attach_summaries)"
  summary_analyze="$(config_get_setting summary_analyze)"
  summary_running="$(config_get_setting summary_running)"
  summary_format="$(config_get_setting summary_format)"
  summary_use_collapsible="$(config_get_setting summary_use_collapsible)"
  summary_max_length="$(config_get_setting summary_max_length)"
  
  assert_eq "true" "$attach_summaries" "attach_summaries parsed correctly"
  assert_eq "false" "$summary_analyze" "summary_analyze parsed correctly"
  assert_eq "false" "$summary_running" "summary_running parsed correctly"
  assert_eq "compact" "$summary_format" "summary_format parsed correctly"
  assert_eq "false" "$summary_use_collapsible" "summary_use_collapsible parsed correctly"
  assert_eq "5000" "$summary_max_length" "summary_max_length parsed correctly"
  
  teardown_test_env
}

test_report_dispatch_with_summary() {
  setup_test_env
  
  # Create task.json with analysis
  local task_dir="${TEST_WORKSPACE_DIR}/test-repo-issue-1"
  mkdir -p "$task_dir"
  cat > "$task_dir/task.json" <<'EOF'
{
  "id": "test-repo-issue-1",
  "analysis": "## Test Analysis\n\nThis is a test analysis with multiple lines.\n\n- Task 1\n- Task 2\n- Task 3"
}
EOF

  # Create config with summaries enabled
  cat > "${TEST_CONFIG_FILE}" <<'EOF'
[settings]
repos = ["test/repo"]
workflow_command = "echo test"
attach_summaries = true
summary_analyze = true

[profiles.default]
model = "gpt-4o"
api_url = "https://api.openai.com/v1"
api_key_env = "OPENAI_API_KEY"
EOF

  config_load
  
  # Mock gh functions
  gh_find_tracking_comment() { echo ""; }
  gh_post_comment() {
    local body="$3"
    echo "$body" > "${TEST_TMP_DIR}/comment.txt"
  }
  export -f gh_find_tracking_comment gh_post_comment
  
  # Test report_dispatch with task_dir
  report_dispatch "test/repo" "1" "test-repo-issue-1" "$task_dir"
  
  # Verify comment includes analysis
  local comment_body
  comment_body="$(cat "${TEST_TMP_DIR}/comment.txt")"
  assert_contains "$comment_body" "Test Analysis" "Comment includes analysis"
  assert_contains "$comment_body" "Task 1" "Comment includes analysis details"
  
  teardown_test_env
}

test_report_status_with_summary() {
  setup_test_env
  
  # Create status.json with summary
  local task_dir="${TEST_WORKSPACE_DIR}/test-repo-issue-1"
  mkdir -p "$task_dir"
  cat > "$task_dir/status.json" <<'EOF'
{
  "message": "In progress",
  "summary": "## Execution Progress\n\nCompleted: Step 1, Step 2\nCurrent: Step 3\nRemaining: Step 4, Step 5"
}
EOF

  # Create config with summaries enabled
  cat > "${TEST_CONFIG_FILE}" <<'EOF'
[settings]
repos = ["test/repo"]
workflow_command = "echo test"
attach_summaries = true
summary_running = true

[profiles.default]
model = "gpt-4o"
api_url = "https://api.openai.com/v1"
api_key_env = "OPENAI_API_KEY"
EOF

  config_load
  
  # Mock gh functions
  gh_find_tracking_comment() { echo "123456"; }
  gh_update_comment() {
    local body="$3"
    echo "$body" > "${TEST_TMP_DIR}/comment.txt"
  }
  export -f gh_find_tracking_comment gh_update_comment
  
  # Test report_status with task_dir
  report_status "test/repo" "1" "test-repo-issue-1" "Test message" "$task_dir"
  
  # Verify comment includes execution summary
  local comment_body
  comment_body="$(cat "${TEST_TMP_DIR}/comment.txt")"
  assert_contains "$comment_body" "Execution Summary" "Comment includes execution summary header"
  assert_contains "$comment_body" "Execution Progress" "Comment includes execution progress section"
  
  teardown_test_env
}

test_summary_disabled_by_default() {
  setup_test_env
  
  # Create task.json with analysis
  local task_dir="${TEST_WORKSPACE_DIR}/test-repo-issue-1"
  mkdir -p "$task_dir"
  cat > "$task_dir/task.json" <<'EOF'
{
  "id": "test-repo-issue-1",
  "analysis": "This should not appear in the comment"
}
EOF

  # Create config with default settings (summaries disabled)
  write_minimal_config
  config_load
  
  # Mock gh functions
  gh_find_tracking_comment() { echo ""; }
  gh_post_comment() {
    local body="$3"
    echo "$body" > "${TEST_TMP_DIR}/comment.txt"
  }
  export -f gh_find_tracking_comment gh_post_comment
  
  # Test report_dispatch without summaries
  report_dispatch "test/repo" "1" "test-repo-issue-1" "$task_dir"
  
  # Verify comment does NOT include analysis
  local comment_body
  comment_body="$(cat "${TEST_TMP_DIR}/comment.txt")"
  if echo "$comment_body" | grep -q "This should not appear"; then
    assert_eq "no" "yes" "Analysis should not appear when summaries disabled"
  else
    assert_eq "yes" "yes" "Analysis correctly excluded when disabled"
  fi
  
  teardown_test_env
}

# Run all tests
echo "=== Testing Summary Attachments ==="
test_format_summary
test_format_summary_truncation
test_format_summary_collapsible
test_config_defaults
test_config_parsing
test_report_dispatch_with_summary
test_report_status_with_summary
test_summary_disabled_by_default

print_test_summary
