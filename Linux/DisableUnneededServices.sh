#!/usr/bin/env bash
# =============================================
# Disable and remove non-essential services:
# CUPS (printing), Avahi (mDNS), and Bluetooth
# Tested on Debian 12/13 (Bookworm/Trixie)
# =============================================

set -euo pipefail

echo "=== Disabling non-essential services (CUPS, Avahi, Bluetooth) ==="

# Ensure we’re running as root
if [[ $EUID -ne 0 ]]; then
    echo "Please run this script as root or with sudo."
    exit 1
fi

disable_service() {
    local svc=$1
    if systemctl list-unit-files | grep -q "^${svc}"; then
        echo "Stopping and disabling ${svc}..."
        systemctl stop "${svc}" 2>/dev/null || true
        systemctl disable "${svc}" 2>/dev/null || true
        systemctl mask "${svc}" 2>/dev/null || true
    else
        echo "Service ${svc} not found, skipping."
    fi
}

# --- Disable CUPS services ---
echo "--- Disabling CUPS services ---"
disable_service cups.service
disable_service cups-browsed.service
disable_service cups.socket

# --- Disable Avahi services ---
echo "--- Disabling Avahi services ---"
disable_service avahi-daemon.service
disable_service avahi-daemon.socket

# --- Disable Bluetooth service ---
echo "--- Disabling Bluetooth service ---"
disable_service bluetooth.service

# --- Optional Package Removal ---
read -rp "Do you want to purge related packages as well? (y/N): " answer
if [[ "$answer" =~ ^[Yy]$ ]]; then
    echo "Purging packages..."
    apt purge -y cups* avahi-daemon avahi-utils libnss-mdns bluez blueman || true
    apt autoremove --purge -y
    apt clean
else
    echo "Skipping package removal."
fi

echo "=== Verifying service status ==="
systemctl --no-pager --type=service | egrep 'cups|avahi|bluetooth' || echo "All target services disabled."

echo "✅ Done. CUPS, Avahi, and Bluetooth are now disabled."
