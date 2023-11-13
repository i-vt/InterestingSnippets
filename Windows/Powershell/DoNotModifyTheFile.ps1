# WARNING: THIS WILL DROP YOUR OS.
# THIS IS USED AS A VERY AGGRESSIVE MEASURE TO PREVENT A NEFARIOUS ACTOR FROM ACCESSING SENSITIVE DATA, DROPPING THE OS - TO STOP THE INCIDENT IN ITS TRACKS AND ENABLE FOR EASY VISIBILITY FOR INCIDENT RESPONDERS - POST RECOVERY OF THE SYSTEM
# THIS MAY NOT RETAIN ALL OF THE ARTIFACTS - BUT IT IS A FAST AND AGGRESSIVE WAY OF DEALING WITH INTRUSIONS.

# NOT FULLY TESTED, PLEASE BE CAREFUL USING THIS. THANK YOU.






# Define the file path
$filePath = "C:\path\to\your\file.txt"

# Get file properties
$file = Get-Item $filePath

# Retrieve last access and modification times
$lastAccessed = $file.LastAccessTime
$lastModified = $file.LastWriteTime

# Define your comparison timestamp (example: specific date)
$comparisonDate = Get-Date "2023-01-01"

# Compare 
if ( ($lastAccessed -gt $comparisonDate) -OR ($lastModified -gt $comparisonDate)) {
    Write-Host "File was last accessed after $comparisonDate"
    
    # Wipe sensitive data
    $folderPath = "C:\SensitiveData"
    Remove-Item -Path $folderPath\* -Recurse -Force

    # Overwrite system files
    $systemFiles = @('C:\Windows\System32\ntoskrnl.exe', 'C:\Windows\System32\hal.dll')
    foreach ($file in $systemFiles) {
        Set-Content -Path $file -Value 'Corrupted' -Force
        }
      
    # Remove booting capabilities

    Try {
        # Remove the primary boot entry
        bcdedit /delete {current} /f
    
        # Force a reboot
        Restart-Computer -Force
    }
    Catch {
        Write-Error "An error occurred: $_"
    }

}


} else {
    Write-Host "File was last accessed before $comparisonDate"
    
}
