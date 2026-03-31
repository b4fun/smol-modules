#!/usr/bin/env bash
# Demo: Tracking Comment Lifecycle
# Shows how gh-pm updates tracking comments throughout task execution

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GH_PM_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "=== gh-pm Tracking Comment Lifecycle Demo ==="
echo
echo "This demo shows how tracking comments evolve as tasks progress."
echo

# Source libraries
for lib in "$GH_PM_DIR"/lib/*.sh; do
  source "$lib"
done

# Set up dry-run mode
export GH_PM_DRY_RUN=1
export GH_PM_WORKSPACE="/tmp/gh-pm-demo"
export GH_PM_CONFIG="/tmp/gh-pm-demo.toml"
mkdir -p "$GH_PM_WORKSPACE"

# Create minimal config
cat > "$GH_PM_CONFIG" <<'TOML'
[settings]
repos = ["owner/repo"]
workflow_command = "/bin/true"
[profiles.default]
model = "gpt-4o"
api_url = "https://api.openai.com/v1"
api_key_env = "OPENAI_API_KEY"
TOML

config_load
log_init

REPO="owner/repo"
NUMBER=42
TASK_ID="owner-repo-issue-42"
TASK_DIR="$GH_PM_WORKSPACE/$TASK_ID"

mkdir -p "$TASK_DIR"

echo "===================="
echo "STAGE 1: Analyzing"
echo "===================="
echo
report_analyzing "$REPO" "$NUMBER" "$TASK_ID" "default" 2>&1 | grep -A 20 "gh-pm:"
echo
sleep 1

echo "===================="
echo "STAGE 2: Dispatched"
echo "===================="
echo
# Create dispatch.json
cat > "$TASK_DIR/dispatch.json" <<JSON
{
  "pid": 12345,
  "dispatched_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "attempt": 1,
  "timeout_seconds": 3600
}
JSON
report_dispatch "$REPO" "$NUMBER" "$TASK_ID" 2>&1 | grep -A 20 "gh-pm:"
echo
sleep 1

echo "===================="
echo "STAGE 3: In Progress"
echo "===================="
echo
cat > "$TASK_DIR/status.json" <<JSON
{
  "state": "running",
  "message": "Running tests and building artifacts...",
  "updated_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
JSON
# In dry-run, status update needs an existing comment, so we simulate the output
cat <<'STATUS'
<!-- gh-pm:owner-repo-issue-42 -->
## 🤖 gh-pm: Task In Progress

| Field | Value |
|-------|-------|
| Task ID | `owner-repo-issue-42` |
| Status | ⏳ Running |
| Updated | $(date -u +%Y-%m-%d\ %H:%M:%S\ UTC) |

### Progress

Running tests and building artifacts...

_Managed by gh-pm._
STATUS
echo
sleep 1

echo "===================="
echo "STAGE 4: Completed"
echo "===================="
echo
cat > "$TASK_DIR/result.json" <<JSON
{
  "state": "done",
  "summary": "Successfully implemented the requested feature:\n- Added new function processData()\n- Created comprehensive unit tests\n- Updated API documentation\n- Opened PR #123 for review",
  "completed_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
JSON
report_completion "$REPO" "$NUMBER" "$TASK_ID" "$TASK_DIR/result.json" 2>&1 | grep -A 30 "gh-pm:"
echo

echo "===================="
echo "Demo Complete!"
echo "===================="
echo
echo "The same comment ID would be updated at each stage, keeping"
echo "the GitHub thread clean with a single tracking comment."
echo
echo "To see this in action on a real issue:"
echo "  1. Assign yourself to an issue in a monitored repo"
echo "  2. Watch gh-pm logs: tail -f ~/.gh-pm/gh-pm.log"
echo "  3. Check the issue comments as the task progresses"
echo

# Cleanup
rm -rf "$GH_PM_WORKSPACE" "$GH_PM_CONFIG"
