#!/usr/bin/env bash
# Test helpers for gh-pm

# Test counters
TEST_PASS=0
TEST_FAIL=0
TEST_NAME=""

# Test environment paths
TEST_TMP_DIR=""
TEST_CONFIG_FILE=""
TEST_WORKSPACE_DIR=""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

setup_test_env() {
  TEST_TMP_DIR="$(mktemp -d -t gh-pm-test.XXXXXX)"
  TEST_CONFIG_FILE="${TEST_TMP_DIR}/config.toml"
  TEST_WORKSPACE_DIR="${TEST_TMP_DIR}/workspace"
  mkdir -p "${TEST_WORKSPACE_DIR}"

  export GH_PM_CONFIG="${TEST_CONFIG_FILE}"
  export GH_PM_WORKSPACE="${TEST_WORKSPACE_DIR}"
  export GH_PM_DRY_RUN="1"
  export GH_PM_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && cd .. && pwd)"

  # Source libs (re-source to reset globals)
  source "${GH_PM_DIR}/lib/config.sh"
  source "${GH_PM_DIR}/lib/log.sh"
  source "${GH_PM_DIR}/lib/github.sh"
  source "${GH_PM_DIR}/lib/llm.sh"
  source "${GH_PM_DIR}/lib/dispatch.sh"
  source "${GH_PM_DIR}/lib/report.sh"
  source "${GH_PM_DIR}/lib/recovery.sh"
}

teardown_test_env() {
  [[ -n "${TEST_TMP_DIR}" && -d "${TEST_TMP_DIR}" ]] && rm -rf "${TEST_TMP_DIR}"
}

# Assertions — never exit on failure, just increment counters.
assert_eq() {
  local expected="$1" actual="$2" msg="$3"
  if [[ "$expected" == "$actual" ]]; then
    echo -e "${GREEN}\u2713${NC} $msg"
    (( TEST_PASS++ )) || true
  else
    echo -e "${RED}\u2717${NC} $msg"
    echo "  expected: $expected"
    echo "  actual:   $actual"
    (( TEST_FAIL++ )) || true
  fi
}

assert_contains() {
  local haystack="$1" needle="$2" msg="$3"
  if [[ "$haystack" == *"$needle"* ]]; then
    echo -e "${GREEN}\u2713${NC} $msg"
    (( TEST_PASS++ )) || true
  else
    echo -e "${RED}\u2717${NC} $msg"
    echo "  needle not found: $needle"
    (( TEST_FAIL++ )) || true
  fi
}

assert_file_exists() {
  local path="$1" msg="$2"
  if [[ -f "$path" ]]; then
    echo -e "${GREEN}\u2713${NC} $msg"
    (( TEST_PASS++ )) || true
  else
    echo -e "${RED}\u2717${NC} $msg"
    echo "  file not found: $path"
    (( TEST_FAIL++ )) || true
  fi
}

assert_file_not_exists() {
  local path="$1" msg="$2"
  if [[ ! -f "$path" ]]; then
    echo -e "${GREEN}\u2713${NC} $msg"
    (( TEST_PASS++ )) || true
  else
    echo -e "${RED}\u2717${NC} $msg"
    echo "  file should not exist: $path"
    (( TEST_FAIL++ )) || true
  fi
}

assert_dir_exists() {
  local path="$1" msg="$2"
  if [[ -d "$path" ]]; then
    echo -e "${GREEN}\u2713${NC} $msg"
    (( TEST_PASS++ )) || true
  else
    echo -e "${RED}\u2717${NC} $msg"
    echo "  dir not found: $path"
    (( TEST_FAIL++ )) || true
  fi
}

# --- Config helpers ---

write_test_config() {
  cat > "${TEST_CONFIG_FILE}" <<'TOML'
[settings]
repos = ["test-org/test-repo", "test-org/another-repo"]
poll_interval = 30
workflow_timeout = 1800
max_retries = 2
log_level = "DEBUG"
workflow_command = "echo mock-workflow"

[profiles.default]
model = "gpt-4o"
api_url = "https://api.openai.com/v1"
api_key_env = "OPENAI_API_KEY"

[profiles.claude]
backend = "anthropic"
model = "claude-sonnet-4-20250514"
api_key_env = "ANTHROPIC_API_KEY"

[profiles.local]
model = "llama3"
api_url = "http://localhost:11434/v1"
TOML
}

write_minimal_config() {
  cat > "${TEST_CONFIG_FILE}" <<'TOML'
[settings]
repos = ["test-org/repo"]
workflow_command = "echo noop"

[profiles.default]
model = "gpt-4o"
api_url = "https://api.openai.com/v1"
api_key_env = "OPENAI_API_KEY"
TOML
}

# write_task_json TASK_DIR REPO NUMBER [TYPE]
write_task_json() {
  local task_dir="$1" repo="$2" number="$3" type="${4:-issue}"
  mkdir -p "$task_dir"
  local owner="${repo%%/*}"
  local repo_name="${repo#*/}"
  local task_id="${owner}-${repo_name}-${type}-${number}"
  cat > "$task_dir/task.json" <<EOF
{"id":"${task_id}","source":{"type":"${type}","repo":"${repo}","number":${number},"url":"https://github.com/${repo}/issues/${number}"},"title":"Test ${type}","body":"Test body","analysis":"Test analysis","created_at":"2024-01-01T00:00:00Z"}
EOF
}

# write_dispatch_json TASK_DIR [PID] [ATTEMPT] [TIMEOUT]
write_dispatch_json() {
  local task_dir="$1" pid="${2:-0}" attempt="${3:-1}" timeout="${4:-3600}"
  cat > "$task_dir/dispatch.json" <<EOF
{"pid":${pid},"dispatched_at":"$(date -u +%Y-%m-%dT%H:%M:%SZ)","attempt":${attempt},"timeout_seconds":${timeout}}
EOF
}

# write_result_json TASK_DIR [STATE] [SUMMARY]
write_result_json() {
  local task_dir="$1" state="${2:-done}" summary="${3:-Test completed}"
  cat > "$task_dir/result.json" <<EOF
{"state":"${state}","summary":"${summary}","completed_at":"$(date -u +%Y-%m-%dT%H:%M:%SZ)"}
EOF
}

print_test_summary() {
  local total=$(( TEST_PASS + TEST_FAIL ))
  echo ""
  echo "=== ${TEST_NAME}: ${TEST_PASS}/${total} passed ==="
  [[ $TEST_FAIL -gt 0 ]] && return 1
  return 0
}
