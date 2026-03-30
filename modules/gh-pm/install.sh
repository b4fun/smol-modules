#!/usr/bin/env bash
set -euo pipefail

# install.sh — Install gh-pm as a user systemd service.
#
# Usage:
#   bash install.sh [OPTIONS]
#
# Options:
#   --exec-start PATH   Override ExecStart path (default: auto-detected from this repo)
#   --env-file PATH     Path to environment file with API keys (default: ~/.gh-pm/env)
#   --no-linger         Skip enabling loginctl linger
#   --uninstall         Remove the service and disable linger
#   --help              Show this help
#
# This installs gh-pm as a systemd *user* unit. By default, user units only
# run while the user has an active login session. To keep gh-pm running after
# logout and start it at boot, this script enables "linger" via:
#
#   loginctl enable-linger $USER
#
# Pass --no-linger to skip this if you only want gh-pm active during sessions.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVICE_NAME="gh-pm.service"
USER_UNIT_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"

# Defaults
EXEC_START=""
ENV_FILE="$HOME/.gh-pm/env"
ENABLE_LINGER=1
UNINSTALL=0

show_help() {
  sed -n '/^# Usage:/,/^# Pass --no-linger/p' "${BASH_SOURCE[0]}" | sed 's/^# \?//'
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --exec-start)  shift; EXEC_START="$1"; shift ;;
    --env-file)    shift; ENV_FILE="$1"; shift ;;
    --no-linger)   ENABLE_LINGER=0; shift ;;
    --uninstall)   UNINSTALL=1; shift ;;
    --help|-h)     show_help; exit 0 ;;
    *) echo "Unknown option: $1" >&2; show_help >&2; exit 1 ;;
  esac
done

# --- Uninstall ---
if [[ "$UNINSTALL" -eq 1 ]]; then
  echo "Stopping and disabling gh-pm..."
  systemctl --user stop "$SERVICE_NAME" 2>/dev/null || true
  systemctl --user disable "$SERVICE_NAME" 2>/dev/null || true
  rm -f "${USER_UNIT_DIR}/${SERVICE_NAME}"
  systemctl --user daemon-reload
  echo "Removed ${USER_UNIT_DIR}/${SERVICE_NAME}"
  echo ""
  echo "Note: linger was not disabled. To disable manually:"
  echo "  loginctl disable-linger $USER"
  exit 0
fi

# --- Resolve ExecStart ---
if [[ -z "$EXEC_START" ]]; then
  EXEC_START="$(readlink -f "${SCRIPT_DIR}/bin/gh-pm")"
fi

if [[ ! -x "$EXEC_START" ]]; then
  echo "Error: ExecStart target is not executable: $EXEC_START" >&2
  echo "Use --exec-start PATH to specify the gh-pm binary." >&2
  exit 1
fi

# --- Check dependencies ---
for cmd in gh jq toml2json curl; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "Warning: '$cmd' not found in PATH. gh-pm requires it at runtime." >&2
  fi
done

# --- Check config exists ---
CONFIG_FILE="${GH_PM_CONFIG:-$HOME/.gh-pm/gh-pm.toml}"
if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "Warning: Config file not found: $CONFIG_FILE" >&2
  echo "  Copy the example:  cp ${SCRIPT_DIR}/gh-pm.example.toml $CONFIG_FILE" >&2
fi

# --- Generate unit file ---
mkdir -p "$USER_UNIT_DIR"

cat > "${USER_UNIT_DIR}/${SERVICE_NAME}" <<EOF
[Unit]
Description=gh-pm — GitHub Project Manager Agent
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=${EXEC_START}
Environment=GH_PM_CONFIG=%h/.gh-pm/gh-pm.toml
Environment=GH_PM_WORKSPACE=%h/.gh-pm/workspace
EOF

# Add EnvironmentFile if the env file exists or was explicitly set
if [[ -f "$ENV_FILE" ]]; then
  echo "EnvironmentFile=${ENV_FILE}" >> "${USER_UNIT_DIR}/${SERVICE_NAME}"
  echo "Loaded env file: $ENV_FILE"
else
  echo "# No env file found at ${ENV_FILE}; create it with your API keys:" >> "${USER_UNIT_DIR}/${SERVICE_NAME}"
  echo "# EnvironmentFile=${ENV_FILE}" >> "${USER_UNIT_DIR}/${SERVICE_NAME}"
  echo "Note: No env file at $ENV_FILE — create it with your API keys."
fi

cat >> "${USER_UNIT_DIR}/${SERVICE_NAME}" <<'EOF'
Restart=on-failure
RestartSec=10

[Install]
WantedBy=default.target
EOF

echo "Installed: ${USER_UNIT_DIR}/${SERVICE_NAME}"

# --- Enable linger ---
if [[ "$ENABLE_LINGER" -eq 1 ]]; then
  if command -v loginctl &>/dev/null; then
    echo "Enabling linger for $USER (gh-pm will run at boot, survive logout)..."
    loginctl enable-linger "$USER" 2>/dev/null || {
      echo "Warning: 'loginctl enable-linger' failed. You may need sudo:" >&2
      echo "  sudo loginctl enable-linger $USER" >&2
    }
  else
    echo "Warning: loginctl not found. Enable linger manually if needed." >&2
  fi
fi

# --- Reload and enable ---
systemctl --user daemon-reload
systemctl --user enable "$SERVICE_NAME"
echo ""
echo "gh-pm service installed and enabled."
echo ""
echo "Commands:"
echo "  systemctl --user start  $SERVICE_NAME   # Start now"
echo "  systemctl --user status $SERVICE_NAME   # Check status"
echo "  journalctl --user -u $SERVICE_NAME -f   # Follow logs"
echo "  systemctl --user stop   $SERVICE_NAME   # Stop"
echo "  bash ${BASH_SOURCE[0]} --uninstall       # Remove"
