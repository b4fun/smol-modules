#!/usr/bin/env bash
# host-status/lib/server.sh — HTTP server for pull-based status queries

# start_http_server — start a simple HTTP server using socat or nc
start_http_server() {
  local port
  port="$(config_get_setting pull_port)"
  
  log_info "server" "Starting HTTP server on port $port"

  # Check if socat is available (preferred)
  if command -v socat &>/dev/null; then
    start_http_server_socat "$port"
  elif command -v nc &>/dev/null; then
    start_http_server_nc "$port"
  else
    log_error "server" "Neither socat nor nc available, cannot start HTTP server"
    return 1
  fi
}

# start_http_server_socat — HTTP server using socat
start_http_server_socat() {
  local port="$1"
  log_debug "server" "Using socat for HTTP server"
  
  while true; do
    # Listen for a connection and handle request
    socat TCP-LISTEN:"$port",fork,reuseaddr SYSTEM:"bash -c 'handle_http_request'" || true
    sleep 0.1
  done
}

# start_http_server_nc — HTTP server using netcat  
start_http_server_nc() {
  local port="$1"
  log_debug "server" "Using nc for HTTP server"
  
  # Detect nc flavor
  if nc -h 2>&1 | grep -q "OpenBSD"; then
    # OpenBSD netcat: nc -l port
    while true; do
      handle_http_request | nc -l "$port" || true
      sleep 0.1
    done
  else
    # GNU netcat: nc -l -p port
    while true; do
      handle_http_request | nc -l -p "$port" || true
      sleep 0.1
    done
  fi
}

# handle_http_request — read HTTP request and route to handler
handle_http_request() {
  # Read HTTP request line
  local request_line method path
  read -r request_line || return
  method="$(echo "$request_line" | cut -d' ' -f1)"
  path="$(echo "$request_line" | cut -d' ' -f2)"

  # Consume headers (read until empty line)
  while IFS= read -r line; do
    line="$(echo "$line" | tr -d '\r')"
    [[ -z "$line" ]] && break
  done

  log_debug "server" "Received $method request for $path"

  # Route the request
  case "$path" in
    /status)
      handle_status_request
      ;;
    /health)
      handle_health_request
      ;;
    *)
      handle_404_request "$path"
      ;;
  esac
}

# handle_status_request — return full status JSON
handle_status_request() {
  log_info "server" "Handling /status request"
  
  local status_json
  if status_json="$(collect_all_providers)"; then
    local content_length=${#status_json}
    
    echo "HTTP/1.1 200 OK"
    echo "Content-Type: application/json"
    echo "Content-Length: $content_length"
    echo "Connection: close"
    echo ""
    echo "$status_json"
  else
    log_error "server" "Failed to collect status"
    echo "HTTP/1.1 500 Internal Server Error"
    echo "Content-Type: application/json"
    echo "Connection: close"
    echo ""
    echo '{"error":"Failed to collect status"}'
  fi
}

# handle_health_request — return simple health check
handle_health_request() {
  log_debug "server" "Handling /health request"
  
  local response='{"status":"ok"}'
  local content_length=${#response}
  
  echo "HTTP/1.1 200 OK"
  echo "Content-Type: application/json"
  echo "Content-Length: $content_length"
  echo "Connection: close"
  echo ""
  echo "$response"
}

# handle_404_request — return 404 for unknown paths
handle_404_request() {
  local path="$1"
  log_debug "server" "Handling 404 for $path"
  
  local response='{"error":"Not found"}'
  local content_length=${#response}
  
  echo "HTTP/1.1 404 Not Found"
  echo "Content-Type: application/json"
  echo "Content-Length: $content_length"
  echo "Connection: close"
  echo ""
  echo "$response"
}
