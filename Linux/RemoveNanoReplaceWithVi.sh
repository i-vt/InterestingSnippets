#!/bin/bash

# Script to remove nano and redirect all nano usage to vi (assuming vi is already installed)

set -e

echo "Removing nano..."
if command -v apt-get >/dev/null 2>&1; then
    sudo apt-get remove --purge -y nano
    sudo apt-get autoremove -y
elif command -v yum >/dev/null 2>&1; then
    sudo yum remove -y nano
elif command -v dnf >/dev/null 2>&1; then
    sudo dnf remove -y nano
elif command -v pacman >/dev/null 2>&1; then
    sudo pacman -Rns --noconfirm nano
else
    echo "Package manager not supported. Please remove nano manually."
    exit 1
fi

echo "Creating symlink so nano redirects to vi..."
if [ -x /usr/bin/vi ]; then
    sudo ln -sf /usr/bin/vi /usr/bin/nano
else
    echo "Error: /usr/bin/vi not found. Please make sure vi is installed."
    exit 1
fi

echo "Setting vi as the default editor..."
if command -v update-alternatives >/dev/null 2>&1; then
    sudo update-alternatives --set editor /usr/bin/vi || \
    sudo update-alternatives --install /usr/bin/editor editor /usr/bin/vi 100
fi

echo "Done! Any call to 'nano' will now launch 'vi'."
