# WireGuard

## Server Configs

run angristan_wireguard-installer.sh, OG source: [here](https://github.com/angristan/wireguard-install/blob/master/wireguard-install.sh)

## Client Configs

### Linux
```
sudo apt install wireguard -y
sudo apt install resolvconf -y
```
Add this to the `~/.bashrc` file: `export PATH=$PATH:/usr/sbin`
```
vi ~/bashrc
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
wg-quick up /etc/wireguard/wg0.conf
```
Turn off wireguard
```
wg-quick down /etc/wireguard/wg0.conf
```
### iOS

Install WireGuard client from app store
