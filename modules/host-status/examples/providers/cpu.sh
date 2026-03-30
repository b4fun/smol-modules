#!/bin/bash
set -euo pipefail

# CPU Status Provider
# Reports CPU usage statistics

# Get CPU load averages
load_avg=$(uptime | awk -F'load average:' '{print $2}' | xargs)
load_1min=$(echo "$load_avg" | cut -d',' -f1 | xargs)
load_5min=$(echo "$load_avg" | cut -d',' -f2 | xargs)
load_15min=$(echo "$load_avg" | cut -d',' -f3 | xargs)

# Get CPU count
cpu_count=$(nproc)

# Calculate load percentage (load / cpu_count)
load_pct=$(echo "scale=2; ($load_1min / $cpu_count) * 100" | bc)

# Determine status based on load
status="ok"
if (( $(echo "$load_pct > 80" | bc -l) )); then
    status="error"
elif (( $(echo "$load_pct > 60" | bc -l) )); then
    status="warn"
fi

# Output JSON
cat <<EOF
{
  "status": "$status",
  "metrics": {
    "load_1min": $load_1min,
    "load_5min": $load_5min,
    "load_15min": $load_15min,
    "cpu_count": $cpu_count,
    "load_percentage": $load_pct
  },
  "message": "CPU load: ${load_1min} (${load_pct}%)"
}
EOF
