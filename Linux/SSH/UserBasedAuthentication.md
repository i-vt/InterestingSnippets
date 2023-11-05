# Configuring SSH on Linux
Tested on ubuntu 22.04.03 LTS

### Check for updates
```
sudo apt update
sudo apt install openssh-server -y
```

### Modify configs
```
vim /etc/ssh/sshd_config
```

Uncomment: 
```
#PasswordAuthentication yes
```
```
PasswordAuthentication yes
```

### Restart services 
```
sudo service ssh restart
```

### Separate privs:
Probably recommended to run on a separate user to separate privs:
```
sudo adduser your_username
sudo passwd your_username
```

modify /etc/ssh/sshd_config to add users (if multiple separate by space)
```
AllowUsers your_username
```

### Manage UFW 


```
sudo apt install ufw -y
sudo ufw enable
```

Just allow all IPs to SSH:
```
sudo ufw allow 22/tcp
```

Restrict to a set of IPs:
```
sudo ufw allow from your_specific_ip to any port 22
sudo ufw deny 22/tcp
```

### Check on it:
Try to SSH into the box:
```
ssh your_username@10.1.1.1
```
If any issues arise restart the service again:
```
sudo service ssh restart
```
