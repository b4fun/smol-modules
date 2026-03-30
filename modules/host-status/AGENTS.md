# host-status - Agent Guidance

This document provides context and guidance for LLM agents working with the `host-status` module.

## Module Purpose

The `host-status` module is a lightweight host monitoring daemon designed for:

- Collecting system metrics (CPU, memory, disk, uptime)
- Supporting extensible custom metrics via provider scripts
- Operating in dual modes: pull (HTTP API) and push (periodic POST)
- Running as a systemd service or standalone daemon
- Integration with monitoring and alerting systems

## Design Philosophy

1. **Simplicity**: Pure bash with minimal dependencies (jq, curl, nc)
2. **Extensibility**: Provider-based architecture allows custom metrics without code changes
3. **Robustness**: Timeouts, error handling, graceful degradation
4. **Flexibility**: Both pull and push modes, configurable intervals
5. **Transparency**: Structured JSON output, detailed logging

## Key Design Decisions

### Provider Protocol

- **Simple**: Providers are executable scripts that output JSON to stdout
- **Language-agnostic**: Any language that can output JSON works
- **Timeout-protected**: Each provider execution has a configurable timeout
- **Non-blocking**: Provider failures don't crash the daemon
- **Validated**: JSON output is validated before aggregation

### Configuration

- **TOML format**: Human-readable, hierarchical, same as gh-pm module
- **Parsed via toml2json + jq**: Avoids custom parser implementation
- **Defaults**: Sensible defaults mean minimal config required
- **Per-provider config**: Each provider can have args and enabled flag

### HTTP Server (Pull Mode)

- **Lightweight**: Uses netcat (nc) in a loop, no heavy HTTP server needed
- **Two endpoints**: `/status` (full JSON) and `/health` (simple check)
- **Stateless**: Collects fresh status on each request
- **Non-blocking**: Runs as background job

### Push Mode

- **Timer-based**: Simple sleep loop, no cron dependency
- **Retries**: HTTP failures are logged but don't stop the loop
- **Dry-run support**: Test configuration without actual HTTP requests

## Code Organization

```
bin/host-status                    # Main daemon orchestrator
bin/host-status-provider-system    # Built-in system metrics provider

lib/log.sh                         # Structured logging (DEBUG/INFO/WARN/ERROR)
lib/config.sh                      # TOML config parsing and access
lib/collect.sh                     # Provider execution and status collection
lib/server.sh                      # HTTP server for pull mode
lib/push.sh                        # Periodic push loop

test/helpers.sh                    # Test utilities (assert_eq, etc.)
test/test_config.sh                # Config parsing tests
test/test_collect.sh               # Provider execution tests
test/run_all.sh                    # Test runner
```

## Common Tasks for Agents

### Adding a New Provider

1. Create executable script that outputs JSON
2. Ensure it follows the provider output format
3. Add to config file under `[[providers]]`
4. Test with `--once` flag

Example:
```bash
#!/usr/bin/env bash
value=$(your_check_logic)
jq -n --arg name "my-check" --arg status "ok" --argjson value "$value" \
  '{name: $name, status: $status, value: $value, unit: "count", message: "OK"}'
```

### Debugging Issues

1. Set `log_level = "DEBUG"` in config
2. Run with `--once` to test collection
3. Use `--dry-run` to test without HTTP operations
4. Check provider execution: `bash -x provider-script`
5. Validate JSON: `provider-script | jq empty`

### Extending Functionality

**Adding a new HTTP endpoint**: Edit `lib/server.sh`, add new case in route handler

**Adding Prometheus metrics**: Create new function in `lib/server.sh` to convert JSON to Prometheus format

**Adding authentication**: Wrap HTTP server with auth proxy or add header validation in server.sh

**Adding notifications**: Create new library (e.g., `lib/notify.sh`) and call from push.sh on status changes

## Testing Strategy

1. **Unit tests**: Test each library module in isolation (test_config.sh, test_collect.sh)
2. **Mock providers**: Use temporary scripts that output known JSON for testing
3. **Integration tests**: Run full daemon in dry-run mode
4. **Real-world tests**: Run daemon for extended period, verify behavior

## Common Patterns

### Error Handling

```bash
# Always check command success
if ! some_command; then
  log_error "component" "Command failed"
  return 1
fi

# Validate JSON before using
if ! echo "$json" | jq empty 2>/dev/null; then
  log_error "component" "Invalid JSON"
  return 1
fi
```

### Configuration Access

```bash
# Always load config first
config_load

# Access settings
value="$(config_get_setting key_name)"

# Iterate providers
while IFS= read -r provider_json; do
  # Process each provider
done < <(config_get_providers)
```

### Logging

```bash
# Initialize logging after config load
log_init

# Use appropriate log levels
log_debug "component" "Detailed debug info"
log_info "component" "Normal operation info"
log_warn "component" "Warning but not critical"
log_error "component" "Error condition"
```

## Integration Points

### With Monitoring Systems

- **Prometheus**: Scrape `/metrics` endpoint (future enhancement)
- **Graphite/StatsD**: Push mode can POST to StatsD aggregator
- **Nagios/Icinga**: Use as active check (--once mode)
- **Custom dashboards**: Pull mode JSON can feed real-time dashboards

### With Alerting Systems

- **Webhook-based**: Push mode sends to alerting system webhook
- **Status-based**: Parse status field (ok/warning/critical) for alerts
- **Threshold-based**: Use provider values for threshold checks

## Security Considerations

1. **Provider execution**: Providers run with daemon's user privileges
2. **HTTP server**: No authentication by default (use reverse proxy for auth)
3. **Push URL**: Credentials in URL visible in config and logs
4. **File permissions**: Config file may contain sensitive URLs

## Performance Characteristics

- **Memory**: ~5-10MB for daemon + provider processes
- **CPU**: Minimal (mostly sleeping), spikes during collection
- **Network**: Only during push mode (configurable interval)
- **Disk I/O**: Minimal (logs only)

## Future Enhancements

- Prometheus metrics format support
- Built-in aggregation/averaging over time windows
- Provider result caching to reduce load
- Webhooks for status change notifications
- TLS support for push mode
- HTTP authentication for pull mode
- Systemd socket activation for pull mode

## Maintenance Notes

- **Dependencies**: Keep minimal, only add if truly necessary
- **Bash version**: Requires bash 4.0+ for associative arrays
- **ShellCheck**: All scripts should pass ShellCheck
- **Compatibility**: Test on common distributions (Ubuntu, Debian, RHEL)

## Related Modules

- **gh-pm**: Similar bash-based daemon, good reference for patterns
- Could integrate with gh-pm to report build/test system health

## Questions to Ask Users

When helping users configure or extend host-status:

1. What metrics do you want to monitor?
2. Pull mode, push mode, or both?
3. What's the remote endpoint for push mode?
4. What's the desired collection/push interval?
5. Any custom providers needed?
6. Running as systemd service or standalone?
7. What's the desired log level?

## Common Gotchas

1. **toml2json not found**: Install remarshal package
2. **nc variations**: Different netcat implementations have different flags
3. **Path resolution**: Providers need absolute paths or be in PATH
4. **JSON escaping**: Use jq -n with --arg for safe JSON construction
5. **Timeout command**: May not be available on all systems (use GNU coreutils)
