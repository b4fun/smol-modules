# Provider Development Guide

This guide explains how to create custom status providers for the host-status module.

## Provider Interface

### Requirements

A provider is an executable program (script, binary, etc.) that:

1. **Outputs JSON to stdout** in the following format:
   ```json
   {
     "status": "ok|warn|error",
     "metrics": {
       "key1": value1,
       "key2": value2
     },
     "message": "Human-readable status message"
   }
   ```

2. **Exits with code 0** on successful execution (even if status is "error")
3. **Exits with non-zero code** only on execution failure
4. **Completes within timeout** (default 30 seconds)

### Field Descriptions

- `status` (required): One of `ok`, `warn`, or `error`
- `metrics` (required): Object containing metric key-value pairs
- `message` (optional): Human-readable description

### Status Levels

- **ok**: Normal operation, no issues detected
- **warn**: Warning condition, degraded but functional
- **error**: Error condition, requires attention

## Example Providers

### Bash Provider Template

```bash
#!/bin/bash
set -euo pipefail

# Collect your metrics
metric_value=$(your_command_here)

# Determine status based on thresholds
status="ok"
if (( $(echo "$metric_value > 90" | bc -l) )); then
    status="error"
elif (( $(echo "$metric_value > 75" | bc -l) )); then
    status="warn"
fi

# Output JSON
cat <<EOF
{
  "status": "$status",
  "metrics": {
    "value": $metric_value,
    "threshold_warn": 75,
    "threshold_error": 90
  },
  "message": "Current value: $metric_value"
}
EOF
```

### Python Provider Template

```python
#!/usr/bin/env python3
import json
import sys

def collect_metrics():
    """Collect your metrics here"""
    value = get_some_metric()
    
    # Determine status
    if value > 90:
        status = "error"
    elif value > 75:
        status = "warn"
    else:
        status = "ok"
    
    return {
        "status": status,
        "metrics": {
            "value": value,
            "threshold_warn": 75,
            "threshold_error": 90
        },
        "message": f"Current value: {value}"
    }

def main():
    try:
        result = collect_metrics()
        print(json.dumps(result))
        return 0
    except Exception as e:
        print(json.dumps({
            "status": "error",
            "metrics": {},
            "message": f"Error: {str(e)}"
        }), file=sys.stderr)
        return 1

if __name__ == "__main__":
    sys.exit(main())
```

### Go Provider Template

```go
package main

import (
	"encoding/json"
	"fmt"
	"os"
)

type ProviderOutput struct {
	Status  string                 `json:"status"`
	Metrics map[string]interface{} `json:"metrics"`
	Message string                 `json:"message"`
}

func collectMetrics() (*ProviderOutput, error) {
	// Your metric collection logic
	value := getSomeMetric()
	
	status := "ok"
	if value > 90 {
		status = "error"
	} else if value > 75 {
		status = "warn"
	}
	
	return &ProviderOutput{
		Status: status,
		Metrics: map[string]interface{}{
			"value":           value,
			"threshold_warn":  75,
			"threshold_error": 90,
		},
		Message: fmt.Sprintf("Current value: %d", value),
	}, nil
}

func main() {
	result, err := collectMetrics()
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		os.Exit(1)
	}
	
	if err := json.NewEncoder(os.Stdout).Encode(result); err != nil {
		fmt.Fprintf(os.Stderr, "JSON encoding error: %v\n", err)
		os.Exit(1)
	}
}
```

## Real-World Examples

### Network Latency Monitor

```bash
#!/bin/bash
set -euo pipefail

TARGET="${TARGET_HOST:-8.8.8.8}"
COUNT=3

# Ping and extract average latency
ping_output=$(ping -c $COUNT -W 2 "$TARGET" 2>&1 || true)
avg_latency=$(echo "$ping_output" | grep 'avg' | awk -F'/' '{print $5}')

if [ -z "$avg_latency" ]; then
    # Ping failed
    cat <<EOF
{
  "status": "error",
  "metrics": {
    "target": "$TARGET",
    "reachable": false
  },
  "message": "Target $TARGET is unreachable"
}
EOF
    exit 0
fi

# Determine status based on latency
status="ok"
if (( $(echo "$avg_latency > 200" | bc -l) )); then
    status="error"
elif (( $(echo "$avg_latency > 100" | bc -l) )); then
    status="warn"
fi

cat <<EOF
{
  "status": "$status",
  "metrics": {
    "target": "$TARGET",
    "avg_latency_ms": $avg_latency,
    "reachable": true
  },
  "message": "Latency to $TARGET: ${avg_latency}ms"
}
EOF
```

