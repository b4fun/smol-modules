# host-status

A lightweight host monitoring daemon that collects system metrics via extensible providers. Supports both pull-based (HTTP API) and push-based (periodic POST) operation modes.

## Features

- **Dual operation modes**: Pull (HTTP server) and Push (periodic reporting)
- **Extensible provider system**: Add custom metrics via external scripts
- **Built-in system metrics**: CPU load, memory usage, disk usage, uptime
- **TOML configuration**: Simple, human-readable config format
- **JSON output**: Structured data for easy integration
- **Timeout handling**: Prevents hanging on slow providers
- **Graceful error handling**: Provider failures don't crash the daemon

## Quick Start

### Installation

```bash
# Enter development environment (requires Nix)
nix develop

# Or ensure dependencies are available:
# bash, jq, curl, nc, toml2json
```

### Basic Usage

```bash
# Collect status once and print to stdout
./bin/host-status --once

# Run as daemon with default config
./bin/host-status --config host-status.example.toml

# Test configuration (dry-run mode)
./bin/host-status --dry-run --once
```

### Example Output

```json
{
  "hostname": "web-01",
  "timestamp": "2024-03-30T12:34:56Z",
  "status": "ok",
  "providers": [
    {
      "name": "cpu",
      "status": "ok",
      "value": 1.2,
      "unit": "load",
      "message": "Load average: 1.2 (1m) 1.0 (5m) 0.8 (15m)",
      "metadata": {
        "load_1m": 1.2,
        "load_5m": 1.0,
        "load_15m": 0.8
      }
    },
    {
      "name": "memory",
      "status": "ok",
      "value": 45,
      "unit": "percent",
      "message": "Memory usage: 45%",
      "metadata": {
        "used_kb": 4500000,
        "total_kb": 10000000
      }
    }
  ]
}
```

## Configuration

Create `~/.host-status/host-status.toml` (see `host-status.example.toml` for full example):

```toml
[settings]
hostname = "web-01"
push_enabled = true
push_url = "https://collector.example.com/api/hosts"
push_interval = 300  # 5 minutes
pull_enabled = true
pull_port = 8080
collection_timeout = 10
log_level = "INFO"

[[providers]]
name = "system-cpu"
command = "./bin/host-status-provider-system"
args = ["cpu"]
enabled = true

[[providers]]
name = "system-memory"
command = "./bin/host-status-provider-system"
args = ["memory"]
enabled = true
```

## Operation Modes

### Pull Mode (HTTP Server)

Start an HTTP server that responds to status queries:

```bash
# Enable in config:
pull_enabled = true
pull_port = 8080

# Query endpoints:
curl http://localhost:8080/status    # Full status JSON
curl http://localhost:8080/health    # Simple health check
```

### Push Mode (Periodic Reporting)

Periodically POST status to a remote endpoint:

```bash
# Enable in config:
push_enabled = true
push_url = "https://collector.example.com/api/hosts"
push_interval = 300  # seconds
```

Both modes can be enabled simultaneously.

## Provider Protocol

Providers are executable scripts that output JSON to stdout. The daemon executes each provider and aggregates results.

### Provider Output Format

```json
{
  "name": "provider-name",
  "status": "ok|warning|critical|unknown",
  "value": 42.5,
  "unit": "percent",
  "message": "Human-readable status message",
  "metadata": {
    "additional": "fields",
    "custom": "data"
  }
}
```

### Creating Custom Providers

1. Create an executable script:

```bash
#!/usr/bin/env bash
set -euo pipefail

# Your monitoring logic here
value=$(check_something)

# Output JSON
jq -n \
  --arg name "my-check" \
  --arg status "ok" \
  --argjson value "$value" \
  --arg message "Everything is fine" \
  '{
    name: $name,
    status: $status,
    value: $value,
    unit: "count",
    message: $message
  }'
```

2. Add to configuration:

```toml
[[providers]]
name = "my-custom-check"
command = "/path/to/my-check.sh"
args = ["optional", "arguments"]
enabled = true
```

## Built-in System Provider

