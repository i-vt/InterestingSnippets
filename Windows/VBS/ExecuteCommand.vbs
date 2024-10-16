' Execute Notepad
shell.Run "notepad.exe"

' Run a command and wait for it to finish
shell.Run "cmd.exe /c echo Hello, World!", 1, True
