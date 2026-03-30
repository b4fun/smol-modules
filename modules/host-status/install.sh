#!/bin/bash
set -euo pipefail

# Installation script for host-status
# Usage: sudo ./install.sh

if [ "$EUID" -ne 0 ]; then
    echo "Please run as root (sudo ./install.sh)"
    exit 1
fi

echo "Installing host-status..."

# Build the binary
echo "Building binary..."
go build -o host-status

# Create user and group
if ! id -u hoststatus >/dev/null 2>&1; then
    echo "Creating hoststatus user..."
    useradd -r -s /bin/false -d /opt/host-status hoststatus
fi

# Create directories
echo "Creating directories..."
mkdir -p /opt/host-status
mkdir -p /etc/host-status
mkdir -p /var/lib/host-status

# Copy binary and examples
echo "Copying files..."
cp host-status /opt/host-status/
cp -r examples /opt/host-status/
chmod +x /opt/host-status/examples/providers/*.sh

# Copy example config if config doesn't exist
if [ ! -f /etc/host-status/config.yaml ]; then
    echo "Installing example configuration..."
    cp examples/config.yaml /etc/host-status/config.yaml
    echo "WARNING: Edit /etc/host-status/config.yaml before starting the service"
fi

# Set ownership
chown -R hoststatus:hoststatus /opt/host-status
chown -R hoststatus:hoststatus /var/lib/host-status
chown root:hoststatus /etc/host-status/config.yaml
chmod 640 /etc/host-status/config.yaml

# Install systemd service
echo "Installing systemd service..."
cp host-status.service /etc/systemd/system/
systemctl daemon-reload

echo ""
echo "Installation complete!"
echo ""
echo "Next steps:"
echo "1. Edit /etc/host-status/config.yaml"
echo "2. Update provider paths to /opt/host-status/examples/providers/"
echo "3. Enable and start the service:"
echo "   sudo systemctl enable --now host-status"
echo "4. Check status:"
echo "   sudo systemctl status host-status"
echo "   journalctl -u host-status -f"
echo ""
