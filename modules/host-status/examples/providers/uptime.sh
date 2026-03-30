#!/bin/bash
set -euo pipefail

# Uptime Status Provider
# Reports system uptime

# Get uptime in seconds
uptime_seconds=$(cut -d' ' -f1 /proc/uptime | cut -d'.' -f1)

# Convert to days, hours, minutes
days=$((uptime_seconds / 86400))
hours=$(((uptime_seconds % 86400) / 3600))
minutes=$(((uptime_seconds % 3600) / 60))

# Format uptime string
if [ $days -gt 0 ]; then
    uptime_str="${days}d ${hours}h ${minutes}m"
elif [ $hours -gt 0 ]; then
    uptime_str="${hours}h ${minutes}m"
else
    uptime_str="${minutes}m"
fi

# Status is always OK for uptime (informational only)
status="ok"

# Output JSON
cat <<EOF
{
  "status": "$status",
  "metrics": {
    "uptime_seconds": $uptime_seconds,
    "uptime_days": $days,
    "uptime_hours": $hours,
    "uptime_minutes": $minutes
  },
  "message": "System uptime: $uptime_str"
}
EOF
