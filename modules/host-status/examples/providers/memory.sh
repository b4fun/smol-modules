#!/bin/bash
set -euo pipefail

# Memory Status Provider
# Reports memory usage statistics

# Get memory info from /proc/meminfo
total=$(grep MemTotal /proc/meminfo | awk '{print $2}')
available=$(grep MemAvailable /proc/meminfo | awk '{print $2}')
used=$((total - available))

# Convert to MB
total_mb=$((total / 1024))
available_mb=$((available / 1024))
used_mb=$((used / 1024))

# Calculate usage percentage
used_pct=$(echo "scale=2; ($used / $total) * 100" | bc)

# Determine status based on usage
status="ok"
if (( $(echo "$used_pct > 90" | bc -l) )); then
    status="error"
elif (( $(echo "$used_pct > 75" | bc -l) )); then
    status="warn"
fi

# Output JSON
cat <<EOF
{
  "status": "$status",
  "metrics": {
    "total_mb": $total_mb,
    "used_mb": $used_mb,
    "available_mb": $available_mb,
    "used_percentage": $used_pct
  },
  "message": "Memory usage: ${used_mb}MB / ${total_mb}MB (${used_pct}%)"
}
EOF
