#!/usr/bin/env bash
# gh-pm/lib/report.sh — GitHub reporting
# Posts and updates tracking comments on issues/PRs.

# report_analyzing REPO NUMBER TASK_ID PROFILE
report_analyzing() {
  local repo="$1" number="$2" task_id="$3" profile="${4:-default}"
  local marker="<!-- gh-pm:${task_id} -->"
  local ts
  ts="$(date -u +%Y-%m-%d\ %H:%M:%S\ UTC)"

  local body="${marker}
## 🤖 gh-pm: Analyzing Task

| Field | Value |
|-------|-------|
| Task ID | \`${task_id}\` |
| Status | 🔍 Analyzing |
| Profile | \`${profile}\` |
| Started | ${ts} |

_Analyzing with LLM before dispatching workflow…_"

  log_info "report" "Posting analyzing comment $repo#$number task=$task_id"
  gh_post_comment "$repo" "$number" "$body"
}

# report_dispatch REPO NUMBER TASK_ID
report_dispatch() {
  local repo="$1" number="$2" task_id="$3"
  local marker="<!-- gh-pm:${task_id} -->"
  local ts
  ts="$(date -u +%Y-%m-%d\ %H:%M:%S\ UTC)"

  local body="${marker}
## 🤖 gh-pm: Task Dispatched

| Field | Value |
|-------|-------|
| Task ID | \`${task_id}\` |
| Status | ⏳ Running |
| Started | ${ts} |

_Managed by gh-pm. Updates will follow._"

  log_info "report" "Posting dispatch comment $repo#$number task=$task_id"
  local comment_id
  comment_id="$(gh_find_tracking_comment "$repo" "$number" "$task_id")"
  if [[ -n "$comment_id" ]]; then
    gh_update_comment "$repo" "$comment_id" "$body"
  else
    gh_post_comment "$repo" "$number" "$body"
  fi
}

# report_status REPO NUMBER TASK_ID STATUS_MSG
report_status() {
  local repo="$1" number="$2" task_id="$3" status_msg="$4"
  local comment_id
  comment_id="$(gh_find_tracking_comment "$repo" "$number" "$task_id")"
  if [[ -z "$comment_id" ]]; then
    log_warn "report" "No tracking comment for $repo#$number task=$task_id"
    return 0
  fi

  local marker="<!-- gh-pm:${task_id} -->"
  local ts
  ts="$(date -u +%Y-%m-%d\ %H:%M:%S\ UTC)"

  local body="${marker}
## 🤖 gh-pm: Task In Progress

| Field | Value |
|-------|-------|
| Task ID | \`${task_id}\` |
| Status | ⏳ Running |
| Updated | ${ts} |

### Progress

${status_msg}

_Managed by gh-pm._"

  gh_update_comment "$repo" "$comment_id" "$body"
}

# report_completion REPO NUMBER TASK_ID RESULT_JSON_PATH
report_completion() {
  local repo="$1" number="$2" task_id="$3" result_path="$4"
  local comment_id
  comment_id="$(gh_find_tracking_comment "$repo" "$number" "$task_id")"

  local state summary error
  state="$(jq -r '.state // "done"' "$result_path" 2>/dev/null)"
  summary="$(jq -r '.summary // "No summary"' "$result_path" 2>/dev/null)"
  error="$(jq -r '.error // ""' "$result_path" 2>/dev/null)"

  local icon status_text
  if [[ "$state" == "failed" ]]; then
    icon="❌"; status_text="Failed"
  else
    icon="✅"; status_text="Completed"
  fi

  local marker="<!-- gh-pm:${task_id} -->"
  local ts
  ts="$(date -u +%Y-%m-%d\ %H:%M:%S\ UTC)"

  local error_section=""
  if [[ -n "$error" ]]; then error_section=$'\n### Error\n\n'"${error}"$'\n'; fi

  local body="${marker}
## 🤖 gh-pm: Task ${status_text}

| Field | Value |
|-------|-------|
| Task ID | \`${task_id}\` |
| Status | ${icon} ${status_text} |
| Finished | ${ts} |

### Summary

${summary}
${error_section}
_Managed by gh-pm._"

  log_info "report" "Reporting completion $repo#$number task=$task_id state=$state"
  if [[ -n "$comment_id" ]]; then
    gh_update_comment "$repo" "$comment_id" "$body"
  else
    gh_post_comment "$repo" "$number" "$body"
  fi
}

# report_timeout REPO NUMBER TASK_ID ATTEMPT MAX_RETRIES
report_timeout() {
  local repo="$1" number="$2" task_id="$3" attempt="$4" max_retries="$5"
  local comment_id
  comment_id="$(gh_find_tracking_comment "$repo" "$number" "$task_id")"
  [[ -z "$comment_id" ]] && return 0

  local marker="<!-- gh-pm:${task_id} -->"
  local ts
  ts="$(date -u +%Y-%m-%d\ %H:%M:%S\ UTC)"

  local body
  if (( attempt < max_retries )); then
    local next=$(( attempt + 1 ))
    body="${marker}
## 🤖 gh-pm: Timeout — Retrying

| Field | Value |
|-------|-------|
| Task ID | \`${task_id}\` |
| Status | ⏱️ Timed out |
| Attempt | ${next} / ${max_retries} |
| Updated | ${ts} |

_Retrying workflow…_"
  else
    body="${marker}
## 🤖 gh-pm: Task Failed

| Field | Value |
|-------|-------|
| Task ID | \`${task_id}\` |
| Status | ❌ Max retries exceeded |
| Attempts | ${max_retries} / ${max_retries} |
| Updated | ${ts} |

_Workflow timed out after ${max_retries} attempts._"
  fi

  gh_update_comment "$repo" "$comment_id" "$body"
}

# report_failure REPO NUMBER TASK_ID ERROR_MSG
report_failure() {
  local repo="$1" number="$2" task_id="$3" error_msg="$4"
  local comment_id
  comment_id="$(gh_find_tracking_comment "$repo" "$number" "$task_id")"
  [[ -z "$comment_id" ]] && return 0

  local marker="<!-- gh-pm:${task_id} -->"
  local ts
  ts="$(date -u +%Y-%m-%d\ %H:%M:%S\ UTC)"

  local body="${marker}
## 🤖 gh-pm: Task Failed

| Field | Value |
|-------|-------|
| Task ID | \`${task_id}\` |
| Status | ❌ Failed |
| Updated | ${ts} |

### Error

${error_msg}

_Managed by gh-pm._"

  gh_update_comment "$repo" "$comment_id" "$body"
}
