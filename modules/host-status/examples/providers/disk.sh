#!/bin/bash
set -euo pipefail

# Disk Status Provider
# Reports disk usage statistics for root filesystem

# Get disk usage for root filesystem
disk_info=$(df -h / | tail -n 1)
total=$(echo "$disk_info" | awk '{print $2}')
used=$(echo "$disk_info" | awk '{print $3}')
available=$(echo "$disk_info" | awk '{print $4}')
used_pct=$(echo "$disk_info" | awk '{print $5}' | tr -d '%')

# Determine status based on usage
status="ok"
if (( used_pct > 90 )); then
    status="error"
elif (( used_pct > 80 )); then
    status="warn"
fi

# Output JSON
cat <<EOF
{
  "status": "$status",
  "metrics": {
    "total": "$total",
    "used": "$used",
    "available": "$available",
    "used_percentage": $used_pct
  },
  "message": "Disk usage: ${used} / ${total} (${used_pct}%)"
}
EOF
