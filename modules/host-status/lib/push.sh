#!/usr/bin/env bash
# host-status/lib/push.sh — Periodic push of status to remote endpoint

# start_push_loop — periodically collect and push status
start_push_loop() {
  local push_url
  push_url="$(config_get_setting push_url)"
  local push_interval
  push_interval="$(config_get_setting push_interval)"

  if [[ -z "$push_url" ]]; then
    log_error "push" "Push URL not configured, cannot start push mode"
    return 1
  fi

  log_info "push" "Starting push loop (interval: ${push_interval}s, url: $push_url)"

  while true; do
    log_debug "push" "Collecting status for push"
    
    local status_json
    if status_json="$(collect_all_providers)"; then
      push_status "$push_url" "$status_json"
    else
      log_error "push" "Failed to collect status"
    fi

    log_debug "push" "Sleeping for ${push_interval}s"
    sleep "$push_interval"
  done
}

# push_status URL JSON — POST status JSON to remote endpoint
push_status() {
  local url="$1"
  local json="$2"

  # In dry-run mode, just log what we would send
  if [[ "${HOST_STATUS_DRY_RUN:-0}" == "1" ]]; then
    log_info "push" "[DRY-RUN] Would POST to $url"
    log_debug "push" "[DRY-RUN] Payload: $json"
    return 0
  fi

  log_info "push" "Pushing status to $url"
  
  local response http_code
  http_code="$(curl -s -w '%{http_code}' -o /dev/null \
    -X POST \
    -H 'Content-Type: application/json' \
    -d "$json" \
    "$url")"

  if [[ "$http_code" -ge 200 && "$http_code" -lt 300 ]]; then
    log_info "push" "Successfully pushed status (HTTP $http_code)"
  else
    log_error "push" "Failed to push status (HTTP $http_code)"
  fi
}
