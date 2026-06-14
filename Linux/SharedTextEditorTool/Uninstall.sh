#!/usr/bin/env bash
set -e

APP_NAME="shared-text-editor"
APP_DIR="/opt/$APP_NAME"
SERVICE_FILE="/etc/systemd/system/$APP_NAME.service"

echo "=============================="
echo "Uninstalling $APP_NAME"
echo "=============================="

# ── Stop & disable the service ─────────────────────────────────────────────
echo "=============================="
echo "Stopping service"
echo "=============================="
if systemctl is-active --quiet "$APP_NAME" 2>/dev/null; then
    sudo systemctl stop "$APP_NAME"
    echo "Service stopped."
else
    echo "Service was not running — skipping stop."
fi

echo "=============================="
echo "Disabling service"
echo "=============================="
if systemctl is-enabled --quiet "$APP_NAME" 2>/dev/null; then
    sudo systemctl disable "$APP_NAME"
    echo "Service disabled."
else
    echo "Service was not enabled — skipping disable."
fi

# ── Remove the systemd unit file ───────────────────────────────────────────
echo "=============================="
echo "Removing systemd service file"
echo "=============================="
if [ -f "$SERVICE_FILE" ]; then
    sudo rm -f "$SERVICE_FILE"
    echo "Removed $SERVICE_FILE"
else
    echo "Service file not found — skipping."
fi

# ── Reload systemd so the unit disappears ──────────────────────────────────
echo "=============================="
echo "Reloading systemd"
echo "=============================="
sudo systemctl daemon-reload
sudo systemctl reset-failed 2>/dev/null || true
echo "systemd reloaded."

# ── Remove the application directory ──────────────────────────────────────
echo "=============================="
echo "Removing application directory"
echo "=============================="
if [ -d "$APP_DIR" ]; then
    sudo rm -rf "$APP_DIR"
    echo "Removed $APP_DIR"
else
    echo "Application directory not found — skipping."
fi

# ── Optional: remove system packages ──────────────────────────────────────
echo "=============================="
echo "System package cleanup"
echo "=============================="
cat <<'MSG'
The installer added: curl, git, npm, nodejs

These are general-purpose tools that may be used by other software on
this system, so they are NOT removed automatically.

To remove them manually, run:
  sudo apt remove --purge nodejs npm
  sudo apt autoremove
MSG

# ── Done ───────────────────────────────────────────────────────────────────
echo "=============================="
echo "Uninstall complete"
echo "=============================="
echo "$APP_NAME has been fully removed."
