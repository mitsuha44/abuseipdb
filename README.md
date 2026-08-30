
# AbuseIPDB NFTables Blacklist

blacklist.txt in releases contains ipv4 addresses and fetched every 6 hours from [abuseipdb](https://www.abuseipdb.com).

You can use it by following inscructions bellow

---

## 1. Install

```bash
curl -fsSL https://raw.githubusercontent.com/mitsuha44/abuseipdb/refs/heads/main/install.sh | sudo bash
```

## 2. Run  it manually once

```bash
update-abuse-blackist
```

## 3. Check Logs

You can quickly check amount of blocked attempts for last 24 hours with:

```bash
sudo journalctl -k --since "24 hours ago" | grep -c "ABUSE"
sudo journalctl -k --since "24 hours ago" | grep -c "ABUSE_abuseipdb"
sudo journalctl -k --since "24 hours ago" | grep -c "ABUSE_skipa"
```

Check most abused networks (mask /24) for last week:

```bash
echo "COUNT    NETWORK"
sudo journalctl -k --since "168 hours ago" |
  grep "ABUSE" |
  grep -oP 'SRC=\K[0-9]{1,3}(\.[0-9]{1,3}){3}' |
  sed 's/\.[0-9]*$/.0/' |
  sort | uniq -c | sort -rn |
  head -20 |
  awk '{printf "%-8d %s\n", $1, $2}'
```

Check most abused networks (mask /16) for last week:

```bash
echo "COUNT    NETWORK"
sudo journalctl -k --since "168 hours ago" |
  grep "ABUSE" |
  grep -oP 'SRC=\K[0-9]{1,3}(\.[0-9]{1,3}){3}' |
  sed -E 's/^([0-9]+\.[0-9]+)\.[0-9]+\.[0-9]+$/\1.0.0/' |
  sort | uniq -c | sort -rn |
  head -20 |
  awk '{printf "%-8d %s/16\n", $1, $2}'
```

## 4. Useful commands

### Delete nftables table

```bash
sudo nft delete table inet abuse
```

### Check nftables chain

```bash
sudo nft list chain inet abuse input
```

## Notes

* Logs of blocked packets are available in your system logs (`/var/log/kern.log` or `journalctl -k`)
* The counter in `nftables` keeps track of packets and bytes blocked by the blacklist
* Make sure your system allows root to run the script and update `nftables`
