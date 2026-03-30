#!/usr/bin/env bash
# host-status/lib/config.sh — Configuration management
# Parses host-status.toml via toml2json + jq and provides config access functions.

# Global config storage
declare -g -A _HOSTSTATUS_SETTINGS=()
declare -g -a _HOSTSTATUS_PROVIDERS=()

# Defaults
_HOSTSTATUS_DEFAULTS_PUSH_INTERVAL=300
_HOSTSTATUS_DEFAULTS_PULL_PORT=8080
_HOSTSTATUS_DEFAULTS_COLLECTION_TIMEOUT=10
_HOSTSTATUS_DEFAULTS_LOG_LEVEL="INFO"

# config_load — parse the TOML config file and populate globals.
config_load() {
  local config_file="${HOST_STATUS_CONFIG:-$HOME/.host-status/host-status.toml}"

  # Set defaults
  _HOSTSTATUS_SETTINGS[hostname]="$(hostname)"
  _HOSTSTATUS_SETTINGS[push_enabled]="false"
  _HOSTSTATUS_SETTINGS[push_url]=""
  _HOSTSTATUS_SETTINGS[push_interval]="$_HOSTSTATUS_DEFAULTS_PUSH_INTERVAL"
  _HOSTSTATUS_SETTINGS[pull_enabled]="true"
  _HOSTSTATUS_SETTINGS[pull_port]="$_HOSTSTATUS_DEFAULTS_PULL_PORT"
  _HOSTSTATUS_SETTINGS[collection_timeout]="$_HOSTSTATUS_DEFAULTS_COLLECTION_TIMEOUT"
  _HOSTSTATUS_SETTINGS[log_level]="$_HOSTSTATUS_DEFAULTS_LOG_LEVEL"
  _HOSTSTATUS_SETTINGS[log_file]=""
  _HOSTSTATUS_PROVIDERS=()

  if [[ ! -f "$config_file" ]]; then
    return 0
  fi

  # Parse TOML to JSON using toml2json
  local json
  if ! json="$(toml2json < "$config_file")" || [[ -z "$json" ]]; then
    echo "host-status: error: failed to parse config file: $config_file" >&2
    return 1
  fi

  # Load [settings] scalars
  # For boolean fields, use 'tostring' to convert false to "false" string
  local -a bool_keys=(push_enabled pull_enabled)
  for key in "${bool_keys[@]}"; do
    local val
    val="$(echo "$json" | jq -r ".settings.${key} | tostring")"
    if [[ "$val" != "null" ]]; then
      _HOSTSTATUS_SETTINGS["$key"]="$val"
    fi
  done
  
  # For other fields, use normal extraction
  local -a setting_keys=(hostname push_url push_interval pull_port collection_timeout log_level log_file)
  for key in "${setting_keys[@]}"; do
    local val
    val="$(echo "$json" | jq -r ".settings.${key} // empty")"
    if [[ -n "$val" ]]; then
      _HOSTSTATUS_SETTINGS["$key"]="$val"
    fi
  done

  # Load [[providers]] array
  local provider_count
  provider_count="$(echo "$json" | jq '.providers // [] | length')"
  if [[ "$provider_count" -gt 0 ]]; then
    _HOSTSTATUS_PROVIDERS=()
    local i
    for (( i=0; i<provider_count; i++ )); do
      local provider_json
      provider_json="$(echo "$json" | jq -c ".providers[$i]")"
      _HOSTSTATUS_PROVIDERS+=("$provider_json")
    done
  fi
}

# config_get_setting KEY — get a setting value.
config_get_setting() {
  echo "${_HOSTSTATUS_SETTINGS[$1]:-}"
}

# config_get_providers — return the providers array (one JSON object per line)
config_get_providers() {
  printf '%s\n' "${_HOSTSTATUS_PROVIDERS[@]}"
}

# config_get_provider_count — return the number of providers
config_get_provider_count() {
  echo "${#_HOSTSTATUS_PROVIDERS[@]}"
}
