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

  case "${backend:-openai}" in
    openai|"")
      _llm_call_openai_compat "$profile" "$system_prompt" "$user_prompt"
      ;;
    shelley)
      _llm_call_shelley "$profile" "$system_prompt" "$user_prompt"
      ;;
    *)
      _llm_call_backend "$backend" "$profile" "$system_prompt" "$user_prompt"
      ;;
  esac
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

# _llm_call_shelley PROFILE SYSTEM USER — call shelley agent via CLI.
_llm_call_shelley() {
  local profile="$1" system_prompt="$2" user_prompt="$3"

  local shelley_url model
  shelley_url="$(config_get_profile_field "$profile" shelley_url)"
  shelley_url="${shelley_url:-unix:///home/${USER}/.config/shelley/shelley.sock}"
  model="$(config_get_profile_field "$profile" model)"

  if ! command -v shelley &>/dev/null; then
    log_error "llm" "shelley CLI not found in PATH"
    return 1
  fi

  # Combine system + user prompts (shelley client has no separate system prompt)
  local combined_prompt="${system_prompt}

---

${user_prompt}"

  local chat_args=(client -url "$shelley_url" chat -p "$combined_prompt")
  if [[ -n "$model" ]]; then
    chat_args+=(-model "$model")
  fi

  local chat_response
  if ! chat_response="$(shelley "${chat_args[@]}" 2>/dev/null)"; then
    log_error "llm" "shelley chat request failed"
    return 1
  fi

  local conv_id
  conv_id="$(echo "$chat_response" | jq -r '.conversation_id // empty')"
  if [[ -z "$conv_id" ]]; then
    log_error "llm" "No conversation_id in shelley response"
    return 1
  fi

  log_debug "llm" "shelley conversation: $conv_id"

  # Wait for the agent turn to complete and extract the final response
  local read_output
  if ! read_output="$(shelley client -url "$shelley_url" read -wait "$conv_id" 2>/dev/null)"; then
    log_error "llm" "shelley read failed for conversation $conv_id"
    return 1
  fi

  # Extract the last agent message with end_of_turn=true
  local content
  content="$(echo "$read_output" | jq -rs '[.[] | select(.type=="agent" and .end_of_turn==true)] | last | .text // empty')"
  if [[ -z "$content" ]]; then
    log_error "llm" "Empty response from shelley agent"
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
