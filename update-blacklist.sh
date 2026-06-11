#!/bin/bash

TABLE="inet abuse"
SET="abuseipdb"
SET2="skipa"
CHAIN="input"
OUTFILE="/tmp/abuseipdb.txt"
OUTFILE2="/tmp/skipa.txt"
BATCH_SIZE=1000  # number of IPs per nft command

# --- Step 0: Ensure nftables table, set, and chain exist ---
echo "Checking nftables table, set, and chain..."

# Create table if it doesn't exist
if ! sudo nft list tables | grep -qw "abuse"; then
    echo "Creating table $TABLE..."
    sudo nft add table inet abuse
else
    echo "Table $TABLE already exists."
fi

# Create abuseibdb set if it doesn't exist
if ! sudo nft list set inet abuse "$SET" &>/dev/null; then
    echo "Creating set $SET..."
    sudo nft "add set inet abuse $SET { type ipv4_addr; flags interval; }"
else
    echo "Set $SET already exists."
fi

# Create skipa set if it doesn't exist
if ! sudo nft list set inet abuse "$SET2" &>/dev/null; then
    echo "Creating set $SET2..."
    sudo nft "add set inet abuse $SET2 { type ipv4_addr; flags interval; }"
else
    echo "Set $SET2 already exists."
fi

# Create chain if it doesn't exist
if ! sudo nft list chain inet abuse "$CHAIN" &>/dev/null; then
    echo "Creating chain $CHAIN..."
    sudo nft "add chain inet abuse $CHAIN { type filter hook input priority 0; policy accept; }"
else
    echo "Chain $CHAIN already exists."
fi

# Add abuseipdb rule if it doesn't exist
if ! sudo nft list chain inet abuse "$CHAIN" | grep -q "\[ABUSE IP\]"; then
    echo "Adding rule to drop and log blacklist IPs..."
    sudo nft "add rule inet abuse $CHAIN ip saddr @$SET counter log prefix \"[ABUSE IP] \" drop"
else
    echo "Blacklist rule already exists."
fi

# Add abuseipdb rule if it doesn't exist
if ! sudo nft list chain inet abuse "$CHAIN" | grep -q "\[BLOCK IP\]"; then
    echo "Adding rule to drop blocklist IPs..."
    sudo nft "add rule inet abuse $CHAIN ip saddr @$SET2 counter log prefix \"[SKIPA IP] \" drop"
else
    echo "Blocklist rule already exists."
fi

# --- Step 1: Download latest blacklist ---
echo "Downloading latest abuseipdb blacklist..."

# Use -# for progress bar, -f to fail on HTTP errors
if curl -fL -# https://github.com/mitsuha44/abuseipdb/releases/latest/download/blacklist.txt -o "$OUTFILE"; then
    echo "Download complete: $OUTFILE"
else
    echo "Error: Failed to download blacklist!" >&2
    exit 1
fi

# --- Step 2: Flush existing nftables set ---
echo "Flushing existing nftables set $SET..."
sudo nft flush set inet abuse "$SET"

# --- Step 3: Update set in batches ---
TOTAL=$(wc -l < "$OUTFILE")
echo "Updating nftables blacklist with $TOTAL IPv4 IPs in batches of $BATCH_SIZE..."

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

echo -e "\nAbuseipdb blacklist updated."

# --- SET2: Load local blocklist ---
echo "Flushing existing nftables set $SET2..."
sudo nft flush set inet abuse "$SET2"

TOTAL2=$(wc -l < "$OUTFILE2")
echo "Updating nftables blocklist with $TOTAL2 IPs in batches of $BATCH_SIZE..."
count=0
BATCH=()
while IFS= read -r ip; do
    BATCH+=("$ip")
    count=$((count + 1))
    if (( ${#BATCH[@]} >= BATCH_SIZE )) || (( count == TOTAL2 )); then
        ELEMENTS=$(IFS=, ; echo "${BATCH[*]}")
        sudo nft add element inet abuse "$SET2" { $ELEMENTS }
        BATCH=()
        PERCENT=$((count * 100 / TOTAL2))
        printf "\rProgress: %d/%d (%d%%)" "$count" "$TOTAL2" "$PERCENT"
    fi
done < "$OUTFILE2"
echo -e "\nSkipa blacklist updated"
echo -e "\nDone updating blocklists"
