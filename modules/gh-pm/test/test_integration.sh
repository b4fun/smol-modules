#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source ./helpers.sh
TEST_NAME="integration"
echo "Running integration tests..."

# --- Test: gh-pm --help exits 0 ---
GH_PM_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && cd .. && pwd)"
output="$(bash "${GH_PM_DIR}/bin/gh-pm" --help 2>&1)"
rc=$?
assert_eq "0" "$rc" "--help exits 0"
assert_contains "$output" "Usage" "--help shows usage"
assert_contains "$output" "--dry-run" "--help mentions --dry-run"

# --- Test: gh-pm --once --dry-run runs and exits cleanly ---
setup_test_env; write_test_config
output="$(bash "${GH_PM_DIR}/bin/gh-pm" --once --dry-run --config "$TEST_CONFIG_FILE" --workspace "$TEST_WORKSPACE_DIR" 2>&1)"
rc=$?
assert_eq "0" "$rc" "--once --dry-run exits 0"
assert_contains "$output" "gh-pm starting" "shows startup message"
assert_contains "$output" "startup recovery" "runs recovery"
assert_contains "$output" "--once mode, exiting" "reports once mode exit"
assert_contains "$output" "gh-pm stopped" "shows shutdown message"
teardown_test_env

# --- Test: gh-pm --once --dry-run with pre-existing completed task ---
setup_test_env; write_test_config
task_dir="${TEST_WORKSPACE_DIR}/test-org-test-repo-issue-99"
write_task_json "$task_dir" "test-org/test-repo" 99
write_dispatch_json "$task_dir" 0 1 3600
write_result_json "$task_dir" "done" "Pre-existing done task"
output="$(bash "${GH_PM_DIR}/bin/gh-pm" --once --dry-run --config "$TEST_CONFIG_FILE" --workspace "$TEST_WORKSPACE_DIR" 2>&1)"
rc=$?
assert_eq "0" "$rc" "handles pre-existing task"
assert_contains "$output" "completed" "recovery processes completed task"
teardown_test_env

# --- Test: bash -n syntax check catches no 'local' outside functions ---
# Regression test for the crash-loop bug where 'local pr_author' was used
# in the main while-loop (not inside a function). bash -n validates syntax.
output="$(bash -n "${GH_PM_DIR}/bin/gh-pm" 2>&1)"
rc=$?
assert_eq "0" "$rc" "bash -n syntax check passes (no local outside function)"

# --- Test: no 'local' keyword in main loop body ---
# Extract the main loop (after last function definition) and ensure no 'local' usage.
# Functions are defined before the main loop; the main loop starts with 'while true'.
main_script="${GH_PM_DIR}/bin/gh-pm"
loop_start=$(grep -n '^while true; do$' "$main_script" | tail -1 | cut -d: -f1)
if [[ -n "$loop_start" ]]; then
  # Extract from loop start to end of file and look for bare 'local' statements
  local_in_loop=$(sed -n "${loop_start},\$p" "$main_script" | grep -c '^[[:space:]]*local ' || true)
  assert_eq "0" "$local_in_loop" "no 'local' keyword in main loop body"
else
  assert_eq "found" "" "main loop 'while true' not found in script"
fi

print_test_summary
