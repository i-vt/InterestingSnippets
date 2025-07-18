#!/bin/bash

# Automate RDP setup using xrdp and Xfce on Debian/Ubuntu
# Ensure script is run as root
if [ "$EUID" -ne 0 ]; then
  echo "Please run this script as root (e.g., sudo ./setup-xrdp.sh)"
  exit 1
fi

echo "[+] Updating packages..."
apt update && apt upgrade -y

echo "[+] Installing Xfce desktop environment..."
apt install xfce4 xfce4-goodies -y

echo "[+] Installing xrdp..."
apt install xrdp -y

echo "[+] Enabling universe repo (required for some Ubuntu variants)..."
add-apt-repository universe -y
apt update

echo "[+] Adding xrdp user to ssl-cert group..."
adduser xrdp ssl-cert

# Create a group for RDP users
echo "[+] Creating 'rdpusers' group if it doesn't exist..."
getent group rdpusers > /dev/null || groupadd rdpusers

# Determine the non-root user (works even when run with sudo)
USERNAME=${SUDO_USER:-$(logname)}

echo "[+] Adding user '$USERNAME' to 'rdpusers' group..."
usermod -aG rdpusers "$USERNAME"

# Set up xsession for the user
echo "[+] Setting xfce4-session for xrdp session..."
echo "xfce4-session" > "/home/$USERNAME/.xsession"
chown "$USERNAME:rdpusers" "/home/$USERNAME/.xsession"
chmod 640 "/home/$USERNAME/.xsession"

# Make home dir group-accessible (optional, can be skipped if sensitive)
chmod g+rx "/home/$USERNAME"

echo "[+] Restarting xrdp service..."
systemctl restart xrdp

echo "[+] Enabling xrdp to start on boot..."
systemctl enable xrdp

echo "[+] Allowing RDP port 3389 from your IP only..."
IP=$(curl -s ifconfig.me)
ufw allow from "$IP/32" to any port 3389
ufw allow OpenSSH
ufw --force enable

echo "[+] Setup complete!"
echo "Use an RDP client to connect to: $IP (port 3389)"
echo "Login with your Linux username and password (make sure the user is in the 'rdpusers' group)."
echo "Example: sudo usermod -aG rdpusers anotherus3r123"
