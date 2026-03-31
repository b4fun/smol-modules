#!/usr/bin/env bash
# gh-pm/lib/config.sh — Configuration management
# Parses gh-pm.toml via toml2json + jq and provides config access functions.

# Global config storage
declare -g -A _GHPM_SETTINGS=()
declare -g -A _GHPM_PROFILES=()
declare -g -a _GHPM_REPOS=()

# Defaults
_GHPM_DEFAULTS_POLL_INTERVAL=60
_GHPM_DEFAULTS_WORKFLOW_TIMEOUT=3600
_GHPM_DEFAULTS_MAX_RETRIES=3
_GHPM_DEFAULTS_LOG_LEVEL="INFO"
_GHPM_DEFAULTS_ATTACH_SUMMARIES="false"
_GHPM_DEFAULTS_SUMMARY_ANALYZE="true"
_GHPM_DEFAULTS_SUMMARY_RUNNING="true"
_GHPM_DEFAULTS_SUMMARY_FORMAT="detailed"
_GHPM_DEFAULTS_SUMMARY_USE_COLLAPSIBLE="true"
_GHPM_DEFAULTS_SUMMARY_MAX_LENGTH="10000"

# config_load — parse the TOML config file and populate globals.
config_load() {
  local config_file="${GH_PM_CONFIG:-$HOME/.gh-pm/gh-pm.toml}"

  # Set defaults
  _GHPM_SETTINGS[poll_interval]="$_GHPM_DEFAULTS_POLL_INTERVAL"
  _GHPM_SETTINGS[workflow_timeout]="$_GHPM_DEFAULTS_WORKFLOW_TIMEOUT"
  _GHPM_SETTINGS[max_retries]="$_GHPM_DEFAULTS_MAX_RETRIES"
  _GHPM_SETTINGS[log_level]="$_GHPM_DEFAULTS_LOG_LEVEL"
  _GHPM_SETTINGS[log_file]=""
  _GHPM_SETTINGS[workflow_command]=""
  _GHPM_SETTINGS[workflow_policy]=""
  _GHPM_SETTINGS[attach_summaries]="$_GHPM_DEFAULTS_ATTACH_SUMMARIES"
  _GHPM_SETTINGS[summary_analyze]="$_GHPM_DEFAULTS_SUMMARY_ANALYZE"
  _GHPM_SETTINGS[summary_running]="$_GHPM_DEFAULTS_SUMMARY_RUNNING"
  _GHPM_SETTINGS[summary_format]="$_GHPM_DEFAULTS_SUMMARY_FORMAT"
  _GHPM_SETTINGS[summary_use_collapsible]="$_GHPM_DEFAULTS_SUMMARY_USE_COLLAPSIBLE"
  _GHPM_SETTINGS[summary_max_length]="$_GHPM_DEFAULTS_SUMMARY_MAX_LENGTH"
  _GHPM_REPOS=()

  if [[ ! -f "$config_file" ]]; then
    return 0
  fi

  # Parse TOML to JSON using toml2json
  local json
  if ! json="$(toml2json < "$config_file")"; then
    echo "gh-pm: error: failed to parse config file: $config_file" >&2
    return 1
  fi

  # Load [settings] scalars
  local -a setting_keys=(poll_interval workflow_timeout max_retries log_level log_file workflow_command workflow_policy attach_summaries summary_analyze summary_running summary_format summary_use_collapsible summary_max_length)
  for key in "${setting_keys[@]}"; do
    local val
    # Use conditional to handle boolean false values (which would be filtered by '// empty')
    val="$(echo "$json" | jq -r "if .settings.${key} == null then \"\" else .settings.${key} | tostring end")"
    if [[ -n "$val" ]]; then
      _GHPM_SETTINGS["$key"]="$val"
    fi
  done

  # Load [settings].repos array
  local repo_count
  repo_count="$(echo "$json" | jq '.settings.repos // [] | length')"
  if [[ "$repo_count" -gt 0 ]]; then
    _GHPM_REPOS=()
    local i
    for (( i=0; i<repo_count; i++ )); do
      _GHPM_REPOS+=("$(echo "$json" | jq -r ".settings.repos[$i]")")
    done
  fi

  # Load [profiles.*] sections
  local profile_names
  profile_names="$(echo "$json" | jq -r '.profiles // {} | keys[]')"
  while IFS= read -r profile_name; do
    [[ -z "$profile_name" ]] && continue
    local profile_keys
    profile_keys="$(echo "$json" | jq -r ".profiles[\"${profile_name}\"] // {} | keys[]")"
    while IFS= read -r field; do
      [[ -z "$field" ]] && continue
      local field_val
      field_val="$(echo "$json" | jq -r ".profiles[\"${profile_name}\"][\"${field}\"] // empty")"
      if [[ -n "$field_val" ]]; then
        _GHPM_PROFILES["${profile_name}.${field}"]="$field_val"
      fi
    done <<< "$profile_keys"
  done <<< "$profile_names"
}

