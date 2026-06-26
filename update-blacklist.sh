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
BATCH_SIZE=1000  # number of IPs per nft command

# PRIORITY SETTING: Use 100 to run AFTER UFW (which uses priority 0)
# Priority scale:
#   -300 = earliest (before everything)
#   0 = standard (where UFW runs)
#   100 = after UFW (this setting)
#   200+ = very late in chain
CHAIN_PRIORITY=100

# Ensure directory exists for ruleset files
sudo mkdir -p /etc/nftables.d

# Function to save base rules (table, chain, rules without set data)
save_base_ruleset() {
    echo "Saving base nftables configuration (table, chain, rules)..."
    sudo bash -c 'cat > '"$RULESET_BASE"' << '"'"'EOF'"'"'
# Base nftables rules for abuse blacklist
# Priority 100 = runs AFTER UFW (priority 0)
# Generated automatically - do not edit manually

table inet abuse {
	set abuseipdb {
		type ipv4_addr
		flags interval
	}

	set skipa {
		type ipv4_addr
		flags interval
	}

	chain input {
		type filter hook input priority 100; policy accept;
		comment "Abuse blacklist - runs AFTER UFW"
		ip saddr @skipa counter log prefix "[ABUSE_skipa] " drop
		ip saddr @abuseipdb counter log prefix "[ABUSE_abuseipdb] " drop
	}
}
EOF'
    if [ $? -eq 0 ]; then
        echo "Base ruleset saved successfully."
    else
        echo "Warning: Failed to save base ruleset!" >&2
    fi
}

# Function to save abuseipdb set with its current data
save_abuseipdb_set() {
    echo "Saving abuseipdb IP set..."
    sudo bash -c "nft list set inet abuse $SET | grep -v '^table' | grep -v '^}' > $RULESET_SET1"
    if [ $? -eq 0 ]; then
        echo "Abuseipdb set saved to $RULESET_SET1"
    else
        echo "Warning: Failed to save abuseipdb set!" >&2
    fi
}

# Function to save skipa set with its current data
save_skipa_set() {
    echo "Saving skipa IP set..."
    sudo bash -c "nft list set inet abuse $SET2 | grep -v '^table' | grep -v '^}' > $RULESET_SET2"
    if [ $? -eq 0 ]; then
        echo "Skipa set saved to $RULESET_SET2"
    else
        echo "Warning: Failed to save skipa set!" >&2
    fi
}

# --- Step 0: Ensure nftables table, sets, and chain exist ---
echo "Checking nftables table, sets, and chain..."
echo "(Using priority $CHAIN_PRIORITY to run AFTER UFW)"
echo ""

# Create table and base structure if it doesn't exist
if ! sudo nft list tables | grep -qw "abuse"; then
    echo "Creating base nftables structure (priority $CHAIN_PRIORITY)..."
    sudo nft -f "$RULESET_BASE" 2>/dev/null || {
        echo "Creating table $TABLE..."
        sudo nft add table inet abuse

        echo "Creating set $SET..."
        sudo nft "add set inet abuse $SET { type ipv4_addr; flags interval; }"

        echo "Creating set $SET2..."
        sudo nft "add set inet abuse $SET2 { type ipv4_addr; flags interval; }"

        echo "Creating chain $CHAIN with priority $CHAIN_PRIORITY (after UFW)..."
        sudo nft "add chain inet abuse $CHAIN { type filter hook input priority $CHAIN_PRIORITY; policy accept; }"

        echo "Adding rules..."
        sudo nft "add rule inet abuse $CHAIN ip saddr @$SET2 counter log prefix \"[ABUSE_skipa] \" drop"
        sudo nft "add rule inet abuse $CHAIN ip saddr @$SET counter log prefix \"[ABUSE_abuseipdb] \" drop"
    }
else
    echo "Table $TABLE already exists."

    # Check if priority is correct
    CURRENT_PRIORITY=$(sudo nft list chain inet abuse input | grep "hook input" | grep -oP "priority \K[0-9-]+")
    if [ "$CURRENT_PRIORITY" != "$CHAIN_PRIORITY" ]; then
        echo "Warning: Current priority is $CURRENT_PRIORITY, expected $CHAIN_PRIORITY"
        echo "To fix this, delete and recreate the chain:"
        echo "  sudo nft delete chain inet abuse input"
        echo "  Then re-run this script"
    fi
