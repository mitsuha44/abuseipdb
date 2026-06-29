#!/bin/bash

################################################################################
# Persistent nftables Abuse Blacklist
#
# Install with: curl -fsSL https://raw.github.../install.sh | sudo bash
#
# Installs nftables rules with priority 5 to run AFTER other firewall rules
################################################################################

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Error: This script must be run with sudo${NC}"
    echo "Usage: curl -fsSL https://example.com/install.sh | sudo bash"
    exit 1
fi

echo -e "${BLUE}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   Installing Persistent nftables Abuse Blacklist               ║${NC}"
echo -e "${BLUE}║   (Rules execute with priority 5 - after other firewalls)   ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Step 1: Check dependencies
echo -e "${YELLOW}Step 1: Checking dependencies...${NC}"
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

# Step 2: Create directories
echo ""
echo -e "${YELLOW}Step 2: Creating directories...${NC}"
mkdir -p /etc/nftables.d
mkdir -p /usr/local/bin
echo -e "${GREEN}✓ Created /etc/nftables.d${NC}"
echo -e "${GREEN}✓ Created /usr/local/bin${NC}"

# Step 3: Create update script with improved base ruleset creation
echo ""
echo -e "${YELLOW}Step 3: Creating update script...${NC}"
cat > /usr/local/bin/update-blacklist.sh << 'ENDSCRIPT'
#!/bin/bash

TABLE="inet abuse"
SET="abuseipdb"
SET2="skipa"
CHAIN="input"
OUTFILE="/tmp/abuseipdb.txt"
OUTFILE2="/tmp/skipa.txt"
RULESET_BASE="/etc/nftables.d/abuse-base.nft"
RULESET_SET1="/etc/nftables.d/abuseipdb-set.nft"
RULESET_SET2="/etc/nftables.d/skipa-set.nft"
BATCH_SIZE=1000
CHAIN_PRIORITY=5

sudo mkdir -p /etc/nftables.d

echo "Checking nftables table, sets, and chain..."

# DEBUG: Print variables before creating
echo "DEBUG: CHAIN_PRIORITY=$CHAIN_PRIORITY"
echo "DEBUG: CHAIN=$CHAIN"
echo "DEBUG: SET=$SET"
echo "DEBUG: SET2=$SET2"

create_base_ruleset() {
    echo "Creating base nftables structure..."

    # Verify variable is set
    if [ -z "$CHAIN_PRIORITY" ]; then
        echo "ERROR: CHAIN_PRIORITY not defined!" >&2
        return 1
    fi

    # Delete existing table if it exists
    sudo nft list tables 2>/dev/null | grep -q "abuse" && sudo nft delete table inet abuse 2>/dev/null || true

    # Create fresh table with all components
    sudo nft add table inet abuse
    sudo nft add set inet abuse "$SET" "{ type ipv4_addr; flags interval; }"
    sudo nft add set inet abuse "$SET2" "{ type ipv4_addr; flags interval; }"
    sudo nft add chain inet abuse "$CHAIN" "{ type filter hook input priority $CHAIN_PRIORITY; policy accept; }"
    sudo nft add rule inet abuse "$CHAIN" "ip saddr @$SET2 counter log prefix \"[ABUSE_skipa] \" drop"
    sudo nft add rule inet abuse "$CHAIN" "ip saddr @$SET counter log prefix \"[ABUSE_abuseipdb] \" drop"

    echo "Base structure created successfully."
}

save_base_ruleset() {
    echo "Saving base nftables configuration..."
    cat > "$RULESET_BASE" <<EOF
table inet abuse {
    set $SET {
        type ipv4_addr
        flags interval
    }

    set $SET2 {
        type ipv4_addr
        flags interval
    }

    chain $CHAIN {
        type filter hook input priority $CHAIN_PRIORITY; policy accept;
        ip saddr @$SET2 counter log prefix "[ABUSE_skipa] " drop
        ip saddr @$SET counter log prefix "[ABUSE_abuseipdb] " drop
    }
}
EOF
    if [ -s "$RULESET_BASE" ]; then
        echo "Base ruleset saved successfully."
    else
        echo "Warning: Failed to save base ruleset!" >&2
    fi
}

save_abuseipdb_set() {
    echo "Saving abuseipdb IP set..."
    sudo bash -c "nft list set inet abuse $SET > $RULESET_SET1"
    if [ $? -eq 0 ]; then
        echo "Abuseipdb set saved."
    fi
}

save_skipa_set() {
    echo "Saving skipa IP set..."
    sudo bash -c "nft list set inet abuse $SET2 > $RULESET_SET2"
    if [ $? -eq 0 ]; then
        echo "Skipa set saved."
    fi
}

