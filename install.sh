#!/bin/bash

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo -e "${BLUE}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   Installing Persistent nftables Abuse Blacklist with UFW      ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Check if running as root or with sudo
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Error: This script must be run as root or with sudo${NC}"
    exit 1
fi

echo -e "${YELLOW}Step 1: Checking dependencies...${NC}"
# Check for required commands
MISSING_DEPS=0
for cmd in curl nft sudo systemctl; do
    if ! command -v $cmd &> /dev/null; then
        echo -e "${RED}✗ Missing: $cmd${NC}"
        MISSING_DEPS=1
    else
        echo -e "${GREEN}✓ Found: $cmd${NC}"
    fi
done

if [ $MISSING_DEPS -eq 1 ]; then
    echo -e "${RED}Please install missing dependencies and try again${NC}"
    exit 1
fi

echo ""
echo -e "${YELLOW}Step 2: Checking UFW status...${NC}"
if systemctl is-active --quiet ufw; then
    echo -e "${GREEN}✓ UFW is running${NC}"
else
    echo -e "${YELLOW}⚠ UFW is not running. Enabling now...${NC}"
    ufw enable --force > /dev/null 2>&1 || true
fi

echo ""
echo -e "${YELLOW}Step 3: Creating directories...${NC}"
mkdir -p /etc/nftables.d
mkdir -p /usr/local/bin
echo -e "${GREEN}✓ Created /etc/nftables.d${NC}"
echo -e "${GREEN}✓ Created /usr/local/bin${NC}"

echo ""
echo -e "${YELLOW}Step 4: Installing scripts...${NC}"

# Check if scripts exist in current directory
if [ ! -f "$SCRIPT_DIR/update-blacklist-after-ufw.sh" ]; then
    echo -e "${RED}Error: update-blacklist-after-ufw.sh not found in $SCRIPT_DIR${NC}"
    echo "Make sure all scripts are in the same directory as this installer"
    exit 1
fi

# Copy and install update script
cp "$SCRIPT_DIR/update-blacklist-after-ufw.sh" /usr/local/bin/update-blacklist.sh
chmod 755 /usr/local/bin/update-blacklist.sh
echo -e "${GREEN}✓ Installed: /usr/local/bin/update-blacklist.sh${NC}"

# Copy and install loader script
if [ -f "$SCRIPT_DIR/load-nftables-blacklist-separate.sh" ]; then
    cp "$SCRIPT_DIR/load-nftables-blacklist-separate.sh" /usr/local/bin/load-nftables-blacklist.sh
    chmod 755 /usr/local/bin/load-nftables-blacklist.sh
    echo -e "${GREEN}✓ Installed: /usr/local/bin/load-nftables-blacklist.sh${NC}"
else
    echo -e "${RED}Error: load-nftables-blacklist-separate.sh not found${NC}"
    exit 1
fi

# Copy and install systemd service
if [ -f "$SCRIPT_DIR/abuse-blacklist-after-ufw.service" ]; then
    cp "$SCRIPT_DIR/abuse-blacklist-after-ufw.service" /etc/systemd/system/abuse-blacklist.service
    chmod 644 /etc/systemd/system/abuse-blacklist.service
    echo -e "${GREEN}✓ Installed: /etc/systemd/system/abuse-blacklist.service${NC}"
else
    echo -e "${RED}Error: abuse-blacklist-after-ufw.service not found${NC}"
    exit 1
fi

echo ""
echo -e "${YELLOW}Step 5: Configuring systemd...${NC}"
systemctl daemon-reload
echo -e "${GREEN}✓ Systemd daemon reloaded${NC}"

systemctl enable abuse-blacklist.service
echo -e "${GREEN}✓ Service enabled for auto-start${NC}"

echo ""
echo -e "${YELLOW}Step 6: Running initial blacklist update...${NC}"
echo "This may take a few minutes..."
echo ""

if /usr/local/bin/update-blacklist.sh; then
    echo -e "${GREEN}✓ Initial update completed successfully${NC}"
else
    echo -e "${RED}✗ Update failed. Check /var/log/blacklist-update.log for details${NC}"
    exit 1
fi

echo ""
echo -e "${YELLOW}Step 7: Verifying installation...${NC}"