### Service Health Check

```python
#!/usr/bin/env python3
import json
import sys
import requests
from urllib.parse import urlparse

def check_service(url, timeout=5):
    try:
        response = requests.get(url, timeout=timeout)
        
        if response.status_code == 200:
            status = "ok"
        elif response.status_code < 500:
            status = "warn"
        else:
            status = "error"
        
        return {
            "status": status,
            "metrics": {
                "url": url,
                "status_code": response.status_code,
                "response_time_ms": int(response.elapsed.total_seconds() * 1000),
                "available": True
            },
            "message": f"Service returned {response.status_code} in {response.elapsed.total_seconds():.2f}s"
        }
    except requests.exceptions.Timeout:
        return {
            "status": "error",
            "metrics": {"url": url, "available": False, "error": "timeout"},
            "message": f"Service timeout after {timeout}s"
        }
    except Exception as e:
        return {
            "status": "error",
            "metrics": {"url": url, "available": False, "error": str(e)},
            "message": f"Service check failed: {str(e)}"
        }

if __name__ == "__main__":
    url = os.environ.get("SERVICE_URL", "http://localhost:8080/health")
    result = check_service(url)
    print(json.dumps(result))
```

### Database Connection Check

```python
#!/usr/bin/env python3
import json
import sys
import os
import time
import psycopg2

def check_database():
    dsn = os.environ.get("DATABASE_URL")
    if not dsn:
        return {
            "status": "error",
            "metrics": {},
            "message": "DATABASE_URL not set"
        }
    
    try:
        start = time.time()
        conn = psycopg2.connect(dsn, connect_timeout=5)
        cursor = conn.cursor()
        cursor.execute("SELECT 1")
        cursor.fetchone()
        cursor.close()
        conn.close()
        duration_ms = int((time.time() - start) * 1000)
        
        return {
            "status": "ok",
            "metrics": {
                "connected": True,
                "connection_time_ms": duration_ms
            },
            "message": f"Database connected in {duration_ms}ms"
        }
    except Exception as e:
        return {
            "status": "error",
            "metrics": {"connected": False, "error": str(e)},
            "message": f"Database connection failed: {str(e)}"
        }

if __name__ == "__main__":
    result = check_database()
    print(json.dumps(result))
```

## Configuration

### Basic Provider Configuration

```yaml
providers:
  - name: "my-provider"
    command: "/path/to/provider.sh"
    timeout: "30s"
```

### Provider with Arguments

```yaml
providers:
  - name: "custom-check"
    command: "/usr/local/bin/check-tool"
    args:
      - "--format"
      - "json"
      - "--verbose"
    timeout: "60s"
```

### Provider with Environment Variables

```yaml
providers:
  - name: "service-check"
    command: "./providers/http-check.py"
    timeout: "15s"
    env:
      SERVICE_URL: "https://api.example.com/health"
      TIMEOUT: "10"
```

## Best Practices

### 1. Error Handling

Always handle errors gracefully:

```bash
#!/bin/bash
set -euo pipefail

if ! command -v required_tool &> /dev/null; then
    cat <<EOF
{
  "status": "error",
  "metrics": {},
  "message": "required_tool is not installed"
}
EOF
    exit 0  # Exit 0 even on error
fi

# Rest of your logic...
```

### 2. Timeout Awareness

Design providers to complete quickly:

```python
# Use timeouts in network operations
response = requests.get(url, timeout=5)

# Use connection timeouts for databases
conn = psycopg2.connect(dsn, connect_timeout=5)
```

### 3. Meaningful Metrics

Include context in metrics:

