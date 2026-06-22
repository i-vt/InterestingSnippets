#!/usr/bin/env bash
set -euo pipefail

# ─── Logging ───────────────────────────────────────────────────────────────────
exec > >(tee -a "$HOME/setup.log") 2>&1
echo "====== Setup started: $(date) ======"

export DEBIAN_FRONTEND=noninteractive

# ─── OS Check ──────────────────────────────────────────────────────────────────
if ! command -v apt-get &>/dev/null; then
  echo "ERROR: This script requires a Debian/Ubuntu-based system (apt-get not found)."
  exit 1
fi

# ─── Root / Sudo Check ─────────────────────────────────────────────────────────
if [[ $EUID -ne 0 ]] && ! sudo -n true 2>/dev/null; then
  echo "ERROR: This script requires root or passwordless sudo access."
  exit 1
fi

# ─── DNS Fix ───────────────────────────────────────────────────────────────────
if ! grep -qE 'nameserver (8\.8\.8\.8|1\.1\.1\.1)' /etc/resolv.conf; then
  echo "Neither 8.8.8.8 nor 1.1.1.1 found. Adding 8.8.8.8..."
  echo "nameserver 8.8.8.8" | sudo tee -a /etc/resolv.conf > /dev/null
else
  echo "Nameserver already set correctly."
fi

# ─── Internet Connectivity Check ───────────────────────────────────────────────
echo "Checking internet connectivity..."
if ! curl -fsS --max-time 10 https://api.ipify.org/ > /dev/null; then
  echo "ERROR: No internet access. Please check your network connection and DNS."
  exit 1
fi
echo "Internet connectivity confirmed."

# ─── Install sudo if missing ───────────────────────────────────────────────────
if command -v sudo >/dev/null 2>&1; then
  echo "sudo is already installed."
else
  echo "sudo is NOT installed. Attempting to install..."
  apt-get update
  apt-get install -y sudo
  if command -v sudo >/dev/null 2>&1; then
    echo "sudo installed successfully."
  else
    echo "ERROR: Failed to install sudo."
    exit 1
  fi
fi

# ─── System Update & Upgrade ───────────────────────────────────────────────────
echo "Updating and upgrading system packages..."
sudo apt update -y && sudo apt upgrade -y \
  || { echo "ERROR: Failed to update/upgrade packages."; exit 1; }

# ─── Install Packages ──────────────────────────────────────────────────────────
echo "Installing required packages..."
sudo apt install -y \
  zip curl tree python3-full python3-pip plocate snapd \
  python3-venv tmux git-all htop uuid-runtime build-essential \
  net-tools ffmpeg rsync \
  || { echo "ERROR: Failed to install packages."; exit 1; }

# ─── Update File Index ─────────────────────────────────────────────────────────
echo "Updating file index (updatedb)..."
sudo updatedb

# ─── Snap ──────────────────────────────────────────────────────────────────────
echo "Refreshing snaps..."
sudo snap refresh

# ─── Fail2ban ──────────────────────────────────────────────────────────────────
# Uses the dedicated install script which configures jail.local, an aggressive
# SSH filter, and drops the f2b-manage helper at /usr/local/bin/f2b-manage.
echo "Installing and configuring fail2ban..."
F2B_SCRIPT="$(mktemp /tmp/install_fail2ban_XXXXXX.sh)"
curl -fsSL \
  https://raw.githubusercontent.com/i-vt/InterestingSnippets/refs/heads/main/Linux/InstallFail2BanForSSH.sh \
  -o "$F2B_SCRIPT" \
  || { echo "ERROR: Failed to download fail2ban install script."; exit 1; }
chmod +x "$F2B_SCRIPT"
sudo bash "$F2B_SCRIPT" || { echo "ERROR: fail2ban install script failed."; rm -f "$F2B_SCRIPT"; exit 1; }
rm -f "$F2B_SCRIPT"
echo "fail2ban configured. Use 'f2b-manage status' to check it."

# ─── Cleanup ───────────────────────────────────────────────────────────────────
echo "Cleaning up old kernels and packages..."
sudo dpkg -l 'linux-image-*' \
  | awk '/^ii/{ print $2 }' \
  | grep -v "$(uname -r)" \
  | grep -E 'linux-image-[0-9]+' \
  | sort | head -n -1 \
  | xargs --no-run-if-empty sudo apt -y purge
sudo apt autoremove -y
sudo apt clean

