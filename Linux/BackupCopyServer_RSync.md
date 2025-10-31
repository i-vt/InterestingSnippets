# BackupCopyServer_RSync
1. Install rsync: `sudo apt install rsync -y` (on both devices)
2. Run this on the receiving computer
```
mkdir -p /local/backup/root

rsync -aHAX --partial --info=progress2 --stats \
--exclude='/root/.cache' -e "ssh -p 22" \
root@vps.example.com:/root/ /local/backup/root/
```
