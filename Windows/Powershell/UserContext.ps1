# =============================
# User Context
# =============================
$currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
$userContext = $currentIdentity.Name
$isSystem = ($userContext -like "*SYSTEM")
$isAdmin = (New-Object Security.Principal.WindowsPrincipal $currentIdentity).IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)

if ($isSystem) {
    $privilege = "SYSTEM"
} elseif ($isAdmin) {
    $privilege = "Administrator"
} else {
    $privilege = "User"
}
Write-Host "`n[+] User Context:"
Write-Host "User: $userContext"
Write-Host "Privilege Level: $privilege"
