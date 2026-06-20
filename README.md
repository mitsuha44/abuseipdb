
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

Check last 100 elements:

```bash
sudo journalctl -k -n 100 | grep "ABUSE"
sudo journalctl -k -n 100 | grep "ABUSE_abuseipdb"
sudo journalctl -k -n 100 | grep "ABUSE_skipa"
```

Watch live:

```bash
sudo journalctl -k -n 50 -f | grep -c "ABUSE"
sudo journalctl -k -n 50 -f | grep -c "ABUSE_abuseipdb"
sudo journalctl -k -n 50 -f | grep -c "ABUSE_skipa"
```

## Notes

* Logs of blocked packets are available in your system logs (`/var/log/kern.log` or `journalctl -k`)
* The counter in `nftables` keeps track of packets and bytes blocked by the blacklist
* Make sure your system allows root to run the script and update `nftables`
