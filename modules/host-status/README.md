# host-status

A flexible host status collection module that supports both pull-based (HTTP endpoint) and push-based (periodic reporting) models. User-defined status providers enable custom metric collection via external programs.

## Features

- 🔄 **Dual Model Support**: Both pull (on-demand queries) and push (periodic reporting) patterns
- 🔌 **Extensible Providers**: Define custom status providers via external programs
- ⏱️ **Configurable Intervals**: Default 5-minute push interval, fully customizable
- 🛡️ **Error Handling**: Timeout management, retry logic, and graceful degradation
- 📊 **Status Aggregation**: Overall status based on individual provider results
- 🔐 **Authentication Support**: Bearer tokens and custom headers for push destinations

## Quick Start

### Installation

```bash
# Build the binary
go build -o host-status

# Or install to $GOPATH/bin
go install
```

### Configuration

Create a `config.yaml` file (see `examples/config.yaml` for full example):

```yaml
pull:
  enabled: true
  host: "0.0.0.0"
  port: 8080

push:
  enabled: true
  interval: "5m"
  destinations:
    - url: "https://monitoring.example.com/api/status"
      auth: "Bearer your-token"

providers:
  # Built-in providers (no command needed)
  - name: "cpu"
    timeout: "10s"
  - name: "memory"
    timeout: "10s"
  - name: "disk"
    timeout: "10s"
  - name: "uptime"
    timeout: "10s"
```

### Running

```bash
# Run with default config location
./host-status

# Run with custom config
./host-status -config /path/to/config.yaml
```

## Usage

### Pull Model (HTTP Endpoint)

When pull mode is enabled, query status via HTTP:

```bash
# Get current status
curl http://localhost:8080/status

# Health check
curl http://localhost:8080/health
```

Example response:

```json
{
  "hostname": "server-001",
  "timestamp": "2024-03-30T10:15:30Z",
  "overall": "ok",
  "providers": [
    {
      "name": "cpu",
      "status": "ok",
      "timestamp": "2024-03-30T10:15:30Z",
      "metrics": {
        "load_1min": 0.52,
        "load_5min": 0.48,
        "load_15min": 0.45,
        "cpu_count": 4,
        "load_percentage": 13.0,
        "execution_time_ms": 12
      }
    },
    {
      "name": "memory",
      "status": "ok",
      "timestamp": "2024-03-30T10:15:30Z",
      "metrics": {
        "total_mb": 16384,
        "used_mb": 8192,
        "available_mb": 8192,
        "used_percentage": 50.0,
        "execution_time_ms": 8
      }
    }
  ]
}
```

### Push Model (Periodic Reporting)

When push mode is enabled, status is automatically sent to configured destinations at the specified interval (default: 5 minutes).

The same JSON format is POSTed to each destination URL with:
- `Content-Type: application/json`
- Configured authentication headers
- Automatic retry on failure (3 attempts with exponential backoff)

## Providers

host-status supports two types of providers:

1. **Built-in Providers**: Implemented in Go, compiled into the binary (no external dependencies)
2. **External Providers**: Custom scripts or programs that follow the provider contract

### Built-in Providers

The following providers are built into the host-status binary:

#### CPU Provider
Monitors CPU load averages and calculates load percentage.

```yaml
providers:
  - name: "cpu"
    timeout: "10s"
```

Metrics:
- `load_1min`, `load_5min`, `load_15min`: Load averages
- `cpu_count`: Number of CPU cores
- `load_percentage`: Load as percentage of total CPU capacity

Status:
- `ok`: Load < 60%
- `warn`: Load 60-80%
- `error`: Load > 80%

#### Memory Provider
Monitors system memory usage.

```yaml
providers:
  - name: "memory"
    timeout: "10s"
```

Metrics:
- `total_mb`, `used_mb`, `available_mb`: Memory in megabytes
- `used_percentage`: Memory usage percentage

