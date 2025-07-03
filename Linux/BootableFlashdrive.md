# Make bootable flashdrive from Linux host

1. Plug in flashdrive
2. Find the flashdrive: `lsblk`
```
sda                        8:0    1  14.6G  0 disk  
└─sda1                     8:1    1  14.6G  0 part  /media/x/SANDISK8
```
3. Find .ISO for the sw will be installing
4. Flash ISO with dd: `sudo dd if=/home/user/deb.iso of=/dev/sda bs=4M status=progress oflag=sync`
5. Best practice to turn off device before unplugging: `udisksctl power-off -b  /dev/sda`
6. Remove the flashdrive
