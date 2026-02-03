#!/bin/bash

# Define colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${YELLOW}Starting NVIDIA Driver Auto-Installer...${NC}"

# 1. CHECK FOR ROOT PRIVILEGES
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}Error: This script must be run as root.${NC}"
   echo "Please run with: sudo ./install_nvidia.sh"
   exit 1
fi

# 2. CHECK SYSTEM ARCHITECTURE
# The command you requested uses 'linux-headers-amd64'. We must verify this is an x86_64 system.
ARCH=$(dpkg --print-architecture)
if [[ "$ARCH" != "amd64" ]]; then
    echo -e "${RED}Error: System architecture is '$ARCH', but script targets 'amd64'.${NC}"
    exit 1
fi

# 3. CHECK FOR NVIDIA HARDWARE
echo "Checking for NVIDIA hardware..."
if lspci -nn | grep -iE 'VGA|3D' | grep -i "nvidia" > /dev/null; then
    echo -e "${GREEN}NVIDIA GPU detected.${NC}"
else
    echo -e "${RED}No NVIDIA GPU found on this system.${NC}"
    echo "Aborting installation to prevent system issues."
    exit 0
fi

# 4. MODIFY SOURCES LIST (Idempotent Check)
# We check if 'contrib non-free' is already present to avoid duplicating entries if script is run twice.
TARGET_FILE="/etc/apt/sources.list"

if grep -q "non-free-firmware contrib non-free" "$TARGET_FILE"; then
    echo -e "${GREEN}Repositories already configured. Skipping sed command.${NC}"
else
    echo "Backing up sources list to /etc/apt/sources.list.bak..."
    cp "$TARGET_FILE" "$TARGET_FILE.bak"
    
    echo "Adding 'contrib' and 'non-free' components..."
    # Your specific sed command
    sed -i 's/non-free-firmware/non-free-firmware contrib non-free/g' "$TARGET_FILE"
fi

# 5. UPDATE APT
echo "Updating package lists..."
apt update

# 6. INSTALL PACKAGES
# Installing headers, driver, and firmware as requested
echo "Installing NVIDIA drivers and headers..."
apt install -y linux-headers-amd64 nvidia-driver firmware-misc-nonfree

# 7. FINISH
if [ $? -eq 0 ]; then
    echo -e "${GREEN}Installation complete!${NC}"
    echo -e "${YELLOW}You must reboot your computer for the drivers to take effect.${NC}"
    read -p "Would you like to reboot now? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        reboot
    fi
else
    echo -e "${RED}Installation encountered an error. Please check the logs above.${NC}"
fi
