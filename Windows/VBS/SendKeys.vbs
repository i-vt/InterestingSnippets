' Open Notepad and type "Hello, World!"
shell.Run "notepad.exe"
Application.Wait Now + TimeValue("0:00:02") ' Wait for Notepad to open
shell.SendKeys "Hello, World!"
