#!/bin/bash

echo "Listing all apps using each port..."
echo "-----------------------------------"

# Check if lsof is available
if command -v lsof >/dev/null 2>&1; then
    sudo lsof -i -P -n | grep LISTEN
else
    # fallback to ss if lsof isn't available
    sudo ss -tulpn
fi
