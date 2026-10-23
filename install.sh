#!/bin/bash

################################################################################
# Persistent nftables Abuse Blacklist
#
# Install with: curl -fsSL https://raw.github.../install.sh | sudo bash
#
# Installs an nftables table hooked at prerouting, priority -300 (raw), so
# blacklisted sources are dropped for local AND forwarded traffic, before
# conntrack allocates any state for them.
################################################################################

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Error: This script must be run as root (use sudo)${NC}"
    echo "Usage: curl -fsSL https://example.com/install.sh | sudo bash"
    exit 1
fi

echo -e "${BLUE}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   Installing Persistent nftables Abuse Blacklist               ║${NC}"
echo -e "${BLUE}║   (prerouting hook, priority -300: before conntrack)           ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Step 1: Check dependencies
echo -e "${YELLOW}Step 1: Checking dependencies...${NC}"
MISSING_DEPS=0
for cmd in curl nft awk systemctl; do
    if ! command -v "$cmd" &> /dev/null; then
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

# Step 3: Remove old nftables table if it exists (also migrates the old
# input-hook version to the prerouting hook)
echo ""
echo -e "${YELLOW}Step 3: Removing old nftables table...${NC}"
if nft list tables 2>/dev/null | grep -q "table inet abuse"; then
    nft delete table inet abuse 2>/dev/null || true
    echo -e "${GREEN}✓ Removed existing nftables table 'abuse'${NC}"
else
    echo -e "${GREEN}✓ No existing nftables table 'abuse' found${NC}"
fi

# Step 4: Create update script
echo ""
echo -e "${YELLOW}Step 4: Creating update script...${NC}"
cat > /usr/local/bin/update-blacklist.sh << 'ENDSCRIPT'
#!/bin/bash

if [ "$EUID" -ne 0 ]; then
    echo "Error: run as root" >&2
    exit 1
fi

TABLE="abuse"
SET="abuseipdb"
SET2="skipa"
CHAIN="prerouting"
CHAIN_PRIORITY=-300
BATCH_SIZE=1000

URL_ABUSEIPDB="https://github.com/mitsuha44/abuseipdb/releases/latest/download/blacklist.txt"
URL_SKIPA="https://raw.githubusercontent.com/tread-lightly/CyberOK_Skipa_ips/refs/heads/main/lists/skipa_cidr.txt"

RULESET_BASE="/etc/nftables.d/abuse-base.nft"
RULESET_SET1="/etc/nftables.d/abuseipdb-set.nft"
RULESET_SET2="/etc/nftables.d/skipa-set.nft"

mkdir -p /etc/nftables.d

# Writes the base ruleset (table, sets, chain, rules). The file is idempotent:
# it declares then deletes the table first, so it can be loaded repeatedly
# (by this script and at boot) and is the single source of truth.
write_base_ruleset() {
    cat > "$RULESET_BASE" <<EOF
table inet $TABLE
delete table inet $TABLE

table inet $TABLE {
    set $SET {
        type ipv4_addr
        flags interval
        auto-merge
    }

    set $SET2 {
        type ipv4_addr
        flags interval
        auto-merge
    }

    chain $CHAIN {
        type filter hook prerouting priority $CHAIN_PRIORITY; policy accept;

        ip saddr @$SET2 counter limit rate 5/minute burst 10 packets log prefix "[ABUSE_skipa] " level info
        ip saddr @$SET2 counter drop

        ip saddr @$SET counter limit rate 5/minute burst 10 packets log prefix "[ABUSE_abuseipdb] " level info
        ip saddr @$SET counter drop
    }
}
EOF
    [ -s "$RULESET_BASE" ]
}

create_base_ruleset() {
    echo "Creating base nftables structure..."
    write_base_ruleset || { echo "ERROR: failed to write $RULESET_BASE" >&2; return 1; }
    nft -f "$RULESET_BASE" || { echo "ERROR: failed to load base ruleset" >&2; return 1; }
    echo "Base structure created successfully."
}

