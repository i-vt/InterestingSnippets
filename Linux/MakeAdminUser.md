
# Cleanup
```
userdel -r adminuser && sed -i '/^admin:/d' /etc/group && sed -i '/^admin:/d' /etc/gshadow && sed -i '/^%admin ALL=(ALL:ALL) ALL$/d' /etc/sudoers
```

# Create admin group and add adminuser
```
groupadd admin && useradd -m -s /bin/bash -G admin adminuser && echo 'adminuser:changeme' | chpasswd && echo '%admin ALL=(ALL:ALL) ALL' >> /etc/sudoers
```
Ignore `userdel: adminuser mail spool (/var/mail/adminuser) not found`
