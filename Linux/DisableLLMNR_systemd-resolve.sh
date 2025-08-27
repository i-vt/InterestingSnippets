#!/bin/bash
# disable-llmnr.sh
# This script disables LLMNR (port 5355) on systems using systemd-resolved.
# systemd-r 1181 systemd-resolve   12u  IPv4  24091      0t0  TCP *:5355 (LISTEN)
# systemd-r 1181 systemd-resolve   14u  IPv6  24099      0t0  TCP *:5355 (LISTEN)
set -e

CONF_FILE="/etc/systemd/resolved.conf"

echo "Disabling LLMNR in $CONF_FILE ..."

# Ensure section [Resolve] exists
if ! grep -q "^\[Resolve\]" "$CONF_FILE"; then
    echo "[Resolve]" | sudo tee -a "$CONF_FILE" >/dev/null
fi

# If LLMNR= line exists, change it; otherwise, add it
if grep -q "^LLMNR=" "$CONF_FILE"; then
    sudo sed -i 's/^LLMNR=.*/LLMNR=no/' "$CONF_FILE"
else
    sudo sed -i '/^\[Resolve\]/a LLMNR=no' "$CONF_FILE"
fi

echo "Restarting systemd-resolved..."
sudo systemctl restart systemd-resolved

echo "Checking status..."
resolvectl status | grep LLMNR

echo "Done. LLMNR should now be disabled."