```json
{
  "metrics": {
    "value": 85,
    "threshold_warn": 75,
    "threshold_error": 90,
    "unit": "percent",
    "timestamp": "2024-03-30T10:15:30Z"
  }
}
```

### 4. Consistent Units

Use standard units:
- Time: milliseconds, seconds
- Memory: bytes, MB, GB
- Percentages: 0-100

### 5. Logging

Write logs to stderr, not stdout:

```bash
echo "Debug: Starting check..." >&2
# JSON output to stdout
echo '{"status": "ok", ...}'
```

## Testing Providers

### Manual Testing

```bash
# Run provider directly
./provider.sh

# Check exit code
echo $?

# Validate JSON output
./provider.sh | jq .

# Test with environment variables
TARGET_HOST=example.com ./provider.sh
```

### Automated Testing

```bash
#!/bin/bash
# test-provider.sh

set -euo pipefail

PROVIDER="./provider.sh"

echo "Testing provider..."

# Test 1: Provider runs successfully
if ! output=$($PROVIDER); then
    echo "FAIL: Provider failed to execute"
    exit 1
fi

# Test 2: Output is valid JSON
if ! echo "$output" | jq . > /dev/null 2>&1; then
    echo "FAIL: Invalid JSON output"
    exit 1
fi

# Test 3: Required fields present
if ! echo "$output" | jq -e '.status' > /dev/null; then
    echo "FAIL: Missing status field"
    exit 1
fi

if ! echo "$output" | jq -e '.metrics' > /dev/null; then
    echo "FAIL: Missing metrics field"
    exit 1
fi

echo "PASS: All tests passed"
```

## Troubleshooting

### Provider Not Executing

1. Check file permissions: `chmod +x provider.sh`
2. Verify shebang line: `#!/bin/bash`
3. Check command path in config
4. Review logs for error messages

### Timeout Issues

1. Increase timeout in config
2. Optimize provider logic
3. Add timeout to external commands
4. Consider async operations

### Invalid JSON Output

1. Test JSON with `jq`: `./provider.sh | jq .`
2. Check for extra output to stdout
3. Escape special characters in strings
4. Use JSON libraries instead of string concatenation

### Status Not Updating

1. Verify provider exit code is 0
2. Check status value is one of: `ok`, `warn`, `error`
3. Review provider logs for errors
4. Test provider independently

## Advanced Topics

### Caching

For expensive operations, implement caching:

```bash
#!/bin/bash
set -euo pipefail

CACHE_FILE="/tmp/provider-cache.json"
CACHE_TTL=300  # 5 minutes

if [ -f "$CACHE_FILE" ]; then
    age=$(($(date +%s) - $(stat -c %Y "$CACHE_FILE")))
    if [ $age -lt $CACHE_TTL ]; then
        cat "$CACHE_FILE"
        exit 0
    fi
fi

# Collect fresh data
result=$(collect_metrics)
echo "$result" | tee "$CACHE_FILE"
```

### Multi-Step Checks

```python
def run_checks():
    checks = [
        ("api_health", check_api),
        ("database", check_database),
        ("cache", check_cache),
    ]
    
    metrics = {}
    overall_status = "ok"
    
    for name, check_func in checks:
        try:
            result = check_func()
            metrics[name] = result
            if result["status"] == "error":
                overall_status = "error"
            elif result["status"] == "warn" and overall_status != "error":
                overall_status = "warn"
        except Exception as e:
            metrics[name] = {"error": str(e)}
            overall_status = "error"
    
    return {
        "status": overall_status,
        "metrics": metrics,
        "message": f"Completed {len(checks)} checks"
    }
```

## Security Considerations

1. **Least Privilege**: Providers run with host-status permissions
2. **Input Validation**: Validate environment variables
3. **Secure Credentials**: Don't hardcode secrets
4. **Command Injection**: Use arrays for arguments, not string concatenation
5. **Output Sanitization**: Escape user input in JSON output

## Contributing

When contributing new providers:

1. Follow the provider interface specification
2. Include comprehensive error handling
3. Add documentation comments
4. Provide example configuration
5. Test thoroughly
6. Update this guide with your example
