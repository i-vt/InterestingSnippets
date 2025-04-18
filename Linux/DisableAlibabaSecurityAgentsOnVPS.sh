#!/bin/bash

echo "[*] Starting removal of Alibaba Cloud Shield components..."

# Kill running processes
echo "[*] Killing known Alibaba Cloud Shield processes..."
for PROC in aegisupdate aegiscli aegisupdate aegis ayns; do
    pkill -f $PROC 2>/dev/null
done

# Remove init and systemd services
echo "[*] Disabling and removing known services..."
systemctl disable --now aliyun.service 2>/dev/null
systemctl disable --now aegis.service 2>/dev/null
rm -f /etc/systemd/system/aliyun.service
rm -f /etc/systemd/system/aegis.service

# Remove binaries
echo "[*] Removing binaries..."
rm -rf /usr/local/aegis
rm -rf /usr/local/cloudmonitor
rm -f /usr/sbin/aliyun*
rm -f /usr/bin/aegis*

# Remove startup scripts
echo "[*] Cleaning up init.d and rc.local entries..."
sed -i '/aliyun/d' /etc/rc.local 2>/dev/null
sed -i '/aegis/d' /etc/rc.local 2>/dev/null
chmod -x /etc/rc.d/init.d/aegis 2>/dev/null
rm -f /etc/rc.d/init.d/agentwatch /etc/init.d/agentwatch

# Remove crontab entries
echo "[*] Removing any related crontab jobs..."
crontab -l | grep -v 'aliyun' | grep -v 'aegis' | crontab -

# Block known Alibaba Cloud Shield IPs
echo "[*] Blocking known Alibaba Cloud Shield IPs..."
iptables -A OUTPUT -d 140.205.201.0/24 -j DROP
iptables -A OUTPUT -d 140.205.201.1 -j DROP
iptables -A OUTPUT -d 140.205.201.2 -j DROP
iptables -A OUTPUT -d 140.205.201.3 -j DROP
iptables -A OUTPUT -d 140.205.201.4 -j DROP
iptables -A OUTPUT -d 140.205.201.5 -j DROP
iptables -A OUTPUT -d 140.205.201.6 -j DROP
iptables -A OUTPUT -d 140.205.201.7 -j DROP
iptables -A OUTPUT -d 203.107.1.1 -j DROP

# Make the iptables rules persistent
echo "[*] Saving iptables rules..."
if command -v iptables-save &>/dev/null; then
    iptables-save > /etc/iptables.rules
    echo -e "[Unit]\nDescription=Restore iptables rules\n[Service]\nType=oneshot\nExecStart=/sbin/iptables-restore < /etc/iptables.rules\n[Install]\nWantedBy=multi-user.target" > /etc/systemd/system/iptables-restore.service
    systemctl enable iptables-restore
fi

echo "[+] Removal complete. It is recommended to reboot the system."


# Ensure it does not come back
chattr +i /usr/local/aegis /etc/systemd/system/aliyun.service
# Alibaba agents sometimes auto-reinstall if part of their provisioning scripts remains. Be cautious — use this only after confirming removal, as it will make those paths immutable.
