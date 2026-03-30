#!/usr/bin/env bash
# gh-pm/lib/llm.sh — LLM interaction layer
# Calls the configured LLM backend and returns response text.

# llm_call PROFILE SYSTEM_PROMPT USER_PROMPT — returns response text.
llm_call() {
  local profile="$1" system_prompt="$2" user_prompt="$3"

  if [[ "${GH_PM_DRY_RUN:-0}" == "1" ]]; then
    log_info "llm" "[DRY-RUN] LLM call with profile=$profile"
    echo "--- system prompt ---" >&2
    echo "$system_prompt" >&2
    echo "--- user prompt ---" >&2
    echo "$user_prompt" >&2
    echo "[DRY-RUN] This is a mock LLM analysis response for task processing."
    return 0
  fi

  local backend
  backend="$(config_get_profile_field "$profile" backend)"

  if [[ -z "$backend" ]]; then
    _llm_call_openai_compat "$profile" "$system_prompt" "$user_prompt"
  else
    _llm_call_backend "$backend" "$profile" "$system_prompt" "$user_prompt"
  fi
}

# _llm_call_openai_compat PROFILE SYSTEM USER — OpenAI-compatible HTTP call.
_llm_call_openai_compat() {
  local profile="$1" system_prompt="$2" user_prompt="$3"

  local api_url model api_key_env api_key
  api_url="$(config_get_profile_field "$profile" api_url)"
  model="$(config_get_profile_field "$profile" model)"
  api_key_env="$(config_get_profile_field "$profile" api_key_env)"

  if [[ -z "$api_url" || -z "$model" ]]; then
    log_error "llm" "Profile '$profile' missing api_url or model"
    return 1
  fi

  # Resolve API key (optional for local models)
  api_key=""
  if [[ -n "$api_key_env" ]]; then
    api_key="${!api_key_env:-}"
    if [[ -z "$api_key" ]]; then
      log_error "llm" "Env var '$api_key_env' not set (required by profile '$profile')"
      return 1
    fi
  fi

  local payload
  payload="$(jq -n \
    --arg model "$model" \
    --arg sys "$system_prompt" \
    --arg usr "$user_prompt" \
    '{
      model: $model,
      messages: [
        {role: "system", content: $sys},
        {role: "user",   content: $usr}
      ]
    }')"

  local curl_args=(-s -f -X POST "${api_url}/chat/completions" \
    -H "Content-Type: application/json" \
    -d "$payload")

  if [[ -n "$api_key" ]]; then
    curl_args+=(-H "Authorization: Bearer ${api_key}")
  fi

  local response
  if ! response="$(curl "${curl_args[@]}")"; then
    log_error "llm" "HTTP request to $api_url failed"
    return 1
  fi

  local content
  content="$(echo "$response" | jq -r '.choices[0].message.content // empty')"
  if [[ -z "$content" ]]; then
    log_error "llm" "Empty response from LLM"
    return 1
  fi
  echo "$content"
}

# _llm_call_backend BACKEND PROFILE SYSTEM USER — SDK wrapper call.
_llm_call_backend() {
  local backend="$1" profile="$2" system_prompt="$3" user_prompt="$4"

  local model api_key_env
  model="$(config_get_profile_field "$profile" model)"
  api_key_env="$(config_get_profile_field "$profile" api_key_env)"

  local script="${GH_PM_DIR}/backends/${backend}"
  if [[ ! -x "$script" ]]; then
    log_error "llm" "Backend script not found or not executable: $script"
    return 1
  fi

  "$script" \
    --model "$model" \
    --api-key-env "${api_key_env:-}" \
    --system "$system_prompt" \
    --user "$user_prompt"
}
