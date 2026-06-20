#!/bin/bash
set -e

SCRIPT_URL="https://raw.githubusercontent.com/mitsuha44/abuseipdb/refs/heads/main/update-blacklist.sh"
INSTALL_PATH="/usr/local/bin/update-blacklist.sh"
ALIAS_LINE="alias update-abuse-blacklists='sudo /usr/local/bin/update-blacklist.sh'"

echo "Installing update-blacklist..."

# Download and install script
curl -fsSL "$SCRIPT_URL" -o "$INSTALL_PATH"
chmod +x "$INSTALL_PATH"
echo "✓ Script installed to $INSTALL_PATH"

# Install alias to system-wide bashrc
if ! grep -qF "alias update-abuse-blacklists=" /etc/bash.bashrc; then
    echo "$ALIAS_LINE" >> /etc/bash.bashrc
    echo "✓ Alias added to /etc/bash.bashrc"
fi

# Install alias to user's bashrc
if ! grep -qF "alias update-abuse-blacklists=" ~/.bashrc; then
    echo "$ALIAS_LINE" >> ~/.bashrc
    echo "✓ Alias added to ~/.bashrc (restart shell or run: source ~/.bashrc)"
fi

echo "Done! Run manually with:"
echo "sudo update-abuse-blacklists"
