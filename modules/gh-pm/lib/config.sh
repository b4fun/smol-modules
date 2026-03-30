#!/usr/bin/env bash
# gh-pm/lib/config.sh — Configuration management
# Parses gh-pm.toml and provides config access functions.

# Global config storage
declare -g -A _GHPM_SETTINGS=()
declare -g -A _GHPM_PROFILES=()
declare -g -a _GHPM_REPOS=()

# Defaults
_GHPM_DEFAULTS_POLL_INTERVAL=60
_GHPM_DEFAULTS_WORKFLOW_TIMEOUT=3600
_GHPM_DEFAULTS_MAX_RETRIES=3
_GHPM_DEFAULTS_LOG_LEVEL="INFO"

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
  _GHPM_REPOS=()

  if [[ ! -f "$config_file" ]]; then
    return 0
  fi

  local current_section=""

  while IFS= read -r line || [[ -n "$line" ]]; do
    # Strip leading/trailing whitespace
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"

    # Skip empty lines and comments
    [[ -z "$line" || "$line" == \#* ]] && continue

    # Section headers: [settings] or [profiles.name]
    if [[ "$line" =~ ^\[([^]]+)\]$ ]]; then
      current_section="${BASH_REMATCH[1]}"
      continue
    fi

    # Key = value pairs
    if [[ "$line" =~ ^([a-zA-Z_][a-zA-Z0-9_]*)[\ ]*=[\ ]*(.+)$ ]]; then
      local key="${BASH_REMATCH[1]}"
      local value="${BASH_REMATCH[2]}"

      # Strip inline comments (outside quotes)
      if [[ "$value" =~ ^\".*\"$ ]] || [[ "$value" =~ ^\[.*\]$ ]]; then
        : # keep as-is for quoted strings and arrays
      else
        value="${value%%#*}"
        value="${value%"${value##*[![:space:]]}"}"
      fi

      # Handle arrays: repos = ["a", "b"]
      if [[ "$value" =~ ^\[(.*)\]$ ]]; then
        local inner="${BASH_REMATCH[1]}"
        if [[ "$key" == "repos" && "$current_section" == "settings" ]]; then
          _GHPM_REPOS=()
          # Extract quoted strings from the array
          local tmp="$inner"
          while [[ "$tmp" =~ \"([^\"]+)\" ]]; do
            _GHPM_REPOS+=("${BASH_REMATCH[1]}")
            tmp="${tmp#*\"${BASH_REMATCH[1]}\"}"
          done
        fi
        continue
      fi

      # Strip quotes from string values
      if [[ "$value" =~ ^\"(.*)\"$ ]]; then
        value="${BASH_REMATCH[1]}"
      elif [[ "$value" =~ ^\'(.*)\'$ ]]; then
        value="${BASH_REMATCH[1]}"
      fi

      if [[ "$current_section" == "settings" ]]; then
        _GHPM_SETTINGS["$key"]="$value"
      elif [[ "$current_section" =~ ^profiles\.(.+)$ ]]; then
        local profile_name="${BASH_REMATCH[1]}"
        _GHPM_PROFILES["${profile_name}.${key}"]="$value"
      fi
    fi
  done < "$config_file"
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