The `host-status-provider-system` binary provides common system metrics:

```bash
# Individual checks
./bin/host-status-provider-system cpu
./bin/host-status-provider-system memory
./bin/host-status-provider-system disk /
./bin/host-status-provider-system uptime

# All checks (returns array)
./bin/host-status-provider-system all
```

## Testing

```bash
# Run all tests
./test/run_all.sh

# Run individual test suites
./test/test_config.sh
./test/test_collect.sh
```

## Command-Line Options

```
host-status [OPTIONS]

OPTIONS:
  --config PATH      Path to config file (default: ~/.host-status/host-status.toml)
  --once             Collect and print status once, then exit
  --dry-run          Dry-run mode (no HTTP operations)
  --help             Show help message
```

## Logging

Logs are written to stderr by default. Configure file logging:

```toml
[settings]
log_level = "DEBUG"  # DEBUG, INFO, WARN, ERROR
log_file = "/var/log/host-status/host-status.log"
```

Log format: `TIMESTAMP LEVEL COMPONENT MESSAGE`

```
2024-03-30T12:34:56Z INFO main host-status starting
2024-03-30T12:34:56Z INFO collect Starting status collection for host 'web-01'
2024-03-30T12:34:57Z INFO collect Collection complete: 4 success, 0 errors out of 4 providers
```

## Systemd Service

To run as a systemd service:

1. Copy the service file:

```bash
sudo cp host-status.service /etc/systemd/system/
```

2. Create config directory:

```bash
mkdir -p ~/.host-status
cp host-status.example.toml ~/.host-status/host-status.toml
# Edit configuration as needed
```

3. Enable and start:

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now host-status
sudo systemctl status host-status
```

4. View logs:

```bash
sudo journalctl -u host-status -f
```

## Architecture

```
┌─────────────────────────────────────────┐
│         host-status daemon              │
│                                          │
│  ┌──────────────────────────────────┐  │
│  │  Configuration Loader             │  │
│  │  (lib/config.sh)                  │  │
│  └──────────────────────────────────┘  │
│            │                             │
│            ↓                             │
│  ┌──────────────────────────────────┐  │
│  │  Provider Manager                 │  │
│  │  (lib/collect.sh)                 │  │
│  │  - Execute providers with timeout │  │
│  │  - Validate JSON output           │  │
│  └──────────────────────────────────┘  │
│            │                             │
│            ↓                             │
│  ┌──────────────────────────────────┐  │
│  │  Status Aggregator                │  │
│  │  - Combine all provider results   │  │
│  │  - Overall status determination   │  │
│  └──────────────────────────────────┘  │
│       │                   │              │
│       ↓                   ↓              │
│  ┌─────────┐       ┌──────────────┐    │
│  │  Pull   │       │    Push      │    │
│  │  Server │       │    Loop      │    │
│  │ (HTTP)  │       │   (Timer)    │    │
│  └─────────┘       └──────────────┘    │
└─────────────────────────────────────────┘
```

## Troubleshooting

### Provider not executing

- Check that the command path is correct and executable
- Verify provider outputs valid JSON
- Check timeout setting (increase if providers are slow)
- Enable DEBUG logging to see execution details

### HTTP server not responding

- Verify port is not already in use: `netstat -tlnp | grep <port>`
- Check firewall rules
- Ensure `pull_enabled = true` in config

### Push not working

- Test URL manually: `curl -X POST -H 'Content-Type: application/json' -d '{}' <url>`
- Check network connectivity
- Verify `push_enabled = true` and `push_url` is set
- Use `--dry-run` to test without actual HTTP requests

## Development

```bash
# Enter Nix development shell
nix develop

# Run shellcheck on all scripts
find . -name '*.sh' -exec shellcheck {} +

# Test individual components
bash -x ./bin/host-status --once
```

## License

See repository LICENSE file.

## Contributing

Contributions welcome! Please ensure:

- All bash scripts pass ShellCheck
- Tests pass (`./test/run_all.sh`)
- Documentation is updated
- Follow existing code patterns
