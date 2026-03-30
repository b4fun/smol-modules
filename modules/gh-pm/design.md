# gh-pm Design

A GitHub-native project manager agent. It watches for tasks (issues, PRs, comments) assigned to the authenticated user, uses an LLM to analyze and break them down, then delegates sub-tasks to local workflows and reports status back on GitHub.

## Overview

```
GitHub (poll)          gh-pm              Workflows
  issues/PRs ───────▶  analyze  ───────▶  agent / script
  comments   ◀───────  report   ◀───────  result
                         ↻
                   monitor / retry
```

gh-pm is a **coordinator**, not an executor. It decides what to do; workflows do the work. Humans decide when a task is complete.

The core loop runs continuously: poll → analyze → dispatch → **monitor** → report. During the monitor phase, gh-pm periodically checks workflow status and retries timed-out workflows (see §4).

## State folder overview

gh-pm uses a single workspace directory (`$GH_PM_WORKSPACE`, default `~/.gh-pm/workspace`) as the source of truth for all in-flight work:

```
~/.gh-pm/
  gh-pm.toml             # config: LLM profiles, poll interval, timeouts
  gh-pm.log              # global log (if log_file is set)
  workspace/
    <task-id>/
      task.json          # task definition + LLM analysis (written by gh-pm)
      dispatch.json      # dispatch metadata: PID, timestamps, attempt count (written by gh-pm)
      status.json        # progress updates (written by workflow)
      result.json        # final output (written by workflow)
      gh-pm.log          # per-task log (written by gh-pm)
```

See §4 for the full protocol and file schemas.

## Key decisions

### 1. GitHub as the interface — `gh` CLI

All GitHub interaction goes through the `gh` CLI, reusing whatever auth the user already has (`gh auth login`). No separate tokens or OAuth flows. This keeps setup trivial and lets us leverage `gh`'s built-in pagination, caching, and output formatting.

### 2. Polling for task discovery

gh-pm polls GitHub on a configurable interval. No webhooks, no server to expose. This fits the single-host model and avoids infrastructure.

The poll scope is configured as a list of repos:

```toml
[settings]
repos = ["owner/repo-a", "owner/repo-b"]
```

For each repo, gh-pm fetches:

- Issues assigned to the authenticated user
- PRs assigned to the authenticated user (including review requests)
- New comments / mentions on tracked items

A task is "new" if gh-pm hasn't processed it yet (tracked via GitHub-side state; see §5).

**Task IDs** are derived from the GitHub source: `<owner>-<repo>-<type>-<number>` (e.g. `b4fun-smol-modules-issue-42`). This keeps IDs deterministic, human-readable, and maps 1:1 to workspace directories.

### 3. Configurable LLM backend

The LLM call for task analysis is behind a pluggable backend. Each provider is modeled as an **LLM provider profile** — a named configuration block that bundles the backend type, model, credentials, and any provider-specific settings.

#### Provider profiles

Profiles are defined in the config file (`~/.gh-pm/gh-pm.toml`, overridable via `GH_PM_CONFIG`):

```toml
[profiles.default]
model   = "gpt-4o"
api_url = "https://api.openai.com/v1"
api_key_env = "OPENAI_API_KEY"   # read key from this env var

[profiles.claude]
backend = "anthropic"     # Anthropic has a different API format, needs SDK adapter
model   = "claude-sonnet-4-20250514"
api_key_env = "ANTHROPIC_API_KEY"

[profiles.claude-openrouter]
model   = "anthropic/claude-sonnet-4-20250514"    # via OpenRouter (OpenAI-compatible)
api_url = "https://openrouter.ai/api/v1"
api_key_env = "OPENROUTER_API_KEY"

[profiles.local]
model   = "llama3"
api_url = "http://localhost:11434/v1"

[profiles.openai-agents]
backend = "openai-agents"     # only set backend when using an SDK adapter
model   = "gpt-4o"
api_key_env = "OPENAI_API_KEY"
```

When `backend` is omitted, gh-pm uses a plain OpenAI-compatible HTTP call (the most common case). The `backend` field is only needed for SDK-based adapters that require a different calling convention.

The active profile is selected by (in priority order):

1. **Task-level override** — a GitHub label on the issue/PR (e.g. `gh-pm:profile=claude`) selects the profile for that task.
2. **Environment variable** — `GH_PM_LLM_PROFILE=claude`.
3. **Config default** — the profile named `default`.

This lets users route different tasks to different models. For example, a label `gh-pm:profile=local` on a low-priority issue uses a local model, while critical tasks use a frontier model.

#### Supported backends

- **(default, no `backend` field)** — plain OpenAI-compatible HTTP chat endpoint. Works with OpenRouter, self-hosted models, or any provider that speaks the OpenAI chat completions format. This is the common path and needs no extra tooling.
- **`openai-agents`** — OpenAI Agents SDK. Shells out to a wrapper.
- **`anthropic`** — Anthropic SDK. Shells out to a wrapper.
- **`copilot`** — Copilot SDK. Shells out to a wrapper.

SDK-based backends shell out to a small wrapper script/binary in the adapter's language. The default (no backend) keeps things simple and works everywhere in bash.

### 4. Directory-based workflow protocol

gh-pm delegates work by writing a **task file** into a workspace directory. A workflow picks it up, does the work, and writes a **result file**. gh-pm watches for results.

File schemas (directory layout: see "State folder overview" above):

