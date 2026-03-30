#!/usr/bin/env bash
# gh-pm/lib/dispatch.sh — Workflow dispatch and monitoring
# Spawns workflow processes and tracks their lifecycle.

# dispatch_task TASK_DIR — spawn the workflow command for a task.
# Writes dispatch.json with PID, timestamp, attempt count.
dispatch_task() {
  local task_dir="$1"

  local workflow_command
  workflow_command="$(config_get_setting workflow_command)"
  if [[ -z "$workflow_command" ]]; then
    log_error "dispatch" "No workflow_command configured in [settings]"
    return 1
  fi

  # Determine attempt number
  local attempt=1
  if [[ -f "$task_dir/dispatch.json" ]]; then
    attempt="$(jq -r '.attempt // 1' "$task_dir/dispatch.json")"
  fi

  local timeout_seconds
  timeout_seconds="$(config_get_setting workflow_timeout)"
  timeout_seconds="${timeout_seconds:-3600}"

  log_info "dispatch" "Dispatching task dir=$task_dir attempt=$attempt"

  if [[ "${GH_PM_DRY_RUN:-0}" == "1" ]]; then
    log_info "dispatch" "[DRY-RUN] Would run: $workflow_command '$task_dir'"
    jq -n --argjson attempt "$attempt" \
         --argjson timeout "$timeout_seconds" \
         --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      '{pid: 0, dispatched_at: $ts, attempt: $attempt, timeout_seconds: $timeout}' \
      > "$task_dir/dispatch.json"
    return 0
  fi

  # Spawn workflow in background via bash -c; capture PID.
  # The workflow receives the task directory as its sole argument.
  bash -c "$workflow_command \"$task_dir\"" > "$task_dir/workflow.log" 2>&1 &
  local pid=$!

  jq -n --argjson pid "$pid" \
       --argjson attempt "$attempt" \
       --argjson timeout "$timeout_seconds" \
       --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '{pid: $pid, dispatched_at: $ts, attempt: $attempt, timeout_seconds: $timeout}' \
    > "$task_dir/dispatch.json"

  log_info "dispatch" "Spawned PID=$pid for $task_dir"
}

# dispatch_check_status TASK_DIR — print one of: running, done, failed, timeout
dispatch_check_status() {
  local task_dir="$1"

  # Completed?
  if [[ -f "$task_dir/result.json" ]]; then
    local state
    state="$(jq -r '.state // "done"' "$task_dir/result.json")"
    if [[ "$state" == "failed" ]]; then
      echo "failed"
    else
      echo "done"
    fi
    return 0
  fi

  # No dispatch.json means not yet dispatched
  if [[ ! -f "$task_dir/dispatch.json" ]]; then
    echo "failed"
    return 0
  fi

  local pid dispatched_at timeout_seconds
  pid="$(jq -r '.pid // 0' "$task_dir/dispatch.json")"
  dispatched_at="$(jq -r '.dispatched_at // ""' "$task_dir/dispatch.json")"
  timeout_seconds="$(jq -r '.timeout_seconds // 3600' "$task_dir/dispatch.json")"

  # Check timeout
  if [[ -n "$dispatched_at" ]]; then
    local start_epoch now_epoch
    start_epoch="$(date -d "$dispatched_at" +%s 2>/dev/null || echo 0)"
    now_epoch="$(date +%s)"
    if (( now_epoch - start_epoch > timeout_seconds )); then
      echo "timeout"
      return 0
    fi
  fi

  # Process alive?
  if dispatch_is_process_alive "$pid"; then
    echo "running"
  else
    # Process exited without writing result.json → failed
    echo "failed"
  fi
}

# dispatch_handle_timeout TASK_DIR — kill if alive, retry or mark failed.
# Returns 0 if retrying, 1 if max retries exceeded.
dispatch_handle_timeout() {
  local task_dir="$1"

  local pid attempt max_retries
  pid="$(jq -r '.pid // 0' "$task_dir/dispatch.json")"
  attempt="$(jq -r '.attempt // 1' "$task_dir/dispatch.json")"
  max_retries="$(config_get_setting max_retries)"
  max_retries="${max_retries:-3}"

  # Kill if still running
  if dispatch_is_process_alive "$pid"; then
    log_warn "dispatch" "Killing timed-out PID=$pid"
    kill -TERM "$pid" 2>/dev/null || true
    sleep 2
    dispatch_is_process_alive "$pid" && kill -KILL "$pid" 2>/dev/null || true
  fi

  if (( attempt < max_retries )); then
    local next=$(( attempt + 1 ))
    log_info "dispatch" "Retrying task attempt=$next/$max_retries"
    # Update attempt and re-dispatch
    jq --argjson a "$next" '.attempt = $a' "$task_dir/dispatch.json" \
      > "$task_dir/dispatch.json.tmp"
    mv "$task_dir/dispatch.json.tmp" "$task_dir/dispatch.json"
    dispatch_task "$task_dir"
    return 0
  else
    log_error "dispatch" "Max retries ($max_retries) exceeded"
    jq -n --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      '{state:"failed", summary:"Workflow timed out after max retries", error:"timeout", completed_at:$ts}' \
      > "$task_dir/result.json"
    return 1
  fi
}

# dispatch_is_process_alive PID — return 0 if alive.
dispatch_is_process_alive() {
  local pid="$1"
  [[ "$pid" -gt 0 ]] 2>/dev/null || return 1
  [[ "${GH_PM_DRY_RUN:-0}" == "1" ]] && return 1
  kill -0 "$pid" 2>/dev/null
}
