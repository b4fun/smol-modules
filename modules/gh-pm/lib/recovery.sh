#!/usr/bin/env bash
# gh-pm/lib/recovery.sh — Startup recovery
# Scans workspace and reconciles in-flight tasks after a restart.

recovery_run() {
  local workspace="$GH_PM_WORKSPACE"
  [[ ! -d "$workspace" ]] && return 0

  local count=0

  for task_dir in "$workspace"/*/; do
    [[ ! -d "$task_dir" ]] && continue
    if [[ ! -f "$task_dir/task.json" ]]; then
      log_warn "recovery" "Removing incomplete task dir: $(basename "$task_dir") (no task.json)"
      rm -rf "$task_dir"
      continue
    fi

    local task_id
    task_id="$(basename "$task_dir")"
    log_task_init "$task_id"

    local repo number source_type
    repo="$(jq -r '.source.repo // empty' "$task_dir/task.json" 2>/dev/null)"
    number="$(jq -r '.source.number // empty' "$task_dir/task.json" 2>/dev/null)"
    source_type="$(jq -r '.source.type // empty' "$task_dir/task.json" 2>/dev/null)"

    if [[ -z "$repo" || -z "$number" ]]; then
      log_warn "recovery" "Task $task_id has invalid task.json, skipping"
      log_task_reset
      continue
    fi

    # Case 1: completed (has result.json)
    if [[ -f "$task_dir/result.json" ]]; then
      log_info "recovery" "Task $task_id completed, checking if reported"
      local comment_id
      comment_id="$(gh_find_tracking_comment "$repo" "$number" "$task_id")"
      if [[ -n "$comment_id" ]]; then
        # Check if already shows completion
        local body
        body="$(gh api "repos/${repo}/issues/comments/${comment_id}" --jq '.body' 2>/dev/null || echo '')"
        if echo "$body" | grep -q 'Completed\|Failed'; then
          log_debug "recovery" "Task $task_id already reported"
        else
          report_completion "$repo" "$number" "$task_id" "$task_dir/result.json" || true
        fi
      else
        report_completion "$repo" "$number" "$task_id" "$task_dir/result.json" || true
      fi
      (( count++ )) || true
    log_task_reset
    continue
  fi

  # Case 2: dispatched but not completed (has dispatch.json)
  if [[ -f "$task_dir/dispatch.json" ]]; then
      local pid
      pid="$(jq -r '.pid // 0' "$task_dir/dispatch.json")"

      if dispatch_is_process_alive "$pid"; then
        log_info "recovery" "Task $task_id PID=$pid still running, resuming monitor"
      else
        log_warn "recovery" "Task $task_id PID=$pid dead, treating as timeout"
        local attempt max_retries
        attempt="$(jq -r '.attempt // 1' "$task_dir/dispatch.json")"
        max_retries="$(config_get_setting max_retries)"
        max_retries="${max_retries:-3}"

        if dispatch_handle_timeout "$task_dir"; then
          report_timeout "$repo" "$number" "$task_id" "$attempt" "$max_retries" || true
        else
          report_failure "$repo" "$number" "$task_id" "Workflow timed out after $max_retries retries" || true
        fi
      fi
      (( count++ )) || true
      log_task_reset
      continue
    fi

    # Case 3: task.json only — never dispatched
    log_info "recovery" "Task $task_id never dispatched, dispatching now"
    if dispatch_task "$task_dir"; then
      report_dispatch "$repo" "$number" "$task_id" || true
    else
      log_error "recovery" "Failed to dispatch $task_id"
    fi
    (( count++ )) || true
    log_task_reset
  done

  if [[ $count -gt 0 ]]; then
    log_info "recovery" "Recovered $count task(s)"
  fi
}
