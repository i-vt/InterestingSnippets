# VirtualBox Troubleshooting


## Sign KVM

```
sudo /sbin/vboxconfig

sudo mkdir -m 0700 -p /var/lib/shim-signed/mok
sudo openssl req -nodes -new -x509 -newkey rsa:2048 -outform DER -addext "extendedKeyUsage=codeSigning" -keyout /var/lib/shim-signed/mok/MOK.priv -out /var/lib/shim-signed/mok/MOK.der
sudo mokutil --import /var/lib/shim-signed/mok/MOK.der


# sudo reboot
```




## KVM Loaded

```
VM Name: Bubuntu213123 
AMD-V is being used by another hypervisor (VERR_SVM_IN_USE). 
VirtualBox can't enable the AMD-V extension. 
Please disable the KVM kernel extension, recompile your kernel and reboot (VERR_SVM_IN_USE). 
Result Code: NS_ERROR_FAILURE (0x80004005) 
Component: ConsoleWrap 
Interface: IConsole {}
```

1. Check the KVM is loaded via the command `lsmod | grep kvm`

AMD: 
```
usr@computa:/home/usr$ lsmod | grep kvm
kvm_amd              [somenum]  0
kvm                  [somenum]  1 kvm_amd
irqbypass            [somenum]  1 kvm
ccp                  [somenum]  1 kvm_amd
```

Intel: 
```
user@host: lsmod | grep kvm
kvm_intel             413696  0
kvm                  1396736  1 kvm_intel
irqbypass              12288  1 kvm
```

2. Unload them

AMD: 
```
sudo modprobe -r kvm_amd
sudo modprobe -r kvm
```

Intel:
```
sudo modprobe -r kvm_intel
sudo modprobe -r kvm
```

3. Restart the VirtualBox 

4. (OPTIONAL) make it permanent & break KVM + Quemu
AMD: 
```
echo "blacklist kvm_amd" | sudo tee /etc/modprobe.d/blacklist-kvm.conf
echo "blacklist kvm" | sudo tee -a /etc/modprobe.d/blacklist-kvm.conf
sudo update-initramfs -u
sudo reboot
```

Intel:
```
echo "blacklist kvm_intel" | sudo tee /etc/modprobe.d/blacklist-kvm.conf
echo "blacklist kvm" | sudo tee -a /etc/modprobe.d/blacklist-kvm.conf
sudo update-initramfs -u
sudo reboot
```
