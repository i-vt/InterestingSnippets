# WireGuard

## Server Configs


## Client Configs
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
