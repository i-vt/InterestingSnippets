# WireGuard

## Server Configs

1. Run angristan_wireguard-installer.sh, OG source: [here](https://github.com/angristan/wireguard-install/blob/master/wireguard-install.sh)

```
bash <(curl -fsSL https://raw.githubusercontent.com/i-vt/InterestingSnippets/refs/heads/main/Networking/VPN/angristan_wireguard-installer.sh)
```

2. It fucks up DNS resolution b/c it removes nameservers, so re-add them:

```
if ! grep -qE 'nameserver (8\.8\.8\.8|1\.1\.1\.1)' /etc/resolv.conf; then
  echo "Neither 8.8.8.8 nor 1.1.1.1 found. Adding 8.8.8.8..."
  echo "nameserver 8.8.8.8" | sudo tee -a /etc/resolv.conf > /dev/null
else
  echo "Nameserver already set correctly."
fi
```

## Client Configs

### Linux
```
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
```
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

