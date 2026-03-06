
# AbuseIPDB NFTables Blacklist

blacklist.txt in releases contains ipv4 addresses and fetched every 6 hours from [abuseipdb](https://www.abuseipdb.com).

You can use it by following inscructions bellow

---

## 1. Create NFTables Table, Set, and Chain

```bash
sudo nft add table inet abuse

sudo nft 'add set inet abuse blacklist { type ipv4_addr; flags interval; }'

sudo nft 'add chain inet abuse input { type filter hook input priority 0; policy accept; }'

sudo nft 'add rule inet abuse input ip saddr @blacklist counter log prefix "[ABUSE IP] " drop'
````

## 2. Create Update Script

This script downloads the latest blacklist from GitHub and updates the `nftables` set:

```bash
sudo tee /usr/local/bin/update-blacklist.sh > /dev/null <<'EOF'
#!/bin/bash
OUTFILE="/tmp/blacklist.txt"
BATCH_SIZE=1000  # number of IPs per nft command

echo "Downloading latest blacklist..."
curl -sL https://github.com/mitsuha44/abuseipdb/releases/latest/download/blacklist.txt \
  -o "$OUTFILE"

# Keep only IPv4 addresses
grep -Eo '([0-9]{1,3}\.){3}[0-9]{1,3}' "$OUTFILE" > "${OUTFILE}.ipv4"
mv "${OUTFILE}.ipv4" "$OUTFILE"

# Flush existing nftables set
sudo nft flush set inet abuse blacklist

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
        sudo nft add element inet abuse blacklist { $ELEMENTS }
        BATCH=()  # clear batch

        # progress percentage only
        PERCENT=$((count * 100 / TOTAL))
        printf "\rProgress: %d/%d (%d%%)" "$count" "$TOTAL" "$PERCENT"
    fi
done < "$OUTFILE"

echo -e "\nDone updating nftables blacklist."
EOF
```

---

## 3. Make the Script Executable

```bash
sudo chmod +x /usr/local/bin/update-blacklist.sh
```

---

## 4. Add Cron Job

Run the script automatically every 12 hours:

```bash
sudo crontab -e
```

Add the following line:

```cron
0 */12 * * * /usr/local/bin/update-blacklist.sh >> /var/log/blacklist-update.log 2>&1
```

Verify the cron job:

```bash
sudo crontab -l
```

---

## 5. Logs

You can quickly check amount of blocked attempts for last 24 hours with:

```bash
sudo journalctl -k --since "24 hours ago" | grep -c "\[ABUSE IP\]"
```

## Notes

* Logs of blocked packets are available in your system logs (`/var/log/kern.log` or `journalctl -k`)
* The counter in `nftables` keeps track of packets and bytes blocked by the blacklist
* Make sure your system allows root to run the script and update `nftables`