echo "Checking nftables table, sets, and chain..."

# Create or verify base structure
if ! sudo nft list tables 2>/dev/null | grep -qw "abuse"; then
    echo "Table 'abuse' not found - creating new structure..."
    create_base_ruleset
else
    echo "Table 'abuse' already exists."
    # Verify chain exists, if not create it
    if ! sudo nft list chain inet abuse "$CHAIN" 2>/dev/null | grep -q "hook input"; then
        echo "Chain 'input' not found - creating..."
        sudo nft add chain inet abuse "$CHAIN" "{ type filter hook input priority $CHAIN_PRIORITY; policy accept; }"
        sudo nft add rule inet abuse "$CHAIN" "ip saddr @$SET2 counter log prefix \"[ABUSE_skipa] \" drop"
        sudo nft add rule inet abuse "$CHAIN" "ip saddr @$SET counter log prefix \"[ABUSE_abuseipdb] \" drop"
    fi
fi

# Save the base configuration
save_base_ruleset

echo ""
echo "========================================"
echo "Updating ABUSEIPDB Blacklist"
echo "========================================"

echo "Downloading latest abuseipdb blacklist..."
if curl -fL -# https://github.com/mitsuha44/abuseipdb/releases/latest/download/blacklist.txt -o "$OUTFILE"; then
    echo "Download complete: $OUTFILE"
else
    echo "Error: Failed to download abuseipdb blacklist!" >&2
    exit 1
fi

echo "Flushing existing nftables set $SET..."
sudo nft flush set inet abuse "$SET" 2>/dev/null || true

TOTAL=$(wc -l < "$OUTFILE")
echo "Updating nftables set with $TOTAL IPv4 addresses..."

