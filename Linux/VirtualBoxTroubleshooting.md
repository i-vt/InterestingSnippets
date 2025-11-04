# VirtualBox Troubleshooting

## Issue 

```
VM Name: Bubuntu213123 
AMD-V is being used by another hypervisor (VERR_SVM_IN_USE). 
VirtualBox can't enable the AMD-V extension. 
Please disable the KVM kernel extension, recompile your kernel and reboot (VERR_SVM_IN_USE). 
Result Code: NS_ERROR_FAILURE (0x80004005) 
Component: ConsoleWrap 
Interface: IConsole {}
```

1. Check the KVM is loaded (something like this):
```
usr@computa:/home/usr$ lsmod | grep kvm
kvm_amd              [somenum]  0
kvm                  [somenum]  1 kvm_amd
irqbypass            [somenum]  1 kvm
ccp                  [somenum]  1 kvm_amd
```
2. Unload them
```
sudo modprobe -r kvm_amd
sudo modprobe -r kvm
```
3. Restart the VirtualBox 

4. (OPTIONAL) make it permanent & break KVM + Quemu
```
echo "blacklist kvm_amd" | sudo tee /etc/modprobe.d/blacklist-kvm.conf
echo "blacklist kvm" | sudo tee -a /etc/modprobe.d/blacklist-kvm.conf
sudo update-initramfs -u
sudo reboot
```