# config_get_setting KEY — get a setting value.
config_get_setting() {
  echo "${_GHPM_SETTINGS[${1}]:-}"
}

# config_get_profile_field PROFILE FIELD — get a profile field.
config_get_profile_field() {
  echo "${_GHPM_PROFILES["${1}.${2}"]:-}"
}

# config_get_repos — print repos, one per line.
config_get_repos() {
  if [[ ${#_GHPM_REPOS[@]} -gt 0 ]]; then
    printf '%s\n' "${_GHPM_REPOS[@]}"
  fi
}

# config_resolve_profile LABELS_CSV — resolve LLM profile from labels/env/default.
# Priority: gh-pm:profile=NAME label > GH_PM_LLM_PROFILE env > "default"
config_resolve_profile() {
  local labels_csv="${1:-}"

  # Check labels for gh-pm:profile=NAME
  if [[ -n "$labels_csv" ]]; then
    local IFS=','
    for label in $labels_csv; do
      # Trim whitespace
      label="${label#"${label%%[![:space:]]*}"}"
      label="${label%"${label##*[![:space:]]}"}"
      if [[ "$label" =~ ^gh-pm:profile=(.+)$ ]]; then
        echo "${BASH_REMATCH[1]}"
        return 0
      fi
    done
  fi

  # Check env var
  if [[ -n "${GH_PM_LLM_PROFILE:-}" ]]; then
    echo "$GH_PM_LLM_PROFILE"
    return 0
  fi

  echo "default"
}



# _get_summary_settings — return summary configuration settings
# Returns: attach_summaries summary_analyze summary_running summary_completion summary_use_collapsible summary_max_length
_get_summary_settings() {
  local attach="${_GHPM_SETTINGS[attach_summaries]:-false}"
  local analyze="${_GHPM_SETTINGS[summary_analyze]:-true}"
  local running="${_GHPM_SETTINGS[summary_running]:-false}"
  local completion="${_GHPM_SETTINGS[summary_completion]:-true}"
  local collapsible="${_GHPM_SETTINGS[summary_use_collapsible]:-true}"
  local max_length="${_GHPM_SETTINGS[summary_max_length]:-5000}"
  echo "$attach" "$analyze" "$running" "$completion" "$collapsible" "$max_length"
}

# _format_summary CONTENT MAX_LENGTH USE_COLLAPSIBLE [TITLE]
# Format a summary section with optional truncation and collapsible wrapper
_format_summary() {
  local content="$1" max_length="$2" use_collapsible="$3" title="${4:-View Details}"
  
  # Truncate if needed
  if [[ ${#content} -gt $max_length ]]; then
    local truncated="${content:0:$max_length}"
    # Try to truncate at a newline to avoid breaking mid-line
    if [[ "$truncated" =~ (.*)$'\n' ]]; then
      truncated="${BASH_REMATCH[1]}"
    fi
    content="${truncated}

_[Content truncated at ${max_length} characters]_"
  fi
  
  # Wrap in collapsible section if enabled
  if [[ "$use_collapsible" == "true" ]]; then
    echo "<details>"
    echo "<summary>${title}</summary>"
    echo ""
    echo "${content}"
    echo ""
    echo "</details>"
  else
    echo "${content}"
  fi
}