**task.json** (written by gh-pm):
```json
{
  "id": "<task-id>",
  "source": { "type": "issue", "repo": "owner/repo", "number": 42, "url": "..." },
  "title": "...",
  "body": "...",
  "analysis": "LLM-generated breakdown / instructions",
  "created_at": "ISO-8601"
}
```

**status.json** (written by workflow, optional, updated in-place):
```json
{
  "state": "running",
  "message": "Working on step 2 of 3",
  "updated_at": "ISO-8601"
}
```

**result.json** (written by workflow when done):
```json
{
  "state": "done | failed",
  "summary": "What was accomplished",
  "error": "reason for failure (when state=failed)",
  "artifacts": ["link or path to output"],
  "completed_at": "ISO-8601"
}
```

gh-pm detects completion by the presence of `result.json`.

**dispatch.json** (written by gh-pm when dispatching):
```json
{
  "pid": 12345,
  "dispatched_at": "ISO-8601",
  "attempt": 1,
  "timeout_seconds": 3600
}
```

#### Monitoring and timeout retry

While workflows are in-flight, gh-pm periodically (on each poll cycle) checks their status:

1. Read `status.json` — if updated, relay progress to GitHub.
2. Check `result.json` — if present, report completion.
3. Check timeout — if `now - dispatched_at > timeout_seconds` and no `result.json`, the workflow is considered timed out:
   - For process-spawn adapter: kill the process if still running.
   - Increment `attempt` in `dispatch.json` and re-dispatch (up to a configurable max retries, default 3).
   - Post a timeout notice on GitHub.
4. If max retries exceeded, mark as failed and report.

Timeout and retry settings are configurable per-profile or globally in `gh-pm.toml`:

```toml
[settings]
poll_interval = 60           # seconds
workflow_timeout = 3600      # seconds, default per-task timeout
max_retries = 3
```

#### Restart recovery

On startup, gh-pm scans `$GH_PM_WORKSPACE/` for existing task directories and reconciles their state:

- **Has `result.json`** → treat as completed; report to GitHub if not already reported.
- **Has `status.json` but no `result.json`** → workflow was in-flight; resume monitoring. Check `dispatch.json` for PID — if the process is no longer running (for process-spawn adapter), treat as timed out and retry per the retry policy.
- **Has `task.json` only (no `dispatch.json`)** → dispatch was written but workflow never started; re-dispatch.

This makes gh-pm resilient to crashes and restarts. The workspace directory is the source of truth for in-flight work, and GitHub comments are the source of truth for what's been reported.

**Process-spawn adapter.** For convenience, gh-pm includes a built-in adapter that implements this protocol by spawning a subprocess. It writes `task.json`, runs the configured command (passing the task directory as an argument), and expects the process to write `status.json` / `result.json` before exiting. This lets users plug in any existing tool without teaching it the directory protocol directly — the adapter script bridges the gap.

**Extensibility.** The protocol is deliberately file-based and language-agnostic. Future versions may swap to a socket/gRPC/message-queue protocol. The internal interface between gh-pm's core loop and the workflow dispatch is a single function (`dispatch_task`), making it straightforward to replace.

### 5. GitHub-side state tracking

Instead of a local database, gh-pm tracks workflow state by posting comments on the originating issue/PR:

- When a task is dispatched: comment with a workflow reference (task ID, timestamp).
- When a workflow reports status: update or reply to the tracking comment.
- When a workflow completes: post a summary comment with results.

gh-pm identifies its own comments by a marker tag (e.g. `<!-- gh-pm:task-id -->`) to avoid re-processing and to locate existing tracking comments.

This keeps state distributed and visible. Trade-off: it's chatty on the issue thread. Acceptable for now; a future central state service can replace this.

### 6. Implementation: bash + jq + gh

The module is implemented in bash. Dependencies:

- `bash` (4.x+)
- `gh` (GitHub CLI)
- `jq`
- `curl` (for LLM API calls in the raw adapter)

All provided via the module's `flake.nix`.

### 7. Logging

gh-pm logs to stderr and optionally to a file. Log lines are structured as `<timestamp> <level> <component> <message>`.

Levels: `DEBUG`, `INFO`, `WARN`, `ERROR`.

Components follow the internal structure: `poll`, `analyze`, `dispatch`, `monitor`, `report`.

Configuration:

```toml
[settings]
log_level = "INFO"                      # default
log_file  = "~/.gh-pm/gh-pm.log"        # optional; always logs to stderr, this adds a file copy
```

Per-task logs are also written to the task directory:

```
$GH_PM_WORKSPACE/<task-id>/gh-pm.log
```

This captures everything gh-pm did for that task (LLM prompts/responses, dispatch details, status checks, GitHub comment posts). Useful for debugging a specific task without sifting through the global log.

In `--dry-run` mode, log level defaults to `DEBUG` and all output goes to stderr.

### 8. Local testing

gh-pm supports a `--dry-run` mode that:

- Reads tasks from a local JSON file instead of polling GitHub.
- Prints LLM prompts to stdout instead of calling the API (or calls the API if configured).
- Writes workflow files to a local temp directory.
- Prints comment content to stdout instead of posting to GitHub.

This makes the full loop testable without any GitHub interaction.

## Non-goals (for now)

- **Closing / merging tasks.** Humans decide completion.
- **Multi-user.** One authenticated user per instance.
- **Webhook / event-driven mode.** Polling only.
- **Built-in workflow execution.** gh-pm delegates; it doesn't run the work itself.
