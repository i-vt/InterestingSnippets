# Registry

## Introduction

### In Depth:
The Windows Registry is a hierarchical database that stores low-level settings for the Microsoft Windows operating system and for applications that opt to use the Registry. It contains information, settings, options, and other values for hardware, operating system software, most non-operating system software, and per-user settings. The Registry acts as a central repository for configuration data, effectively controlling how Windows and many installed applications behave and interact with the system and with each other.

### TLDR:
The Windows Registry is like a central control panel for the operating system, where various settings and options are stored much like a library's catalog system organizes and tracks books.

## Interesting Spots:

### Persistance:
In order for the application to stay running on the computer upon every reboot (after initial run) the registry keys can be created here:

- Run every time a specific user logs in: ```HKCU\Software\Microsoft\Windows\CurrentVersion\Run```
- Run every time any user logs in: ```HKLM\Software\Microsoft\Windows\CurrentVersion\Run```
- Run the next time current user logs in: ```HKCU\Software\Microsoft\Windows\CurrentVersion\RunOnce```
- Run the next time any user logs in: ```HKLM\Software\Microsoft\Windows\CurrentVersion\RunOnce```
