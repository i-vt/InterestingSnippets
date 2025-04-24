#!/usr/bin/env bash
export DEBIAN_FRONTEND=noninteractive
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

# Display the current IP address
echo "-------[Current IP]-------"
curl https://api.ipify.org/ || { echo 'Failed to fetch IP address'; exit 1; }
echo ""

# Shortcuts
echo "alias s2020='python3 -m http.server 2020'" >> ~/.bashrc
echo "alias s2021='python3 -m http.server 2021'" >> ~/.bashrc
echo "alias s2022='python3 -m http.server 2022'" >> ~/.bashrc

# Basic system info
echo "-------[System Info]-------"
uname -a
lsb_release -a