Status:
- `ok`: Usage < 80%
- `warn`: Usage 80-90%
- `error`: Usage > 90%

#### Disk Provider
Monitors filesystem disk usage.

```yaml
providers:
  - name: "disk"
    timeout: "10s"
    args: ["/"]  # Optional: path to monitor (default: "/")
```

Metrics:
- `path`: Monitored filesystem path
- `total_gb`, `used_gb`, `available_gb`: Disk space in gigabytes
- `used_percentage`: Disk usage percentage

Status:
- `ok`: Usage < 80%
- `warn`: Usage 80-90%
- `error`: Usage > 90%

#### Uptime Provider
Reports system uptime.

```yaml
providers:
  - name: "uptime"
    timeout: "10s"
```

Metrics:
- `uptime_seconds`: Total uptime in seconds
- `days`, `hours`, `minutes`: Uptime broken down

Status: Always `ok`

### External Provider Interface

### Provider Contract

External providers are executable programs (scripts, binaries, etc.) that:

1. **Input**: Receive configuration via environment variables (optional)
2. **Output**: Print JSON to stdout in the following format:
   ```json
   {
     "status": "ok|warn|error",
     "metrics": {
       "key": "value",
       ...
     },
     "message": "Human-readable status message"
   }
   ```
3. **Exit Code**: Return 0 for success, non-zero for failure
4. **Timeout**: Must complete within configured timeout (default: 30s)

### Status Levels

- `ok`: Normal operation
- `warn`: Warning condition (not critical)
- `error`: Error condition (requires attention)

### Creating a Provider

Example provider in bash:

```bash
#!/bin/bash
set -euo pipefail

# Collect some metrics
value=$(your-command-here)

# Determine status
status="ok"
if [ $value -gt 90 ]; then
    status="error"
elif [ $value -gt 75 ]; then
    status="warn"
fi

# Output JSON
cat <<EOF
{
  "status": "$status",
  "metrics": {
    "value": $value,
    "threshold_warn": 75,
    "threshold_error": 90
  },
  "message": "Current value: $value"
}
EOF
```

Example provider in Python:

```python
#!/usr/bin/env python3
import json
import sys

def collect_metrics():
    # Your metric collection logic
    value = get_some_metric()
    
    if value > 90:
        status = "error"
    elif value > 75:
        status = "warn"
    else:
        status = "ok"
    
    return {
        "status": status,
        "metrics": {
            "value": value
        },
        "message": f"Current value: {value}"
    }

if __name__ == "__main__":
    try:
        result = collect_metrics()
        print(json.dumps(result))
        sys.exit(0)
    except Exception as e:
        print(json.dumps({
            "status": "error",
            "metrics": {},
            "message": f"Error: {str(e)}"
        }))
        sys.exit(1)
```

## Configuration Reference

### Pull Configuration

```yaml
pull:
  enabled: bool      # Enable HTTP server (default: false)
  host: string       # Bind address (default: "0.0.0.0")
  port: int          # Port number (default: 8080)
```

### Push Configuration

```yaml
push:
  enabled: bool      # Enable periodic pushing (default: false)
  interval: string   # Push interval (default: "5m")
                    # Format: "300s", "5m", "1h", etc.
  destinations:
    - url: string             # Destination URL (required)
      auth: string            # Authorization header value
      headers:                # Additional headers
        Header-Name: value
```

### Provider Configuration

Built-in providers:
```yaml
providers:
  - name: string      # Provider name: "cpu", "memory", "disk", or "uptime"
    timeout: string   # Execution timeout (default: "30s")
    args: [string]    # Arguments (optional, disk provider accepts path)
```

External providers:
```yaml
providers:
  - name: string      # Provider name (required, unique)
    command: string   # Executable path (required)
    args: [string]    # Command arguments (optional)
    timeout: string   # Execution timeout (default: "30s")
    env:              # Environment variables (optional)
      VAR_NAME: value
```

## Included Example Providers

