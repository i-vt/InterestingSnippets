# =============================
# Available Drives
# =============================
Write-Host "`n[+] Available Drives (Get-PSDrive):"
try {
    Get-PSDrive -PSProvider FileSystem | Format-Table Name, Root, Used, Free -AutoSize | Out-String | Write-Host
} catch {
    Write-Host "Failed to list drives"
}
