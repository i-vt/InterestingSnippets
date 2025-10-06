#!/bin/bash
# Script to create a privileged sudo user on Debian/Ubuntu systems
# Run this as root (or with sudo)

# Exit on error
set -e

# Prompt for username
read -rp "Enter new username: " USERNAME

# Check if user already exists
if id "$USERNAME" &>/dev/null; then
    echo "User '$USERNAME' already exists!"
    exit 1
fi

# 1) Create user with home directory and bash shell
useradd -m -s /bin/bash "$USERNAME"
echo "User '$USERNAME' created with home directory."

# 2) Set the user's password
echo "Set password for user '$USERNAME':"
passwd "$USERNAME"

# 3) Add user to sudo group
usermod -aG sudo "$USERNAME"
echo "User '$USERNAME' added to 'sudo' group."

# 4) Verify group membership
echo "Verifying user groups:"
id "$USERNAME"

# 5) Test sudo rights
echo "Testing sudo privileges for '$USERNAME'..."
su - "$USERNAME" -c "sudo whoami"

echo "✅ User '$USERNAME' successfully created with sudo privileges."
