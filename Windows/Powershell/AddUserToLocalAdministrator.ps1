# Define the domain and user
$domain = "ball123"
$user = "usernamegoeshere"
$group = "Administrators"
$fullUser = "$domain\$user"

# Check if user is already in the Administrators group
$groupMembers = net localgroup $group
if ($groupMembers -match [regex]::Escape($fullUser)) {
    Write-Output "$fullUser is already a member of $group."
} else {
    # Add the user to the group
    net localgroup $group "$fullUser" /add
    if ($LASTEXITCODE -eq 0) {
        Write-Output "Successfully added $fullUser to $group."
    } else {
        Write-Error "Failed to add $fullUser to $group."
    }
}

# Force a group policy update
gpupdate.exe /force
