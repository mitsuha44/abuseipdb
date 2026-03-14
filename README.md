
# AbuseIPDB NFTables Blacklist

blacklist.txt in releases contains ipv4 addresses and fetched every 6 hours from [abuseipdb](https://www.abuseipdb.com).

You can use it by following inscructions bellow

---

## 1. Create Script

This script downloads the latest blacklist from GitHub and updates the `nftables` set:

```bash
sudo tee /usr/local/bin/update-blacklist.sh > /dev/null <<'EOF'
#!/bin/bash

TABLE="inet abuse"
SET="blacklist"
CHAIN="input"
OUTFILE="/tmp/blacklist.txt"
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

# Create set if it doesn't exist
if ! sudo nft list set inet abuse "$SET" &>/dev/null; then
    echo "Creating set $SET..."
    sudo nft "add set inet abuse $SET { type ipv4_addr; flags interval; }"
else
    echo "Set $SET already exists."
fi

# Create chain if it doesn't exist
if ! sudo nft list chain inet abuse "$CHAIN" &>/dev/null; then
    echo "Creating chain $CHAIN..."
    sudo nft "add chain inet abuse $CHAIN { type filter hook input priority 0; policy accept; }"
else
    echo "Chain $CHAIN already exists."
fi

# Add rule if it doesn't exist
if ! sudo nft list chain inet abuse "$CHAIN" | grep -q "\[ABUSE IP\]"; then
    echo "Adding rule to drop and log blacklist IPs..."
    sudo nft "add rule inet abuse $CHAIN ip saddr @$SET counter log prefix \"[ABUSE IP] \" drop"
else
    echo "Blacklist rule already exists."
fi

# --- Step 1: Download latest blacklist ---
echo "Downloading latest blacklist..."

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

echo -e "\nDone updating nftables blacklist."
EOF
```

## 3. Make the Script Executable

```bash
sudo chmod +x /usr/local/bin/update-blacklist.sh
```

## 4. Add Cron Job

Run the script automatically every 6 hours:

```bash
sudo crontab -e
```

Github workflow makes a release every 6 hours, we will fetch new IPs 10 minutes after release

```cron
10 */6 * * * /usr/local/bin/update-blacklist.sh >> /var/log/update-blacklist.log 2>&1
```

Verify the cron job:

```bash
sudo crontab -l
```
## 5. (Optional) Run  it manually

```bash
sudo /usr/local/bin/update-blacklist.sh
```

## 6. Check Logs

You can quickly check amount of blocked attempts for last 24 hours with:

```bash
sudo journalctl -k --since "24 hours ago" | grep -c "ABUSE IP"
```

## Notes

* Logs of blocked packets are available in your system logs (`/var/log/kern.log` or `journalctl -k`)
* The counter in `nftables` keeps track of packets and bytes blocked by the blacklist
* Make sure your system allows root to run the script and update `nftables`
