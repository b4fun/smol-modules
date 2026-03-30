# gh-pm Design

A GitHub-native project manager agent. It watches for tasks (issues, PRs, comments) assigned to the authenticated user, uses an LLM to analyze and break them down, then delegates sub-tasks to local workflows and reports status back on GitHub.

## Overview

```
GitHub (poll)          gh-pm              Workflows
  issues/PRs ───────▶  analyze  ───────▶  agent / script
  comments   ◀───────  report   ◀───────  result
```

gh-pm is a **coordinator**, not an executor. It decides what to do; workflows do the work. Humans decide when a task is complete.

## Key decisions

### 1. GitHub as the interface — `gh` CLI

All GitHub interaction goes through the `gh` CLI, reusing whatever auth the user already has (`gh auth login`). No separate tokens or OAuth flows. This keeps setup trivial and lets us leverage `gh`'s built-in pagination, caching, and output formatting.

### 2. Polling for task discovery

gh-pm polls GitHub on a configurable interval. No webhooks, no server to expose. This fits the single-host model and avoids infrastructure. The poll fetches:

- Issues assigned to the authenticated user
- PRs assigned to the authenticated user (including review requests)
- New comments / mentions on tracked items

A task is "new" if gh-pm hasn't processed it yet (tracked via GitHub-side state; see §5).

### 3. Configurable LLM backend

The LLM call for task analysis is behind a pluggable backend. gh-pm ships a thin calling convention — a function that takes a prompt and returns a response — with adapters for:

- **Raw HTTP API** — any OpenAI-compatible chat endpoint (covers OpenRouter, self-hosted, etc.)
- **Provider SDKs** — OpenAI Agents SDK, Anthropic SDK, Copilot SDK, etc.

Adapter selection is via environment variable or config file. The raw HTTP adapter is the default since it works everywhere and keeps the bash implementation simple. SDK-based adapters can shell out to a small wrapper script/binary in the adapter's language.

Configuration surface:

| Variable | Purpose |
|---|---|
| `GHPM_LLM_BACKEND` | Adapter name (`raw`, `openrouter`, `openai`, `anthropic`, `copilot`, …) |
| `GHPM_LLM_MODEL` | Model identifier (e.g. `gpt-4o`, `claude-sonnet-4-20250514`) |
| `GHPM_LLM_API_KEY` | API key (for raw / provider adapters) |
| `GHPM_LLM_API_URL` | Base URL (for raw adapter, defaults to `https://api.openai.com/v1`) |

### 4. Directory-based workflow protocol

gh-pm delegates work by writing a **task file** into a workspace directory. A workflow picks it up, does the work, and writes a **result file**. gh-pm watches for results.

```
$GHPM_WORKSPACE/
  <task-id>/
    task.json        # written by gh-pm
    status.json      # written by workflow (updated as work progresses)
    result.json      # written by workflow (final output)
```

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
  "state": "done",
  "summary": "What was accomplished",
  "artifacts": ["link or path to output"],
  "completed_at": "ISO-8601"
}
```

gh-pm detects completion by the presence of `result.json`.

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

### 7. Local testing

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
