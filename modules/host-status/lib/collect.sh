#!/usr/bin/env bash
# host-status/lib/collect.sh — Provider execution and status collection

# execute_provider PROVIDER_JSON — execute a single provider and return its JSON output
execute_provider() {
  local provider_json="$1"
  local timeout
  timeout="$(config_get_setting collection_timeout)"

  # Parse provider config
  local name command enabled args
  name="$(echo "$provider_json" | jq -r '.name // "unknown"')"
  command="$(echo "$provider_json" | jq -r '.command // ""')"
  enabled="$(echo "$provider_json" | jq -r 'if has("enabled") then .enabled | tostring else "true" end')"
  
  # Check if provider is enabled
  if [[ "$enabled" != "true" ]]; then
    log_debug "collect" "Provider '$name' is disabled, skipping"
    return 0
  fi

  if [[ -z "$command" ]]; then
    log_error "collect" "Provider '$name' has no command specified"
    return 1
  fi

  log_debug "collect" "Executing provider '$name': $command"

  # Build command with args
  local -a cmd_args=()
  local args_count
  args_count="$(echo "$provider_json" | jq '.args // [] | length')"
  if [[ "$args_count" -gt 0 ]]; then
    local i
    for (( i=0; i<args_count; i++ )); do
      cmd_args+=("$(echo "$provider_json" | jq -r ".args[$i]")")
    done
  fi

  # Execute provider with timeout
  local output exit_code
  set +e
  if [[ ${#cmd_args[@]} -gt 0 ]]; then
    output="$(timeout "$timeout" "$command" "${cmd_args[@]}" 2>&1)"
  else
    output="$(timeout "$timeout" "$command" 2>&1)"
  fi
  exit_code=$?
  set -e

  # Handle timeout (exit code 124)
  if [[ $exit_code -eq 124 ]]; then
    log_error "collect" "Provider '$name' timed out after ${timeout}s"
    echo '{"name":"'"$name"'","status":"unknown","message":"Provider timed out"}'
    return 0
  fi

  # Handle non-zero exit
  if [[ $exit_code -ne 0 ]]; then
    log_warn "collect" "Provider '$name' exited with code $exit_code"
    echo '{"name":"'"$name"'","status":"error","message":"Provider failed with exit code '"$exit_code"'"}'
    return 0
  fi

  # Validate JSON output
  if ! echo "$output" | jq empty 2>/dev/null; then
    log_error "collect" "Provider '$name' returned invalid JSON"
    echo '{"name":"'"$name"'","status":"error","message":"Invalid JSON output"}'
    return 0
  fi

  log_debug "collect" "Provider '$name' completed successfully"
  echo "$output"
}

# collect_all_providers — collect status from all enabled providers and return aggregated JSON
collect_all_providers() {
  local hostname
  hostname="$(config_get_setting hostname)"
  local timestamp
  timestamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

  log_info "collect" "Starting status collection for host '$hostname'"

  local -a provider_results=()
  local provider_count=0
  local success_count=0
  local error_count=0

  # Iterate over all providers
  while IFS= read -r provider_json; do
    [[ -z "$provider_json" ]] && continue
    ((provider_count++))
    
    local result
    if result="$(execute_provider "$provider_json")"; then
      if [[ -n "$result" ]]; then
        provider_results+=("$result")
        local status
        status="$(echo "$result" | jq -r '.status // "unknown"')"
        if [[ "$status" == "error" || "$status" == "unknown" ]]; then
          ((error_count++))
        else
          ((success_count++))
        fi
      fi
    else
      ((error_count++))
    fi
  done < <(config_get_providers)

  log_info "collect" "Collection complete: $success_count success, $error_count errors out of $provider_count providers"

  # Build aggregated status JSON
  local overall_status="ok"
  if [[ $error_count -gt 0 ]]; then
    if [[ $success_count -eq 0 ]]; then
      overall_status="critical"
    else
      overall_status="warning"
    fi
  fi

  # Construct JSON
  local providers_json="[]"
  if [[ ${#provider_results[@]} -gt 0 ]]; then
    providers_json="$(printf '%s\n' "${provider_results[@]}" | jq -s '.')"
  fi

  jq -n \
    --arg hostname "$hostname" \
    --arg timestamp "$timestamp" \
    --arg status "$overall_status" \
    --argjson providers "$providers_json" \
    '{
      hostname: $hostname,
      timestamp: $timestamp,
      status: $status,
      providers: $providers
    }'
}
