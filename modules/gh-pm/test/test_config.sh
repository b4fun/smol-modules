#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source ./helpers.sh
TEST_NAME="config"
echo "Running config tests..."

# --- Test: parse valid config ---
setup_test_env; write_test_config; config_load
assert_eq "30" "$(config_get_setting poll_interval)" "poll_interval parsed"
assert_eq "1800" "$(config_get_setting workflow_timeout)" "workflow_timeout parsed"
assert_eq "2" "$(config_get_setting max_retries)" "max_retries parsed"
assert_eq "DEBUG" "$(config_get_setting log_level)" "log_level parsed"
assert_eq "echo mock-workflow" "$(config_get_setting workflow_command)" "workflow_command parsed"
teardown_test_env

# --- Test: repos list ---
setup_test_env; write_test_config; config_load
local_repos="$(config_get_repos)"
assert_contains "$local_repos" "test-org/test-repo" "repos has first entry"
assert_contains "$local_repos" "test-org/another-repo" "repos has second entry"
assert_eq "2" "$(echo "$local_repos" | wc -l | tr -d ' ')" "repos count is 2"
teardown_test_env

# --- Test: profile fields ---
setup_test_env; write_test_config; config_load
assert_eq "gpt-4o" "$(config_get_profile_field default model)" "default profile model"
assert_eq "https://api.openai.com/v1" "$(config_get_profile_field default api_url)" "default profile api_url"
assert_eq "OPENAI_API_KEY" "$(config_get_profile_field default api_key_env)" "default profile api_key_env"
assert_eq "" "$(config_get_profile_field default backend)" "default profile has no backend"
assert_eq "anthropic" "$(config_get_profile_field claude backend)" "claude profile backend"
assert_eq "claude-sonnet-4-20250514" "$(config_get_profile_field claude model)" "claude profile model"
assert_eq "llama3" "$(config_get_profile_field local model)" "local profile model"
assert_eq "http://localhost:11434/v1" "$(config_get_profile_field local api_url)" "local profile api_url"
teardown_test_env

# --- Test: profile resolution - label wins ---
setup_test_env; write_test_config; config_load
assert_eq "claude" "$(config_resolve_profile "bug,gh-pm:profile=claude,help")" "label selects profile"
teardown_test_env

# --- Test: profile resolution - env wins over default ---
setup_test_env; write_test_config; config_load
export GH_PM_LLM_PROFILE="local"
assert_eq "local" "$(config_resolve_profile "bug,help")" "env var selects profile"
unset GH_PM_LLM_PROFILE
teardown_test_env

# --- Test: profile resolution - label beats env ---
setup_test_env; write_test_config; config_load
export GH_PM_LLM_PROFILE="local"
assert_eq "claude" "$(config_resolve_profile "gh-pm:profile=claude")" "label beats env"
unset GH_PM_LLM_PROFILE
teardown_test_env

# --- Test: profile resolution - falls back to default ---
setup_test_env; write_test_config; config_load
assert_eq "default" "$(config_resolve_profile "bug,help")" "falls back to default"
assert_eq "default" "$(config_resolve_profile "")" "empty labels falls back to default"
teardown_test_env

# --- Test: defaults when no config file ---
setup_test_env
# Don't write a config file
config_load
assert_eq "60" "$(config_get_setting poll_interval)" "default poll_interval"
assert_eq "3600" "$(config_get_setting workflow_timeout)" "default workflow_timeout"
assert_eq "3" "$(config_get_setting max_retries)" "default max_retries"
assert_eq "INFO" "$(config_get_setting log_level)" "default log_level"
teardown_test_env

print_test_summary
