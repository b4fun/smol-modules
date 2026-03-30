# gh-pm — GitHub Project Manager Agent

A GitHub-native project manager agent that watches for assigned tasks (issues, PRs, comments), uses an LLM to analyze and break them down, then delegates sub-tasks to local workflows and reports status back on GitHub.

## Quick Start

### 1. Prerequisites

- **GitHub CLI** (`gh`) — Install and authenticate: `gh auth login`
- **jq**, **curl**, **bash** — Standard Unix tools
- **[toml2json](https://github.com/woodruffw/toml2json)** — TOML-to-JSON converter (`cargo install toml2json`)
- Or use Nix: `nix develop` (provides all dependencies)

### 2. Create Configuration

Create `~/.gh-pm/gh-pm.toml` (see `gh-pm.example.toml` for a template):

```toml
[settings]
repos = ["your-org/your-repo"]
poll_interval = 60
workflow_timeout = 3600
max_retries = 3
log_level = "INFO"
log_file = "~/.gh-pm/gh-pm.log"
workflow_command = "/path/to/your/workflow-script"

[profiles.default]
model = "gpt-4o"
api_url = "https://api.openai.com/v1"
api_key_env = "OPENAI_API_KEY"
```

### 3. Run

```bash
# Continuous mode (polls GitHub on interval)
./bin/gh-pm

# Single poll cycle (useful for testing)
./bin/gh-pm --once

# Dry-run mode (no side effects)
./bin/gh-pm --dry-run --once
```

## Configuration Reference

Configuration is stored in `~/.gh-pm/gh-pm.toml` (or set via `$GH_PM_CONFIG`).

### `[settings]` Section

Global behavior settings:

```toml
[settings]
repos = ["owner/repo-a", "owner/repo-b"]  # Required: GitHub repos to monitor
poll_interval = 60                          # Optional: seconds between polls (default: 60)
workflow_timeout = 3600                     # Optional: workflow timeout in seconds (default: 3600)
max_retries = 3                             # Optional: max retry attempts for timed-out workflows (default: 3)
log_level = "INFO"                          # Optional: DEBUG|INFO|WARN|ERROR (default: INFO)
log_file = "~/.gh-pm/gh-pm.log"            # Optional: path to global log file (default: stderr only)
workflow_command = "/path/to/script"        # Required: command to dispatch workflows
```

**Field details:**

- **`repos`** (array of strings, required): List of GitHub repos to monitor for assigned tasks. Format: `"owner/repo"`.
- **`poll_interval`** (integer, default: 60): Seconds between polling cycles.
- **`workflow_timeout`** (integer, default: 3600): Timeout in seconds for workflows. After this time, workflows are considered timed out and retried.
- **`max_retries`** (integer, default: 3): Maximum number of retry attempts for timed-out workflows before marking as failed.
- **`log_level`** (string, default: "INFO"): Logging verbosity. Options: `DEBUG`, `INFO`, `WARN`, `ERROR`.
- **`log_file`** (string, optional): Path to global log file. If unset, logs go to stderr. Expands `~` to home directory.
- **`workflow_command`** (string, required): Command to execute when dispatching a workflow. Receives the task directory path as an argument.

### `[profiles.<name>]` Section

LLM provider profiles. Define one or more profiles for different LLM backends. The profile named `default` is used for task analysis.

```toml
[profiles.default]
backend = "openai"              # Optional: backend type (default: "openai" for OpenAI-compatible APIs)
model = "gpt-4o"                # Required: model name
api_url = "https://api.openai.com/v1"  # Required: API endpoint (for OpenAI-compatible APIs)
api_key_env = "OPENAI_API_KEY"  # Required: environment variable containing API key
```

**Field details:**

- **`backend`** (string, optional): Backend type. Default is `"openai"` (OpenAI-compatible HTTP API). Built-in backends: `"openai"`, `"shelley"` (local [shelley](https://github.com/anthropics/shelley) agent via Unix socket). Use other values like `"anthropic"` or `"openai-agents"` for SDK-based adapters with different calling conventions.
- **`model`** (string, required): Model identifier (e.g., `"gpt-4o"`, `"claude-sonnet-4-20250514"`, `"llama3"`).
- **`api_url`** (string, required): Base URL for the API endpoint. For OpenAI: `https://api.openai.com/v1`. For local Ollama: `http://localhost:11434/v1`.
- **`api_key_env`** (string, required for openai backend): Name of the environment variable containing the API key. gh-pm reads the key from this env var at runtime.
- **`shelley_url`** (string, optional): Socket URL for the shelley backend. Defaults to `unix:///home/$USER/.config/shelley/shelley.sock`. Can also be an `http://` URL.

**Example profiles:**

```toml
# OpenAI (default)
[profiles.default]
model = "gpt-4o"
api_url = "https://api.openai.com/v1"
api_key_env = "OPENAI_API_KEY"

# Local Ollama
[profiles.local]
model = "llama3"
api_url = "http://localhost:11434/v1"
api_key_env = "OLLAMA_API_KEY"  # Can be dummy if Ollama doesn't require auth

# Claude via OpenRouter (OpenAI-compatible)
[profiles.claude]
model = "anthropic/claude-sonnet-4-20250514"
api_url = "https://openrouter.ai/api/v1"
api_key_env = "OPENROUTER_API_KEY"

# Shelley (local exe.dev agent — no API key needed)
[profiles.shelley]
backend = "shelley"
model = "claude-sonnet-4.5"
```

## CLI Usage

```bash
gh-pm [OPTIONS]

Options:
  --config PATH      Config file (default: ~/.gh-pm/gh-pm.toml, or $GH_PM_CONFIG)
  --workspace PATH   Workspace directory (default: ~/.gh-pm/workspace, or $GH_PM_WORKSPACE)
  --dry-run          No side effects — print what would happen (no GitHub writes, no workflow dispatch)
  --once             Run one poll cycle then exit (useful for testing)
  --help             Show this help
```

**Environment variables:**

- `GH_PM_CONFIG`: Override config file path (default: `~/.gh-pm/gh-pm.toml`)
- `GH_PM_WORKSPACE`: Override workspace directory (default: `~/.gh-pm/workspace`)
- `GH_PM_DRY_RUN`: Set to `1` to enable dry-run mode (equivalent to `--dry-run`)

## Directory Protocol for Workflows

gh-pm delegates work to external workflows via a **directory-based protocol**. Each task gets its own directory under `$GH_PM_WORKSPACE/<task-id>/`.

### Directory Structure

```
~/.gh-pm/workspace/<task-id>/
  task.json          # Task definition + LLM analysis (written by gh-pm)
  dispatch.json      # Dispatch metadata: PID, timestamps, attempt count (written by gh-pm)
  status.json        # Progress updates (written by workflow, optional)
  result.json        # Final output (written by workflow when done)
  gh-pm.log          # Per-task log (written by gh-pm)
```

### File Schemas

**`task.json`** (written by gh-pm, read by workflow):
```json
{
  "id": "owner-repo-issue-42",
  "source": {
    "type": "issue",
    "repo": "owner/repo",
    "number": 42,
    "url": "https://github.com/owner/repo/issues/42"
  },
  "title": "Fix the build",
  "body": "The CI is failing...",
  "analysis": "LLM-generated breakdown and instructions",
  "created_at": "2025-03-30T12:00:00Z"
}
```

**`status.json`** (written by workflow, optional, updated in-place):
```json
{
  "state": "running",
  "message": "Working on step 2 of 3",
  "updated_at": "2025-03-30T12:05:00Z"
}
```

**`result.json`** (written by workflow when done):
```json
{
  "state": "done",
  "summary": "Fixed the build by updating dependencies",
  "artifacts": ["https://github.com/owner/repo/pull/43"],
  "completed_at": "2025-03-30T12:30:00Z"
}
```

Or for failures:
```json
{
  "state": "failed",
  "error": "Tests failed: 3 errors in test_foo.py",
  "completed_at": "2025-03-30T12:30:00Z"
}
```

**`dispatch.json`** (written by gh-pm, read by gh-pm for monitoring):
```json
{
  "pid": 12345,
  "dispatched_at": "2025-03-30T12:00:00Z",
  "attempt": 1,
  "timeout_seconds": 3600
}
```

### Workflow Implementation Guide

To implement a workflow:

1. **Read `task.json`** from the directory passed as the first argument
2. **Optionally write `status.json`** to report progress during execution
3. **Write `result.json`** when done (required)

Example workflow (bash):

```bash
#!/usr/bin/env bash
set -euo pipefail

TASK_DIR="$1"
cd "$TASK_DIR"

# Read task
TITLE=$(jq -r '.title' task.json)
ANALYSIS=$(jq -r '.analysis' task.json)

# Report progress
echo '{"state":"running","message":"Starting work","updated_at":"'$(date -Iseconds)'"}' > status.json

# Do work...
sleep 10

# Report completion
echo '{
  "state":"done",
  "summary":"Completed the task",
  "completed_at":"'$(date -Iseconds)'"
}' > result.json
```

### Monitoring and Timeout Retry

gh-pm monitors in-flight workflows on each poll cycle:

1. Checks `status.json` for progress updates → relays to GitHub
2. Checks `result.json` for completion → reports to GitHub
3. Checks timeout: if `now - dispatched_at > timeout_seconds` and no `result.json`, the workflow is timed out:
   - Kills the process if still running
   - Increments `attempt` in `dispatch.json`
   - Re-dispatches (up to `max_retries` attempts)
   - Posts a timeout notice on GitHub
4. If max retries exceeded, marks as failed and reports

### Restart Recovery

On startup, gh-pm scans the workspace and reconciles state:

- **Has `result.json`**: Completed → report to GitHub if not already reported
- **Has `status.json` but no `result.json`**: In-flight → resume monitoring, check for timeout
- **Has `task.json` only**: Dispatch was written but never started → re-dispatch

This makes gh-pm resilient to crashes and restarts.

## Dry-Run Mode

Use `--dry-run` to preview what gh-pm would do without making changes:

```bash
./bin/gh-pm --dry-run --once
```

In dry-run mode:
- GitHub API reads are performed normally
- No GitHub writes (comments, labels, etc.)
- No workflow dispatch
- All actions are logged with `[DRY-RUN]` prefix

Useful for:
- Testing configuration
- Verifying task discovery logic
- Debugging without side effects

## Running as a systemd Service

gh-pm ships with an install script that sets it up as a **systemd user unit** — no root required.

### Install

```bash
# 1. Create an environment file with your API keys
mkdir -p ~/.gh-pm
cat > ~/.gh-pm/env <<'EOF'
OPENAI_API_KEY=sk-...
# ANTHROPIC_API_KEY=sk-ant-...
EOF
chmod 600 ~/.gh-pm/env

# 2. Run the installer
bash modules/gh-pm/install.sh

# 3. Start the service
systemctl --user start gh-pm.service
```

The installer:
- Generates a unit file in `~/.config/systemd/user/gh-pm.service`
- Auto-detects the `gh-pm` binary path (override with `--exec-start PATH`)
- Loads API keys from `~/.gh-pm/env` if it exists (override with `--env-file PATH`)
- Enables `loginctl enable-linger` so the service **runs at boot and survives logout**
- Checks that required dependencies (`gh`, `jq`, `toml2json`, `curl`) are in PATH

### Linger: Running After Logout

By default, systemd user units **only run while the user has an active login session**. When the last session ends (SSH disconnect, logout), all user units stop.

The install script enables **linger** to change this behavior:

```bash
loginctl enable-linger $USER
```

With linger enabled:
- gh-pm starts at boot (no login required)
- gh-pm keeps running after you log out
- gh-pm auto-restarts on failure (`Restart=on-failure`)

To skip linger (only run during active sessions):

```bash
bash install.sh --no-linger
```

### Managing the Service

```bash
systemctl --user start   gh-pm.service   # Start
systemctl --user stop    gh-pm.service   # Stop
systemctl --user status  gh-pm.service   # Status
systemctl --user restart gh-pm.service   # Restart
journalctl --user -u gh-pm.service -f    # Follow logs
```

### Uninstall

```bash
bash modules/gh-pm/install.sh --uninstall
```

### Installer Options

| Flag | Purpose |
|---|---|
| `--exec-start PATH` | Override the gh-pm binary path |
| `--env-file PATH` | Path to env file with API keys (default: `~/.gh-pm/env`) |
| `--no-linger` | Skip `loginctl enable-linger` — service only runs during active sessions |
| `--uninstall` | Stop, disable, and remove the service |

### Environment File

Store secrets in `~/.gh-pm/env` (mode `600`):

```bash
# ~/.gh-pm/env
OPENAI_API_KEY=sk-...
ANTHROPIC_API_KEY=sk-ant-...
GH_PM_LLM_PROFILE=default
```

### Using a Nix-installed Binary

```bash
bash install.sh --exec-start ~/.nix-profile/bin/gh-pm
```

### Sample Unit File

A reference unit file is also provided at [`gh-pm.service`](./gh-pm.service) for manual setup or system-level deployment. The install script generates a tailored version automatically.

## Running Tests

```bash
# Run all tests
cd modules/gh-pm
bash test/run_all.sh

# Run a specific test
bash test/test_config.sh
```

Tests use a minimal test framework and mock GitHub API calls. No external dependencies required.

## Architecture Details

For implementation details, design decisions, and protocol specifications, see [design.md](./design.md).

Key highlights:
- **GitHub as the interface**: Uses `gh` CLI for all GitHub operations
- **Polling model**: No webhooks, no server infrastructure
- **Configurable LLM backend**: Pluggable provider profiles (OpenAI, Anthropic, local models)
- **Directory-based protocol**: Language-agnostic workflow integration
- **GitHub-side state**: Tracks workflow state via comments (no local database)
- **Implemented in bash**: Minimal dependencies, easy to inspect and modify
