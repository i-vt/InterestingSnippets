#!/usr/bin/env bash

# Check if /etc/resolv.conf already has 8.8.8.8 or 1.1.1.1
if ! grep -qE 'nameserver (8\.8\.8\.8|1\.1\.1\.1)' /etc/resolv.conf; then
  echo "Neither 8.8.8.8 nor 1.1.1.1 found. Adding 8.8.8.8..."
  echo "nameserver 8.8.8.8" | sudo tee -a /etc/resolv.conf > /dev/null
else
  echo "Nameserver already set correctly."
fi

# Check if sudo is installed
if command -v sudo >/dev/null 2>&1; then
  echo "sudo is already installed."
else
  echo "sudo is NOT installed. Attempting to install..."

  # Install sudo using dnf
  dnf install -y sudo

  # Verify installation
  if command -v sudo >/dev/null 2>&1; then
    echo "sudo installed successfully."
  else
    echo "Failed to install sudo."
    exit 2
  fi
fi

# Update and upgrade the system packages
sudo dnf update -y || { echo 'Failed to update packages'; exit 1; }

# Install necessary packages (mapped for DNF-based systems)
sudo dnf install -y zip curl tree python3 python3-pip mlocate tmux git htop uuid-devel \
  @development-tools net-tools ffmpeg wget || { echo 'Failed to install packages'; exit 1; }

# Enable locate database
sudo updatedb

# Clean old kernels (leave the latest 2, safer default)
sudo dnf remove -y $(dnf repoquery --installonly --latest-limit=-2 -q) || echo "No old kernels to remove"

# Cleanup
sudo dnf autoremove -y
sudo dnf clean all

# Download and save the .vimrc file to the home directory
wget https://raw.githubusercontent.com/i-vt/InterestingSnippets/refs/heads/main/Linux/.vimrc --output-document=$HOME/.vimrc || { echo 'Failed to download .vimrc'; exit 1; }

# Define aliases to add
ALIASES=(
  "alias s2020='python3 -m http.server 2020'"
  "alias s2021='python3 -m http.server 2021'"
  "alias s2022='python3 -m http.server 2022'"
)

# File to modify
BASHRC="$HOME/.bashrc"

# Add comment if not already present
if ! grep -q "# Shortcuts" "$BASHRC"; then
  echo -e "\n# Shortcuts" >> "$BASHRC"
fi

# Add aliases if not already defined
for ALIAS in "${ALIASES[@]}"; do
  if ! grep -Fq "$ALIAS" "$BASHRC"; then
    echo "$ALIAS" >> "$BASHRC"
  fi
done

# Source the updated file
source "$BASHRC"

# Display the current IP address
echo "-------[Current IP]-------"
curl https://api.ipify.org/ || { echo 'Failed to fetch IP address'; exit 1; }
echo ""

# Basic system info
echo "-------[System Info]-------"
uname -a
cat /etc/os-release