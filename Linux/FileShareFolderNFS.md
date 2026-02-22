# NFS
- linux to linux interactions are optimal for this
- Computer A (192.168.1.9) hosting the share, Computer B (192.168.1.10) connecting to it

---

## Computer A (server)

### Set up the folder

```
sudo apt update
sudo apt install nfs-kernel-server
mkdir -p /home/user/shared
sudo chown nobody:nogroup /home/user/shared
sudo chmod 777 /home/user/shared
```

### Set up permissions
add `/home/shared 192.168.1.10(rw,sync,no_subtree_check)` (.10 is of the connecting computer, not the server) to the file `/etc/exports` 

### Restart services
```
sudo exportfs -a
sudo systemctl restart nfs-kernel-server
```

---

## Computer B (client)
```
sudo apt update
sudo apt install nfs-common
mkdir -p ~/shared
sudo mount 192.168.1.9:/home/user/shared ~/shared
```

### Mount automatically
1. edit `/etc/fstab`, and add this:
```
192.168.1.10:/home/shared /home/youruser/shared nfs defaults 0 0
```
2. test: `sudo mount -a`
