# =============================
# Tasklist with Services
# =============================
Write-Host "`n[+] Processes and Services (tasklist /svc):"
try {
    tasklist /svc | Out-String | Write-Host
} catch {
    Write-Host "Failed to execute 'tasklist /svc'"
}
