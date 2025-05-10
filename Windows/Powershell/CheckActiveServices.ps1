
# =============================
# Active Services
# =============================
Write-Host "`n[+] Active Services (Get-Service):"
try {
    Get-Service | Where-Object {$_.Status -eq "Running"} | Format-Table -AutoSize | Out-String | Write-Host
} catch {
    Write-Host "Failed to get services"
}
