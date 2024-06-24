# Troubleshooting Cisco Networking Devices

## Identify Fault

1. **show version**
   - Provides detailed information about the device’s software and hardware, including uptime, image version, and model.

2. **show interfaces**
   - Displays detailed information about all interfaces, including their status, errors, and statistics.

3. **show ip interface brief**
   - Provides a summary of the status and IP address of all interfaces, making it easier to spot down or unassigned interfaces.

4. **show running-config**
   - Displays the current configuration of the device, essential for verifying settings and identifying configuration issues.

5. **show ip route**
   - Shows the routing table, helping to identify routing issues and verify that routes are being correctly advertised and learned.

6. **show logging**
   - Displays the device’s log messages, which can provide insight into events leading up to a fault.

7. **show ip arp**
   - Shows the ARP table, useful for diagnosing layer 2 connectivity issues.

8. **show cdp neighbors**
   - Displays information about directly connected Cisco devices, useful for verifying physical connections and identifying neighbors.

9. **show ip protocols**
   - Displays information about the IP routing protocols that are configured and their status.

10. **show processes cpu**
    - Provides CPU utilization details, useful for identifying high CPU usage that might indicate a performance issue.

11. **show memory**
    - Displays memory usage, helping to identify memory leaks or issues causing high memory utilization.

12. **show spanning-tree**
    - Shows the spanning tree status for VLANs, useful for diagnosing layer 2 loops and topology changes.'

## Privilege Elevation

```
1. enable
2. configure terminal
3. Use one of the following:
• enable password [level level]
{password | encryption-type encrypted-password}
• enable secret [level level]
{password | encryption-type encrypted-password}
4. service password-encryption
5. end
6. show running-config
7. copy running-config startup-config
```

## Disabling / Enabling a port
```
Switch>enable

Switch#conf t

Switch#(config)int fa 0/1

Switch#(config-int)shut

Switch#(config-int) no shut
```
