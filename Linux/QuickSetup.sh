#!/usr/bin/env bash
export DEBIAN_FRONTEND=noninteractive


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
sudo apt install -y curl tree python3-pip plocate snapd python3-venv tmux git-all || { echo 'Failed to install packages'; exit 1; }

sudo snap refresh 


# Clean up
sudo apt autoremove -y
sudo apt clean

# Download and save the .vimrc file to the home directory
wget https://raw.githubusercontent.com/i-vt/InterestingSnippets/refs/heads/main/Linux/.vimrc --output-document=$HOME/.vimrc || { echo 'Failed to download .vimrc'; exit 1; }

# Check if /etc/resolv.conf already has 8.8.8.8 or 1.1.1.1
if ! grep -qE 'nameserver (8\.8\.8\.8|1\.1\.1\.1)' /etc/resolv.conf; then
  echo "Neither 8.8.8.8 nor 1.1.1.1 found. Adding 8.8.8.8..."
  echo "nameserver 8.8.8.8" | sudo tee -a /etc/resolv.conf > /dev/null
else
  echo "Nameserver already set correctly."
fi

# Shortcuts
echo "alias s2020='python3 -m http.server 2020'" >> ~/.bashrc
echo "alias s2021='python3 -m http.server 2021'" >> ~/.bashrc
echo "alias s2022='python3 -m http.server 2022'" >> ~/.bashrc
source ~/.bashrc

# Display the current IP address
echo "-------[Current IP]-------"
curl https://api.ipify.org/ || { echo 'Failed to fetch IP address'; exit 1; }
echo ""

# Basic system info
echo "-------[System Info]-------"
uname -a
lsb_release -a

