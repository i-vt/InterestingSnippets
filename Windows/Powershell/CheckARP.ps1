# =============================
# ARP Table
# =============================
Write-Host "`n[+] ARP Table (arp -a):"
try {
    arp -a | Out-String | Write-Host
} catch {
    Write-Host "Failed to execute 'arp -a'"
}
