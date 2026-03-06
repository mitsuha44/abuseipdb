
# AbuseIPDB NFTables Blacklist

blacklist.txt in releases contains ipv4 addresses and fetched every 6 hours from [abuseipdb](https://www.abuseipdb.com).

You can use it by following inscructions bellow

---

## 1. Create NFTables Table, Set, and Chain

```bash
# Create table
sudo nft add table inet abuse

# Create IPv4 set for blacklisted IPs
sudo nft 'add set inet abuse blacklist { type ipv4_addr; flags interval; }'

# Create input chain
sudo nft 'add chain inet abuse input { type filter hook input priority 0; policy accept; }'

# Add drop rule for blacklisted IPs
sudo nft 'add rule inet abuse input ip saddr @blacklist drop'
````

## 2. Add Logging and Counter

```bash
# Optional: log and count blocked packets
sudo nft add rule inet abuse input ip saddr @blacklist counter log prefix \"[ABUSE IP] \" drop
```

* Logs blocked packets with the prefix `[ABUSE IP]`
* Tracks packets and bytes in the counter

---

## 3. Create Update Script

This script downloads the latest blacklist from GitHub and updates the `nftables` set:

```bash
cat <<'EOF' > /usr/local/bin/update-blacklist.sh
#!/bin/bash
OUTFILE="/tmp/blacklist.txt"

# Direct download from latest release
curl -L https://github.com/mitsuha44/abuseipdb/releases/latest/download/blacklist.txt \
  -o "$OUTFILE"

# Update nftables set
sudo nft flush set inet abuse blacklist
sudo xargs -a "$OUTFILE" -I {} sudo nft add element inet abuse blacklist { {} }
EOF
```

---

## 4. Make the Script Executable

```bash
sudo chmod +x /usr/local/bin/update-blacklist.sh
```

---

## 5. Add Cron Job

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

## 6. Logs

You can quickly check amount of blocked attempts for last 24 hours with:

```bash
sudo journalctl -k --since "24 hours ago" | grep -c "\[ABUSE IP\]"
```

## Notes

* Logs of blocked packets are available in your system logs (`/var/log/kern.log` or `journalctl -k`)
* The counter in `nftables` keeps track of packets and bytes blocked by the blacklist
* Make sure your system allows root to run the script and update `nftables`
