#!/bin/bash
set -e

SCRIPT_URL="https://raw.githubusercontent.com/YOUR_USER/YOUR_REPO/main/update-blacklist.sh"
INSTALL_PATH="/usr/local/bin/update-blacklist.sh"

echo "Installing update-blacklist..."

# Download and install script
curl -fsSL "$SCRIPT_URL" -o "$INSTALL_PATH"
chmod +x "$INSTALL_PATH"
echo "✓ Script installed to $INSTALL_PATH"

# Install systemd service
curl -fsSL "$SERVICE_URL" -o "$SERVICE_PATH"
systemctl daemon-reload

echo ""
echo "Done! Run manually with:"
echo "  sudo $INSTALL_PATH"
