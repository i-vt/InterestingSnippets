# =============================
# System Information
# =============================
Write-Host "`n[+] System Information (systeminfo):"
try {
    systeminfo | Out-String | Write-Host
} catch {
    Write-Host "Failed to execute 'systeminfo'"
}