# Check if nftables table exists
if nft list tables | grep -q "abuse"; then
    echo -e "${GREEN}✓ nftables table 'abuse' created${NC}"
else
    echo -e "${RED}✗ nftables table 'abuse' not found${NC}"
    exit 1
fi

# Check priority
PRIORITY=$(nft list chain inet abuse input 2>/dev/null | grep -oP 'priority \K[0-9-]+' || echo "NOT_FOUND")
if [ "$PRIORITY" = "100" ]; then
    echo -e "${GREEN}✓ Chain priority is 100 (correct - runs after UFW)${NC}"
else
    echo -e "${RED}✗ Chain priority is $PRIORITY (expected 100)${NC}"
    exit 1
fi

# Check if sets have data
ABUSEIPDB_COUNT=$(nft list set inet abuse abuseipdb 2>/dev/null | wc -l)
if [ "$ABUSEIPDB_COUNT" -gt 5 ]; then
    echo -e "${GREEN}✓ Abuseipdb IP set populated${NC}"
else
    echo -e "${RED}✗ Abuseipdb IP set appears empty${NC}"
fi

SKIPA_COUNT=$(nft list set inet abuse skipa 2>/dev/null | wc -l)
if [ "$SKIPA_COUNT" -gt 5 ]; then
    echo -e "${GREEN}✓ Skipa IP set populated${NC}"
else
    echo -e "${RED}✗ Skipa IP set appears empty${NC}"
fi

# Check persistence files
echo ""
echo -e "${YELLOW}Step 8: Checking persistence files...${NC}"
if [ -f "/etc/nftables.d/abuse-base.nft" ]; then
    echo -e "${GREEN}✓ Base ruleset: /etc/nftables.d/abuse-base.nft${NC}"
else
    echo -e "${RED}✗ Base ruleset not found${NC}"
fi

if [ -f "/etc/nftables.d/abuseipdb-set.nft" ]; then
    SIZE=$(du -h /etc/nftables.d/abuseipdb-set.nft | cut -f1)
    echo -e "${GREEN}✓ Abuseipdb set: /etc/nftables.d/abuseipdb-set.nft ($SIZE)${NC}"
else
    echo -e "${RED}✗ Abuseipdb set not found${NC}"
fi

if [ -f "/etc/nftables.d/skipa-set.nft" ]; then
    SIZE=$(du -h /etc/nftables.d/skipa-set.nft | cut -f1)
    echo -e "${GREEN}✓ Skipa set: /etc/nftables.d/skipa-set.nft ($SIZE)${NC}"
else
    echo -e "${RED}✗ Skipa set not found${NC}"
fi

echo ""
echo -e "${BLUE}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║            ✓ Installation Complete!                            ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""

echo -e "${GREEN}Your system is now protected with:${NC}"
echo "  • Layer 1: UFW firewall (priority 0)"
echo "  • Layer 2: Abuse blacklist table (priority 100)"
echo ""

echo -e "${YELLOW}Next steps:${NC}"
echo ""
echo "1. Schedule daily updates (optional but recommended):"
echo "   sudo crontab -e"
echo "   # Add this line:"
echo "   0 2 * * * /usr/local/bin/update-blacklist.sh > /var/log/blacklist-update.log 2>&1"
echo ""

echo "2. Monitor blocks:"
echo "   sudo journalctl -f | grep -E 'UFW|ABUSE_'"
echo ""

echo "3. Check current rules:"
echo "   sudo nft list table inet abuse"
echo ""

echo "4. View rule statistics:"
echo "   sudo nft list table inet abuse --stateless"
echo ""

echo -e "${YELLOW}Useful commands:${NC}"
echo "   Update blacklist now:      sudo /usr/local/bin/update-blacklist.sh"
echo "   Service status:            sudo systemctl status abuse-blacklist.service"
echo "   Service logs:              sudo journalctl -u abuse-blacklist.service -f"
echo "   View all rules:            sudo nft list table inet abuse"
echo "   View abuseipdb IPs:        sudo nft list set inet abuse abuseipdb | head -20"
echo "   View skipa CIDRs:          sudo nft list set inet abuse skipa | head -20"
echo ""

echo -e "${GREEN}Installation verified and working!${NC}"
