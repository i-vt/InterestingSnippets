#!/usr/bin/env bash
export DEBIAN_FRONTEND=noninteractive

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

  # Install sudo using apt
  apt-get update
  apt-get install -y sudo

  # Verify installation
  if command -v sudo >/dev/null 2>&1; then
    echo "sudo installed successfully."
  else
    echo "Failed to install sudo."
    exit 2
  fi
fi




# Update and upgrade the system packages non-interactively
sudo apt update -y && sudo apt upgrade -y || { echo 'Failed to update and upgrade packages'; exit 1; }



# Install necessary packages
sudo apt install -y zip curl tree python3-full python3-pip plocate snapd python3-venv tmux git-all htop uuid-runtime build-essential || { echo 'Failed to install packages'; exit 1; }

sudo snap refresh 


# Clean up
sudo dpkg -l 'linux-image-*' | \
  awk '/^ii/{ print $2 }' | \
  grep -v $(uname -r) | \
  grep -E 'linux-image-[0-9]+' | \
  sort | head -n -1 | \
  xargs sudo apt -y purge
sudo apt autoremove -y
sudo apt clean

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
lsb_release -a