# ─── Directory Setup ───────────────────────────────────────────────────────────
echo "Creating standard directories..."
mkdir -p ~/Desktop ~/Downloads ~/Documents ~/Music ~/Pictures ~/Videos ~/Trash

# ─── Clone Repo ────────────────────────────────────────────────────────────────
CLONE_DIR="$HOME/Documents/InterestingSnippets-main"
if [ -d "$CLONE_DIR/.git" ]; then
  echo "Repo already cloned. Pulling latest changes..."
  git -C "$CLONE_DIR" pull
else
  echo "Cloning InterestingSnippets repo..."
  git clone https://github.com/i-vt/InterestingSnippets.git "$CLONE_DIR"
fi

# ─── Dotfiles ──────────────────────────────────────────────────────────────────
DOTFILES_DIR="$CLONE_DIR/Linux"

echo "Copying .vimrc from repo..."
cat "$DOTFILES_DIR/.vimrc" > "$HOME/.vimrc" \
  || { echo "ERROR: Failed to copy .vimrc."; exit 1; }

echo "Copying .bashrc from repo..."
cat "$DOTFILES_DIR/.bashrc" > "$HOME/.bashrc" \
  || { echo "ERROR: Failed to copy .bashrc."; exit 1; }

# ─── Bash Aliases ──────────────────────────────────────────────────────────────
# Append custom aliases to ~/.bash_aliases (kept separate from ~/.bashrc).
# Ensure ~/.bashrc sources ~/.bash_aliases after the copy above.
BASH_ALIASES="$HOME/.bash_aliases"
BASHRC="$HOME/.bashrc"

if ! grep -q '.bash_aliases' "$BASHRC"; then
  cat >> "$BASHRC" <<'EOF'

# Source aliases
if [ -f ~/.bash_aliases ]; then
  . ~/.bash_aliases
fi
EOF
fi

ALIASES=(
  "alias s2020='python3 -m http.server 2020'"
  "alias s2021='python3 -m http.server 2021'"
  "alias s2022='python3 -m http.server 2022'"
  "alias uploadserver='cd ~/Documents/InterestingSnippets-main/Python/uploadserver/ && python3 ~/Documents/InterestingSnippets-main/Python/uploadserver/uploadserver.py'"
)

if ! grep -q "# Shortcuts" "$BASH_ALIASES" 2>/dev/null; then
  echo -e "\n# Shortcuts" >> "$BASH_ALIASES"
fi

for ALIAS in "${ALIASES[@]}"; do
  if ! grep -Fq "$ALIAS" "$BASH_ALIASES" 2>/dev/null; then
    echo "$ALIAS" >> "$BASH_ALIASES"
  fi
done

# ─── Git Global Config ─────────────────────────────────────────────────────────
# Uncomment and fill in to configure git identity:
# git config --global user.name  "Your Name"
# git config --global user.email "you@example.com"
# git config --global init.defaultBranch main

# ─── SSH Key ───────────────────────────────────────────────────────────────────
SSH_KEY="$HOME/.ssh/id_ed25519"
if [ ! -f "$SSH_KEY" ]; then
  echo "Generating SSH key (ed25519)..."
  mkdir -p "$HOME/.ssh"
  chmod 700 "$HOME/.ssh"
  ssh-keygen -t ed25519 -N "" -f "$SSH_KEY"
  echo ""
  echo "SSH public key (add this to GitHub/GitLab/authorized_keys as needed):"
  cat "${SSH_KEY}.pub"
else
  echo "SSH key already exists: $SSH_KEY"
fi

# ─── Timezone ──────────────────────────────────────────────────────────────────
echo "Setting timezone to UTC..."
sudo timedatectl set-timezone UTC

# ─── Reload Shell Config ───────────────────────────────────────────────────────
# shellcheck disable=SC1090
source "$HOME/.bashrc" || true

# ─── System Info ───────────────────────────────────────────────────────────────
echo ""
echo "-------[Current IP]-------"
curl -fsS https://api.ipify.org/ || { echo "ERROR: Failed to fetch IP address."; exit 1; }
echo ""

echo ""
echo "-------[System Info]-------"
uname -a
lsb_release -a

echo ""
echo "====== Setup completed: $(date) ======"
echo "Log saved to: $HOME/setup.log"
echo "NOTE: Open a new shell session (or run 'source ~/.bashrc') for aliases to take effect."
