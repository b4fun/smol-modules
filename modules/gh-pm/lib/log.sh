#!/usr/bin/env bash
# gh-pm/lib/log.sh — Structured logging
# Levels: DEBUG(0) INFO(1) WARN(2) ERROR(3)
# Format: <ISO-8601> <LEVEL> <COMPONENT> <MESSAGE>

declare -g _GHPM_LOG_LEVEL_NUM=1
declare -g _GHPM_LOG_FILE=""
declare -g _GHPM_TASK_LOG_FILE=""

_log_level_to_num() {
  case "${1^^}" in
    DEBUG) echo 0 ;;
    INFO)  echo 1 ;;
    WARN)  echo 2 ;;
    ERROR) echo 3 ;;
    *)     echo 1 ;;
  esac
}

# log_init — initialize logging from config. Call after config_load.
log_init() {
  local level_name
  level_name="$(config_get_setting log_level)"
  level_name="${level_name:-INFO}"
  _GHPM_LOG_LEVEL_NUM="$(_log_level_to_num "$level_name")"

  _GHPM_LOG_FILE="$(config_get_setting log_file)"
  if [[ -n "$_GHPM_LOG_FILE" ]]; then
    # Expand ~ if present
    _GHPM_LOG_FILE="${_GHPM_LOG_FILE/#\~/$HOME}"
    mkdir -p "$(dirname "$_GHPM_LOG_FILE")"
  fi

  # In dry-run mode, default to DEBUG
  if [[ "${GH_PM_DRY_RUN:-0}" == "1" ]]; then
    _GHPM_LOG_LEVEL_NUM=0
  fi
}

# _log_write LEVEL_NAME COMPONENT MESSAGE
_log_write() {
  local level_name="$1" component="$2" msg="$3"
  local level_num
  level_num="$(_log_level_to_num "$level_name")"
  [[ "$level_num" -lt "$_GHPM_LOG_LEVEL_NUM" ]] && return 0

  local ts
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  local line="$ts $level_name $component $msg"

  echo "$line" >&2
  if [[ -n "$_GHPM_LOG_FILE" ]]; then echo "$line" >> "$_GHPM_LOG_FILE"; fi
  if [[ -n "$_GHPM_TASK_LOG_FILE" ]]; then echo "$line" >> "$_GHPM_TASK_LOG_FILE"; fi
  return 0
}

log_debug() { _log_write DEBUG  "$1" "$2"; }
log_info()  { _log_write INFO   "$1" "$2"; }
log_warn()  { _log_write WARN   "$1" "$2"; }
log_error() { _log_write ERROR  "$1" "$2"; }

# log_task_init TASK_ID — set per-task log file.
log_task_init() {
  local task_id="$1"
  local task_dir="${GH_PM_WORKSPACE}/${task_id}"
  mkdir -p "$task_dir"
  _GHPM_TASK_LOG_FILE="$task_dir/gh-pm.log"
}

# log_task_reset — clear per-task log file (call after task processing).
log_task_reset() {
  _GHPM_TASK_LOG_FILE=""
}