echo "Checking nftables table, sets, and chain..."

# (Re)create if the table/chain is missing or has the wrong hook (old input version)
if ! nft list chain inet "$TABLE" "$CHAIN" 2>/dev/null | grep -q "hook $CHAIN"; then
    echo "Table/chain missing or outdated - creating new structure..."
    create_base_ruleset || exit 1
else
    echo "Table '$TABLE' with chain '$CHAIN' already exists."
    # Refresh the on-disk base file so boot loading stays in sync
    write_base_ruleset
fi

# update_set <set> <url> <label> <saved-file>
# Downloads a list, validates entries, then replaces the set contents in ONE
# atomic nft transaction (no window where the set is empty, and any error
# leaves the old set untouched and is reported).
update_set() {
    local set="$1" url="$2" label="$3" saved="$4"
    local raw clean nftfile total

    raw=$(mktemp); clean=$(mktemp); nftfile=$(mktemp)

    echo ""
    echo "========================================"
    echo "Updating $label"
    echo "========================================"

    echo "Downloading latest $label list..."
    if ! curl -fsSL "$url" -o "$raw"; then
        echo "Error: Failed to download $label list!" >&2
        rm -f "$raw" "$clean" "$nftfile"
        return 1
    fi

    # Keep only valid-looking IPv4 / IPv4-CIDR entries, one per line
    tr -d '\r' < "$raw" \
        | grep -Eo '^[0-9]{1,3}(\.[0-9]{1,3}){3}(/[0-9]{1,2})?' \
        | sort -u > "$clean" || true

    total=$(wc -l < "$clean")
    if [ "$total" -eq 0 ]; then
        echo "Error: $label list contained no valid entries; keeping existing set." >&2
        rm -f "$raw" "$clean" "$nftfile"
        return 1
    fi

    echo "Loading $total entries into set $set..."
    {
        echo "flush set inet $TABLE $set"
        awk -v set="$set" -v table="$TABLE" -v n="$BATCH_SIZE" '
            { buf = buf (c++ ? "," : "") $0
              if (c == n) { print "add element inet " table " " set " { " buf " }"; buf = ""; c = 0 } }
            END { if (c) print "add element inet " table " " set " { " buf " }" }
        ' "$clean"
    } > "$nftfile"

    if nft -f "$nftfile"; then
        echo "$label set updated ($total entries)."
        nft list set inet "$TABLE" "$set" > "$saved"
    else
        echo "Error: nft rejected the $label update; existing set left unchanged." >&2
        rm -f "$raw" "$clean" "$nftfile"
        return 1
    fi

    rm -f "$raw" "$clean" "$nftfile"
}

STATUS=0
update_set "$SET"  "$URL_ABUSEIPDB" "ABUSEIPDB Blacklist" "$RULESET_SET1" || STATUS=1
update_set "$SET2" "$URL_SKIPA"      "SKIPA Blocklist"      "$RULESET_SET2" || STATUS=1

echo ""
echo "========================================"
if [ $STATUS -eq 0 ]; then
    echo "Update Complete"
else
    echo "Update finished with errors (see above)"
fi
echo "========================================"
exit $STATUS
ENDSCRIPT

chmod 755 /usr/local/bin/update-blacklist.sh
echo -e "${GREEN}✓ Created: /usr/local/bin/update-blacklist.sh${NC}"

# Step 5: Create boot loader script
echo ""
echo -e "${YELLOW}Step 5: Creating boot loader script...${NC}"
cat > /usr/local/bin/load-nftables-blacklist.sh << 'ENDLOADER'
#!/bin/bash

RULESET_BASE="/etc/nftables.d/abuse-base.nft"
RULESET_SET1="/etc/nftables.d/abuseipdb-set.nft"
RULESET_SET2="/etc/nftables.d/skipa-set.nft"

echo "Loading nftables blacklist rules..." | logger -t abuse-blacklist

