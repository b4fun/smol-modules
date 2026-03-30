#!/usr/bin/env bash
set -euo pipefail

# install.sh - Install host-status as a systemd user service

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$HOME/.host-status"
SERVICE_FILE="$HOME/.config/systemd/user/host-status.service"

usage() {
  cat << 'EOF'
Usage: install.sh [OPTIONS]

Install host-status as a systemd user service.

OPTIONS:
  --uninstall    Uninstall the service
  --help         Show this help

DEFAULT BEHAVIOR:
  - Copies files to ~/.host-status/
  - Installs systemd service to ~/.config/systemd/user/
  - Enables and starts the service

EOF
}

uninstall() {
  echo "Uninstalling host-status service..."
  
  # Stop and disable service
  if systemctl --user is-active host-status >/dev/null 2>&1; then
    echo "Stopping service..."
    systemctl --user stop host-status
  fi
  
  if systemctl --user is-enabled host-status >/dev/null 2>&1; then
    echo "Disabling service..."
    systemctl --user disable host-status
  fi
  
  # Remove service file
  if [[ -f "$SERVICE_FILE" ]]; then
    echo "Removing service file..."
    rm -f "$SERVICE_FILE"
    systemctl --user daemon-reload
  fi
  
  # Remove installation directory (preserve config)
  if [[ -d "$INSTALL_DIR" ]]; then
    echo "Removing installation directory (config preserved)..."
    rm -rf "$INSTALL_DIR/bin" "$INSTALL_DIR/lib"
  fi
  
  echo "Uninstall complete."
}

install() {
  echo "Installing host-status..."
  
  # Create directories
  mkdir -p "$INSTALL_DIR"/{bin,lib}
  mkdir -p "$(dirname "$SERVICE_FILE")"
  
  # Copy binaries
  echo "Copying binaries..."
  cp -r "$SCRIPT_DIR/bin"/* "$INSTALL_DIR/bin/"
  chmod +x "$INSTALL_DIR/bin"/*
  
  # Copy libraries
  echo "Copying libraries..."
  cp -r "$SCRIPT_DIR/lib"/* "$INSTALL_DIR/lib/"
  
  # Copy example config if config doesn't exist
  if [[ ! -f "$INSTALL_DIR/host-status.toml" ]]; then
    echo "Creating default config..."
    cp "$SCRIPT_DIR/host-status.example.toml" "$INSTALL_DIR/host-status.toml"
    echo "Edit $INSTALL_DIR/host-status.toml to customize."
  else
    echo "Config already exists, skipping."
  fi
  
  # Install service file
  echo "Installing systemd service..."
  cp "$SCRIPT_DIR/host-status.service" "$SERVICE_FILE"
  systemctl --user daemon-reload
  
  # Enable and start service
  echo "Enabling service..."
  systemctl --user enable host-status
  
  echo "Starting service..."
  systemctl --user start host-status
  
  echo ""
  echo "Installation complete!"
  echo ""
  echo "Service status:"
  systemctl --user status host-status --no-pager
  echo ""
  echo "Useful commands:"
  echo "  systemctl --user status host-status"
  echo "  systemctl --user restart host-status"
  echo "  journalctl --user -u host-status -f"
  echo ""
  echo "Configuration file: $INSTALL_DIR/host-status.toml"
}

main() {
  case "${1:-}" in
    --uninstall)
      uninstall
      ;;
    --help)
      usage
      exit 0
      ;;
    "")
      install
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      exit 1
      ;;
  esac
}

main "$@"