fi

# --- ABUSEIPDB SECTION ---
echo ""
echo "========================================"
echo "Updating ABUSEIPDB Blacklist"
echo "========================================"

# Download latest blacklist
echo "Downloading latest abuseipdb blacklist..."
if curl -fL -# https://github.com/mitsuha44/abuseipdb/releases/latest/download/blacklist.txt -o "$OUTFILE"; then
    echo "Download complete: $OUTFILE"
else
    echo "Error: Failed to download abuseipdb blacklist!" >&2
    exit 1
fi

# Flush existing set
echo "Flushing existing nftables set $SET..."
sudo nft flush set inet abuse "$SET"

# Update set in batches
TOTAL=$(wc -l < "$OUTFILE")
echo "Updating nftables set with $TOTAL IPv4 addresses in batches of $BATCH_SIZE..."

count=0
BATCH=()
while IFS= read -r ip; do
    BATCH+=("$ip")
    count=$((count + 1))

    # when batch is full or last line, add to nft
    if (( ${#BATCH[@]} >= BATCH_SIZE )) || (( count == TOTAL )); then
        ELEMENTS=$(IFS=, ; echo "${BATCH[*]}")
        sudo nft add element inet abuse "$SET" { $ELEMENTS }
        BATCH=()  # clear batch

        # progress percentage only
        PERCENT=$((count * 100 / TOTAL))
        printf "\rProgress: %d/%d (%d%%)" "$count" "$TOTAL" "$PERCENT"
    fi
done < "$OUTFILE"

echo -e "\nAbuseipdb set updated."

# Save abuseipdb set to persistence file
save_abuseipdb_set

# --- SKIPA SECTION ---
echo ""
echo "========================================"
echo "Updating SKIPA Blocklist"
echo "========================================"

# Download latest blacklist
echo "Downloading latest skipa blacklist..."
if curl -fL -# https://raw.githubusercontent.com/tread-lightly/CyberOK_Skipa_ips/refs/heads/main/lists/skipa_cidr.txt -o "$OUTFILE2"; then
    echo "Download complete: $OUTFILE2"
else
    echo "Error: Failed to download skipa blacklist!" >&2
    exit 1
fi

# Flush existing set
echo "Flushing existing nftables set $SET2..."
sudo nft flush set inet abuse "$SET2"

# Update set in batches
TOTAL=$(wc -l < "$OUTFILE2")
echo "Updating nftables set with $TOTAL IPv4 CIDRs in batches of $BATCH_SIZE..."

count=0
BATCH=()
while IFS= read -r ip; do
    BATCH+=("$ip")
    count=$((count + 1))

    # when batch is full or last line, add to nft
    if (( ${#BATCH[@]} >= BATCH_SIZE )) || (( count == TOTAL )); then
        ELEMENTS=$(IFS=, ; echo "${BATCH[*]}")
        sudo nft add element inet abuse "$SET2" { $ELEMENTS }
        BATCH=()  # clear batch

        # progress percentage only
        PERCENT=$((count * 100 / TOTAL))
        printf "\rProgress: %d/%d (%d%%)" "$count" "$TOTAL" "$PERCENT"
    fi
done < "$OUTFILE2"

echo -e "\nSkipa set updated."

# Save skipa set to persistence file
save_skipa_set

echo ""
echo "========================================"
echo "Update Complete"
echo "========================================"
echo "Rules will persist across reboots:"
echo "  Base rules: $RULESET_BASE (priority $CHAIN_PRIORITY)"
echo "  Abuseipdb set: $RULESET_SET1"
echo "  Skipa set: $RULESET_SET2"
echo ""
echo "Execution order:"
echo "  1. UFW rules (priority 0)"
echo "  2. Your abuse table (priority $CHAIN_PRIORITY) ← AFTER UFW"