### cpu.sh
Monitors CPU load average and reports status based on load percentage.

**Metrics:**
- `load_1min`, `load_5min`, `load_15min`: Load averages
- `cpu_count`: Number of CPU cores
- `load_percentage`: Load as percentage of CPU capacity

**Status Thresholds:**
- `ok`: < 60%
- `warn`: 60-80%
- `error`: > 80%

### memory.sh
Monitors memory usage from `/proc/meminfo`.

**Metrics:**
- `total_mb`, `used_mb`, `available_mb`: Memory in megabytes
- `used_percentage`: Memory usage percentage

**Status Thresholds:**
- `ok`: < 75%
- `warn`: 75-90%
- `error`: > 90%

### disk.sh
Monitors root filesystem disk usage.

**Metrics:**
- `total`, `used`, `available`: Disk space (human-readable)
- `used_percentage`: Disk usage percentage

**Status Thresholds:**
- `ok`: < 80%
- `warn`: 80-90%
- `error`: > 90%

### uptime.sh
Reports system uptime (always returns `ok` status).

**Metrics:**
- `uptime_seconds`: Total uptime in seconds
- `uptime_days`, `uptime_hours`, `uptime_minutes`: Uptime components

## Deployment

### Systemd Service

Create `/etc/systemd/system/host-status.service`:

```ini
[Unit]
Description=Host Status Monitor
After=network.target

[Service]
Type=simple
User=hoststatus
Group=hoststatus
WorkingDirectory=/opt/host-status
ExecStart=/opt/host-status/host-status -config /etc/host-status/config.yaml
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
```

Enable and start:

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now host-status
sudo systemctl status host-status
```

### Docker

Example Dockerfile:

```dockerfile
FROM golang:1.21-alpine AS builder
WORKDIR /build
COPY . .
RUN go build -o host-status

FROM alpine:latest
RUN apk --no-cache add ca-certificates bc
WORKDIR /app
COPY --from=builder /build/host-status .
COPY examples/ ./examples/
COPY config.yaml .
EXPOSE 8080
CMD ["./host-status"]
```

## Monitoring and Observability

The service logs to stdout/stderr. In production:

```bash
# View logs (systemd)
journalctl -u host-status -f

# View logs (Docker)
docker logs -f host-status
```

Log messages include:
- Provider execution results
- Push success/failure
- HTTP request handling
- Configuration loading
- Shutdown events

## Security Considerations

1. **Provider Execution**: Providers run with the same permissions as the host-status process. Use dedicated service accounts with minimal privileges.

2. **Authentication**: Store authentication tokens securely. Consider using environment variable substitution in config files.

3. **Network Exposure**: When using pull mode, restrict access to the HTTP endpoint via firewall rules or reverse proxy authentication.

4. **Provider Validation**: Validate provider scripts before deployment. Malicious providers can execute arbitrary code.

## Troubleshooting

### Provider Timeout
Increase the timeout in config:
```yaml
providers:
  - name: "slow-provider"
    timeout: "60s"  # Increased from default 30s
```

### Push Failures
Check logs for retry attempts and error messages. Verify:
- Destination URL is reachable
- Authentication tokens are valid
- Network connectivity

### High Execution Time
Monitor the `execution_time_ms` metric in responses. Optimize slow providers.

## Development

### Building

```bash
go build -o host-status
```

### Testing

Run example providers directly:

```bash
./examples/providers/cpu.sh
./examples/providers/memory.sh
```

Test with minimal config:

```yaml
pull:
  enabled: true
  port: 8080
providers:
  - name: "test"
    command: "./examples/providers/uptime.sh"
```

### Nix Development Shell

Enter the development environment:

```bash
nix develop
```

## Contributing

When adding features:
1. Update this README
2. Add tests if applicable
3. Update example configuration
4. Follow Go standard formatting (`gofmt`)

See the root `AGENTS.md` for module conventions.

## License

MIT
