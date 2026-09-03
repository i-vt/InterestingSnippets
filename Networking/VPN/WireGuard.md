# WireGuard

## Server Configs

1. Run angristan_wireguard-installer.sh, OG source: [here](https://github.com/angristan/wireguard-install/blob/master/wireguard-install.sh)

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/i-vt/InterestingSnippets/refs/heads/main/Networking/VPN/angristan_wireguard-installer.sh)
```

2. It fucks up DNS resolution b/c it removes nameservers, so re-add them:

```bash
if ! grep -qE 'nameserver (8\.8\.8\.8|1\.1\.1\.1)' /etc/resolv.conf; then
  echo "Neither 8.8.8.8 nor 1.1.1.1 found. Adding 8.8.8.8..."
  echo "nameserver 8.8.8.8" | sudo tee -a /etc/resolv.conf > /dev/null
else
  echo "Nameserver already set correctly."
fi
```

After a while it may fuck up again, so you may wanna set it as a service:

```bash
#!/usr/bin/env bash
# install-ensure-dns.sh — run once as root, then this file can be removed.
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Please run as root: sudo bash $0" >&2
  exit 1
fi

# 1) The actual check script (this is what the service runs)
cat > /usr/local/sbin/ensure-dns.sh <<'EOF'
#!/usr/bin/env bash
if ! grep -qE 'nameserver (8\.8\.8\.8|1\.1\.1\.1)' /etc/resolv.conf; then
  echo "Neither 8.8.8.8 nor 1.1.1.1 found. Adding 8.8.8.8..."
  echo "nameserver 8.8.8.8" >> /etc/resolv.conf
else
  echo "Nameserver already set correctly."
fi
EOF
chmod 755 /usr/local/sbin/ensure-dns.sh

# 2) systemd service (oneshot)
cat > /etc/systemd/system/ensure-dns.service <<'EOF'
[Unit]
Description=Ensure a public DNS nameserver exists in /etc/resolv.conf

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/ensure-dns.sh
EOF

# 3) systemd timer (hourly, plus once shortly after boot)
cat > /etc/systemd/system/ensure-dns.timer <<'EOF'
[Unit]
Description=Hourly check of /etc/resolv.conf nameservers

[Timer]
OnBootSec=2min
OnCalendar=hourly
Persistent=true

[Install]
WantedBy=timers.target
EOF

# 4) Activate
systemctl daemon-reload
systemctl enable --now ensure-dns.timer

echo
echo "Done. Installed:"
echo "  - /usr/local/sbin/ensure-dns.sh"
echo "  - /etc/systemd/system/ensure-dns.service"
echo "  - /etc/systemd/system/ensure-dns.timer"
systemctl list-timers ensure-dns.timer --no-pager
```

## Client Configs

### Linux
```bash
sudo apt install wireguard -y
sudo apt install resolvconf -y
touch ~/.bashrc
[ -f ~/.bashrc ] && grep -Fxq 'export PATH=$PATH:/usr/sbin' ~/.bashrc || echo 'export PATH=$PATH:/usr/sbin' >> ~/.bashrc
echo "alias wgup='wg-quick up /etc/wireguard/wg0.conf'" >> ~/.bashrc
echo "alias wgdown='wg-quick down /etc/wireguard/wg0.conf'" >> ~/.bashrc
source ~/.bashrc
# copy from root@server# ~/wg0-client-computer1.conf
sudo vi /etc/wireguard/wg0.conf
sudo reboot
```


To add to startup: 

```bash
sudo systemctl enable wg-quick@wg0
```
To turn on wireguard
```
sudo wgup
```
Turn off wireguard
```
sudo wgdown
```
### iOS

Install WireGuard client from app store


![image](https://github.com/user-attachments/assets/18330c08-2ddf-4ecd-8d66-0f5ccb5da32d)

