#!/usr/bin/env bash
# host-status/lib/server.sh — HTTP server for pull-based status queries

# start_http_server — start a simple HTTP server using busybox httpd or nc
start_http_server() {
  local port
  port="$(config_get_setting pull_port)"
  
  log_info "server" "Starting HTTP server on port $port"

  # Create temporary directory for server
  local server_dir
  server_dir="$(mktemp -d)"
  trap "rm -rf '$server_dir'" EXIT

  # Main server loop using nc (netcat)
  while true; do
    # Listen for a single connection
    {
      # Read HTTP request
      local request_line method path
      read -r request_line
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
    } | nc -l -p "$port" || true

    # Small delay to prevent tight loop on error
    sleep 0.1
  done
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
