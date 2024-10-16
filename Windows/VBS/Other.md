Special folders:
```
Dim desktopPath As String
desktopPath = shell.SpecialFolders("Desktop")
MsgBox "Desktop Path: " & desktopPath
```

Access env vars:
```
Dim userName As String
userName = shell.Environment("PROCESS")("USERNAME")
MsgBox "Current User: " & userName
```

Popup
```
shell.Popup "Operation Completed Successfully.", 5, "Status", vbInformation
```

Activate app window
```
' Activate the Notepad window
shell.AppActivate "Notepad"
```
