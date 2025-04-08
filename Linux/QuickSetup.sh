#!/usr/bin/env bash
export DEBIAN_FRONTEND=noninteractive
# Update and upgrade the system packages non-interactively
sudo apt update -y && sudo apt upgrade -y || { echo 'Failed to update and upgrade packages'; exit 1; }

# Install necessary packages
sudo apt install -y curl tree python3-pip plocate snapd python3-venv tmux || { echo 'Failed to install packages'; exit 1; }

# Download and save the .vimrc file to the home directory
wget https://raw.githubusercontent.com/i-vt/InterestingSnippets/refs/heads/main/Linux/.vimrc --output-document=$HOME/.vimrc || { echo 'Failed to download .vimrc'; exit 1; }

# Display the current IP address
echo "-------[current ip]-------"
curl https://api.ipify.org/ || { echo 'Failed to fetch IP address'; exit 1; }
echo ""
