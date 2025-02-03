# WireGuard

## Server Configs

run angristan_wireguard-installer.sh, OG source: [here](https://github.com/angristan/wireguard-install/blob/master/wireguard-install.sh)

## Client Configs

### Linux
```
sudo apt install wireguard
# copy from root@server# ~/wg0-client-computer1.conf
sudo vi /etc/wireguard/wg0.conf
wg-quick up /etc/wireguard/wg0.conf
```


Turn off wireguard
```
wg-quick down /etc/wireguard/wg0.conf
```
### iOS

Install WireGuard client from app store
