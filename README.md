
# AbuseIPDB NFTables Blacklist

blacklist.txt in releases contains ipv4 addresses and fetched every 6 hours from [abuseipdb](https://www.abuseipdb.com).

You can use it by following inscructions bellow

---

## 1. Install

```bash
curl -fsSL https://raw.githubusercontent.com/mitsuha44/abuseipdb/refs/heads/main/install.sh | sudo bash
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
