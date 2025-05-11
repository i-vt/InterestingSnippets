# Step 1: Create or set the file association for .txt files to a custom ProgID
New-Item -Path "HKCU:\Software\Classes\.txt" -Force
Set-ItemProperty -Path "HKCU:\Software\Classes\.txt" -Name '(Default)' -Value 'txtfile'

# Step 2: Create the ProgID path and the shell open command
New-Item -Path "HKCU:\Software\Classes\txtfile\shell\open\command" -Force
Set-ItemProperty -Path "HKCU:\Software\Classes\txtfile\shell\open\command" -Name '(Default)' -Value 'C:\Windows\System32\calc.exe'
