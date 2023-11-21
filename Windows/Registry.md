# Registry

## Introduction

### In Depth:
The Windows Registry is a hierarchical database that stores low-level settings for the Microsoft Windows operating system and for applications that opt to use the Registry. It contains information, settings, options, and other values for hardware, operating system software, most non-operating system software, and per-user settings. The Registry acts as a central repository for configuration data, effectively controlling how Windows and many installed applications behave and interact with the system and with each other.

### TLDR:
The Windows Registry is like a central control panel for the operating system, where various settings and options are stored much like a library's catalog system organizes and tracks books.

## Interesting Spots:

### Misc
- 418 Teapot status can be enabled: ```HKEY_CURRENT_USER\Software\Microsoft\Internet Explorer\Main``` if you create a string value named `Enable Browser Extensions` and set its value to `TeaPot`.
- OEM information can be changed: ```HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\OEMInformation``` specifically the values: `Manufacturer`, `Model`, `Logo`, and `SupportHours`.


### Forensics
- Last application opened via start menu: ```HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Explorer\UserAssist```
- Shell bags to reconstruct user's activity & interaction with file explorer: ```HKEY_USERS\[User SID]\Software\Microsoft\Windows\Shell\Bags```
- URLs typed into explorer: ```HKEY_CURRENT_USER\Software\Microsoft\Internet Explorer\TypedURLs``` and ```HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Explorer\RunMRU```
- Check for browser-based infections: ```HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Browser Helper Objects```
- Contains security settings & password hashes: ```HKEY_LOCAL_MACHINE\SAM``` and ```HKEY_LOCAL_MACHINE\SECURITY```

### Persistance:
In order for the application to stay running on the computer upon every reboot (after initial run) the registry keys can be created here:

- Run every time a specific user logs in: ```HKCU\Software\Microsoft\Windows\CurrentVersion\Run```
- Run every time any user logs in: ```HKLM\Software\Microsoft\Windows\CurrentVersion\Run```
- Run the next time current user logs in: ```HKCU\Software\Microsoft\Windows\CurrentVersion\RunOnce```
- Run the next time any user logs in: ```HKLM\Software\Microsoft\Windows\CurrentVersion\RunOnce```
- Reconfigure a service to execute as diff path: ```HKEY_LOCAL_MACHINE\System\CurrentControlSet\Services```

### Debugging & Optimization

- Specifies DLLs to be loaded into each process that calls User32.dll (DLL injection): ```HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Windows\AppInit_DLLs```