count=0
BATCH=()
while IFS= read -r ip; do
    [ -z "$ip" ] && continue
    BATCH+=("$ip")
    count=$((count + 1))

    if (( ${#BATCH[@]} >= BATCH_SIZE )) || (( count == TOTAL )); then
        ELEMENTS=$(IFS=, ; echo "${BATCH[*]}")
        sudo nft add element inet abuse "$SET" "{ $ELEMENTS }" 2>/dev/null || true
        BATCH=()

        PERCENT=$((count * 100 / TOTAL))
        printf "\rProgress: %d/%d (%d%%)" "$count" "$TOTAL" "$PERCENT"
    fi
done < "$OUTFILE"

echo -e "\nAbuseipdb set updated."
save_abuseipdb_set

echo ""
echo "========================================"
echo "Updating SKIPA Blocklist"
echo "========================================"

echo "Downloading latest skipa blacklist..."
if curl -fL -# https://raw.githubusercontent.com/tread-lightly/CyberOK_Skipa_ips/refs/heads/main/lists/skipa_cidr.txt -o "$OUTFILE2"; then
    echo "Download complete: $OUTFILE2"
else
    echo "Error: Failed to download skipa blacklist!" >&2
    exit 1
fi

echo "Flushing existing nftables set $SET2..."
sudo nft flush set inet abuse "$SET2" 2>/dev/null || true

TOTAL=$(wc -l < "$OUTFILE2")
echo "Updating nftables set with $TOTAL IPv4 CIDRs..."

count=0
BATCH=()
while IFS= read -r ip; do
    [ -z "$ip" ] && continue
    BATCH+=("$ip")
    count=$((count + 1))

    if (( ${#BATCH[@]} >= BATCH_SIZE )) || (( count == TOTAL )); then
        ELEMENTS=$(IFS=, ; echo "${BATCH[*]}")
        sudo nft add element inet abuse "$SET2" "{ $ELEMENTS }" 2>/dev/null || true
        BATCH=()

        PERCENT=$((count * 100 / TOTAL))
        printf "\rProgress: %d/%d (%d%%)" "$count" "$TOTAL" "$PERCENT"
    fi
done < "$OUTFILE2"

echo -e "\nSkipa set updated."
save_skipa_set

echo ""
echo "========================================"
echo "Update Complete"
echo "========================================"
ENDSCRIPT

chmod 755 /usr/local/bin/update-blacklist.sh
echo -e "${GREEN}✓ Created: /usr/local/bin/update-blacklist.sh${NC}"

# Step 4: Create loader script
echo -e "${YELLOW}Step 4: Creating boot loader script...${NC}"
cat > /usr/local/bin/load-nftables-blacklist.sh << 'ENDLOADER'
#!/bin/bash

RULESET_BASE="/etc/nftables.d/abuse-base.nft"
RULESET_SET1="/etc/nftables.d/abuseipdb-set.nft"
RULESET_SET2="/etc/nftables.d/skipa-set.nft"

sleep 2

echo "Loading nftables blacklist rules..." | logger

if [ -f "$RULESET_BASE" ]; then
    echo "Loading base rules..." | logger
    nft -f "$RULESET_BASE"
    if [ $? -eq 0 ]; then
        echo "Base rules loaded." | logger
    else
        echo "Failed to load base rules!" | logger
        exit 1
    fi
else
    echo "Base ruleset not found at $RULESET_BASE" | logger
    exit 1
fi

if [ -f "$RULESET_SET1" ]; then
    echo "Loading abuseipdb IP set..." | logger
    nft -f "$RULESET_SET1" 2>/dev/null || true
fi

if [ -f "$RULESET_SET2" ]; then
    echo "Loading skipa IP set..." | logger
    nft -f "$RULESET_SET2" 2>/dev/null || true
fi

echo "All blacklist rules loaded." | logger
ENDLOADER

chmod 755 /usr/local/bin/load-nftables-blacklist.sh
echo -e "${GREEN}✓ Created: /usr/local/bin/load-nftables-blacklist.sh${NC}"

# Step 5: Create systemd service
echo -e "${YELLOW}Step 5: Creating systemd service...${NC}"
cat > /etc/systemd/system/abuse-blacklist.service << 'ENDSERVICE'
[Unit]
Description=Load nftables abuse blacklist rules
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/load-nftables-blacklist.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
ENDSERVICE

chmod 644 /etc/systemd/system/abuse-blacklist.service
echo -e "${GREEN}✓ Created: /etc/systemd/system/abuse-blacklist.service${NC}"

# Step 6: Configure systemd
echo ""
echo -e "${YELLOW}Step 6: Configuring systemd...${NC}"
systemctl daemon-reload
echo -e "${GREEN}✓ Systemd daemon reloaded${NC}"

systemctl enable abuse-blacklist.service
echo -e "${GREEN}✓ Service enabled for auto-start${NC}"

# Step 7: Run initial update
echo ""
echo -e "${YELLOW}Step 7: Running initial blacklist update...${NC}"
echo "This may take a few minutes..."
echo ""

if /usr/local/bin/update-blacklist.sh; then
    echo -e "${GREEN}✓ Initial update completed successfully${NC}"
else
    echo -e "${RED}✗ Update failed${NC}"
    exit 1
fi

# Step 8: Verify
echo ""
echo -e "${YELLOW}Step 8: Verifying installation...${NC}"

if sudo nft list tables | grep -q "abuse"; then
    echo -e "${GREEN}✓ nftables table 'abuse' created${NC}"
else
    echo -e "${RED}✗ nftables table not found${NC}"
    exit 1
fi

# Check if chain exists
if sudo nft list chain inet abuse input 2>/dev/null | grep -q "hook input"; then
    echo -e "${GREEN}✓ Chain 'input' created with priority 5${NC}"
else
    echo -e "${RED}✗ Chain 'input' not found${NC}"
    echo "Full table output:"
    sudo nft list table inet abuse
    exit 1
fi

if [ -f "/etc/nftables.d/abuse-base.nft" ]; then
    echo -e "${GREEN}✓ Base ruleset saved${NC}"
fi

if [ -f "/etc/nftables.d/abuseipdb-set.nft" ]; then
    SIZE=$(du -h /etc/nftables.d/abuseipdb-set.nft | cut -f1)
    echo -e "${GREEN}✓ Abuseipdb set saved ($SIZE)${NC}"
fi

if [ -f "/etc/nftables.d/skipa-set.nft" ]; then
    SIZE=$(du -h /etc/nftables.d/skipa-set.nft | cut -f1)
    echo -e "${GREEN}✓ Skipa set saved ($SIZE)${NC}"
fi

echo ""
echo -e "${BLUE}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║            ✓ Installation Complete!                            ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""

echo -e "${GREEN}nftables abuse blacklist is now installed and running${NC}"
echo ""
echo "Rules configuration:"
echo "  • Table: inet abuse"
echo "  • Priority: 5 (executes after other firewall rules)"
echo "  • Sets: abuseipdb, skipa"
echo ""

echo -e "${YELLOW}Next steps:${NC}"
echo ""
echo "1. Schedule daily updates (optional):"
echo "   sudo crontab -e"
echo "   Add: 0 2 * * * /usr/local/bin/update-blacklist.sh > /var/log/blacklist-update.log 2>&1"
echo ""
echo "2. Monitor blocks:"
echo "   sudo journalctl -f | grep ABUSE_"
echo ""
echo "3. Check rules:"
echo "   sudo nft list table inet abuse"
echo ""
echo "4. Manual update:"
echo "   sudo /usr/local/bin/update-blacklist.sh"
echo ""

echo -e "${GREEN}Installation verified and working!${NC}"
