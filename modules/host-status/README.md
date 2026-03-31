# host-status

Host monitoring with pull and push status collection.

## Quick Start

```bash
# Build
go build

# Run with config
./host-status -config config.toml

# Query status
curl http://localhost:8080/status
```

## Configuration

Example `config.toml`:

```toml
[pull]
enabled = true
port = 8080
host = "0.0.0.0"

[push]
enabled = true
interval = "5m"

[[push.destinations]]
url = "https://monitoring.example.com/api/status"
auth = "Bearer <token>"

[[providers]]
name = "cpu"
timeout = "10s"

[[providers]]
name = "memory"
timeout = "10s"

[[providers]]
name = "disk"
timeout = "10s"

[[providers]]
name = "uptime"
timeout = "10s"
```

## Built-in Providers

- **cpu**: CPU load and percentage
- **memory**: Memory usage statistics
- **disk**: Disk usage (default: /)
- **uptime**: System uptime

## External Providers

Run custom programs that output JSON:

```toml
[[providers]]
name = "custom"
command = "/path/to/script.sh"
args = ["arg1", "arg2"]
timeout = "30s"
```

Expected JSON format:

```json
{
  "status": "ok",
  "metrics": {
    "key": "value"
  },
  "message": "Optional message"
}
```

Status values: `ok`, `warn`, `error`

## API Endpoints

### GET /status

Returns aggregated status from all providers:

```json
{
  "hostname": "server1",
  "timestamp": "2024-03-30T10:00:00Z",
  "overall": "ok",
  "providers": [
    {
      "name": "cpu",
      "status": "ok",
      "metrics": {...},
      "timestamp": "2024-03-30T10:00:00Z"
    }
  ]
}
```

### GET /health

Health check endpoint:

```json
{"status": "ok"}
```

## Deployment

### systemd

```bash
# Install service
sudo cp host-status /usr/local/bin/
sudo cp config.toml /etc/host-status/
sudo cp host-status.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now host-status
```

### Docker

```bash
docker build -t host-status .
docker run -p 8080:8080 -v $(pwd)/config.toml:/etc/host-status/config.toml host-status
```