if [ ! -f "$RULESET_BASE" ]; then
    echo "Base ruleset not found at $RULESET_BASE" | logger -t abuse-blacklist
    exit 1
fi

if ! nft -f "$RULESET_BASE"; then
    echo "Failed to load base rules!" | logger -t abuse-blacklist
    exit 1
fi
echo "Base rules loaded." | logger -t abuse-blacklist

for f in "$RULESET_SET1" "$RULESET_SET2"; do
    if [ -f "$f" ]; then
        if nft -f "$f"; then
            echo "Loaded $f" | logger -t abuse-blacklist
        else
            echo "Failed to load $f" | logger -t abuse-blacklist
        fi
    fi
done

echo "All blacklist rules loaded." | logger -t abuse-blacklist
ENDLOADER

chmod 755 /usr/local/bin/load-nftables-blacklist.sh
echo -e "${GREEN}✓ Created: /usr/local/bin/load-nftables-blacklist.sh${NC}"

# Step 6: Create systemd service
echo ""
echo -e "${YELLOW}Step 6: Creating systemd service...${NC}"
cat > /etc/systemd/system/abuse-blacklist.service << 'ENDSERVICE'
[Unit]
Description=Load nftables abuse blacklist rules
# Run after nftables.service so a "flush ruleset" there can't wipe our table
After=network-online.target nftables.service
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

# Step 7: Configure systemd
echo ""
echo -e "${YELLOW}Step 7: Configuring systemd...${NC}"
systemctl daemon-reload
echo -e "${GREEN}✓ Systemd daemon reloaded${NC}"

systemctl enable abuse-blacklist.service
echo -e "${GREEN}✓ Service enabled for auto-start${NC}"

# Step 8: Run initial update
echo ""
echo -e "${YELLOW}Step 8: Running initial blacklist update...${NC}"
echo "This may take a minute..."
echo ""

if /usr/local/bin/update-blacklist.sh; then
    echo -e "${GREEN}✓ Initial update completed successfully${NC}"
else
    echo -e "${RED}✗ Update failed${NC}"
    exit 1
fi

# Step 9: Verify
echo ""
echo -e "${YELLOW}Step 9: Verifying installation...${NC}"

if nft list tables | grep -q "abuse"; then
    echo -e "${GREEN}✓ nftables table 'abuse' created${NC}"
else
    echo -e "${RED}✗ nftables table not found${NC}"
    exit 1
fi

if nft list chain inet abuse prerouting 2>/dev/null | grep -q "hook prerouting"; then
    echo -e "${GREEN}✓ Chain 'prerouting' created with priority -300${NC}"
else
    echo -e "${RED}✗ Chain 'prerouting' not found${NC}"
    echo "Full table output:"
    nft list table inet abuse
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
echo "  • Hook: prerouting, priority -300 (before conntrack; covers forwarded traffic)"
echo "  • Sets: abuseipdb, skipa"
echo "  • Persistence: abuse-blacklist.service reloads rules at boot"
echo ""

echo -e "${YELLOW}Next steps:${NC}"
echo ""
echo "1. Schedule daily updates (optional):"
echo "   sudo crontab -e"
echo "   Add: 0 2 * * * /usr/local/bin/update-blacklist.sh >> /var/log/blacklist-update.log 2>&1"
echo "   Or with timestamps: 0 2 * * * { date '+%Y-%m-%d %H:%M:%S'; /usr/local/bin/update-blacklist.sh; } >> /var/log/blacklist-update.log 2>&1"
echo ""
echo "2. Monitor blocks:"
echo "   sudo journalctl -f | grep ABUSE_"
echo ""
echo "3. Check table:"
echo "   sudo nft list table inet abuse"
echo ""
echo "4. Check chain:"
echo "   sudo nft list chain inet abuse prerouting"
echo ""
echo "5. Manual update:"
echo "   sudo /usr/local/bin/update-blacklist.sh"
echo ""

echo -e "${GREEN}Installation verified and working!${NC}"
