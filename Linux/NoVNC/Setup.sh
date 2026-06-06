#!/usr/bin/env bash

# Complete VNC/noVNC Installer for Clean Debian OS - REBOOT-SAFE VERSION
# This script installs and configures VNC with noVNC web interface from scratch
# Compatible with Debian 11/12 and Ubuntu 20.04/22.04/24.04
# KEY FIXES vs previous version:
#   - Uses Xvnc directly (no vncserver wrapper) so systemd Type=simple works correctly
#   - Display number PINNED to :2 / port 5902 (no dynamic allocation that breaks on reboot)
#   - ExecStartPost launches xstartup session separately so Xvnc process stays as PID 1
#   - noVNC uses /usr/bin/websockify directly (more reliable than novnc_proxy wrapper)
#   - Proper ExecStop uses kill on the lock file PID instead of vncserver -kill
#   - Services use StandardOutput/StandardError for better journalctl visibility

set -euo pipefail

# ─── Colors ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# ─── Configuration (override via env vars) ─────────────────────────────────────
TARGET_USER="${TARGET_USER:-vncuser}"
VNC_PASSWORD="${VNC_PASSWORD:-}"
WEB_PORT="${WEB_PORT:-6080}"
VNC_GEOMETRY="${VNC_GEOMETRY:-1280x800}"
DESKTOP_ENV="${DESKTOP_ENV:-minimal}"   # minimal | xfce4 | lxde | mate

# ─── PINNED values (stable across reboots) ────────────────────────────────────
DISPLAY_NUM=2
VNC_PORT=5902

# ─── Derived (set after user creation) ────────────────────────────────────────
USER_HOME=""

# ─── Helpers ───────────────────────────────────────────────────────────────────
print_status()  { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error()   { echo -e "${RED}[ERROR]${NC} $1"; }

# ──────────────────────────────────────────────────────────────────────────────
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root (use sudo)"
        exit 1
    fi
}

# ──────────────────────────────────────────────────────────────────────────────
detect_os() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS=${ID:-unknown}
        OS_VERSION=${VERSION_ID:-unknown}
    else
        print_error "Cannot detect OS. This script requires Debian or Ubuntu."
        exit 1
    fi
    print_status "Detected OS: $OS $OS_VERSION"
    if [[ "$OS" != "debian" && "$OS" != "ubuntu" ]]; then
        print_error "This script only supports Debian and Ubuntu"
        exit 1
    fi
}

# ──────────────────────────────────────────────────────────────────────────────
fix_hostname_resolution() {
    print_status "Checking hostname resolution..."
    local current_hostname
    current_hostname=$(hostname)
    if ! ping -c 1 "$current_hostname" &>/dev/null; then
        print_warning "Hostname '$current_hostname' not resolvable. Fixing /etc/hosts..."
        echo "127.0.0.1 $current_hostname" >> /etc/hosts
        print_success "Hostname resolution fixed."
    else
        print_success "Hostname resolves correctly."
    fi
}

# ──────────────────────────────────────────────────────────────────────────────
create_vncuser() {
    print_status "Creating vncuser account..."

    if id "$TARGET_USER" &>/dev/null; then
        print_warning "User '$TARGET_USER' already exists"
        USER_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
        print_status "Using existing home directory: $USER_HOME"
    else
        if ! command -v uuidgen &>/dev/null; then
            print_status "Installing uuid-runtime..."
            apt-get update -qq
            apt-get install -y uuid-runtime
        fi

        SYSTEM_PASSWORD=$(uuidgen | head -c 8)
        useradd -m -s /bin/bash "$TARGET_USER"
        echo "$TARGET_USER:$SYSTEM_PASSWORD" | chpasswd
        USER_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"

        print_success "User '$TARGET_USER' created"
        echo "$SYSTEM_PASSWORD" > /root/vncuser_system_password.txt
        chmod 600 /root/vncuser_system_password.txt
        print_status "System password saved to: /root/vncuser_system_password.txt"
    fi

    if [[ ! -d "$USER_HOME" ]]; then
        print_error "Home directory '$USER_HOME' does not exist"
        exit 1
    fi

    print_status "Target user: $TARGET_USER  |  Home: $USER_HOME"
}

# ──────────────────────────────────────────────────────────────────────────────
update_system() {
    print_status "Updating system packages..."
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    apt-get upgrade -y -qq
    print_success "System updated"
}

# ──────────────────────────────────────────────────────────────────────────────
install_base_packages() {
    print_status "Installing base packages..."
    apt-get install -y \
        curl wget gnupg2 apt-transport-https ca-certificates \
        lsb-release systemd dbus dbus-x11 uuid-runtime
    print_success "Base packages installed"
}

# ──────────────────────────────────────────────────────────────────────────────
install_vnc_packages() {
    print_status "Installing VNC packages..."
    apt-get install -y \
        tigervnc-standalone-server tigervnc-common \
        tigervnc-tools tigervnc-viewer \
        novnc python3-websockify websockify
    print_success "VNC packages installed"
}

# ──────────────────────────────────────────────────────────────────────────────
install_x11_packages() {
    print_status "Installing X11 packages..."
    apt-get install -y \
        xorg xserver-xorg-core \
        xfonts-base xfonts-75dpi xfonts-100dpi xfonts-scalable \
        x11-apps x11-utils x11-xserver-utils xterm
    print_success "X11 packages installed"
}

# ──────────────────────────────────────────────────────────────────────────────
install_desktop_environment() {
    print_status "Installing desktop environment: $DESKTOP_ENV"
    case "$DESKTOP_ENV" in
        xfce4)   apt-get install -y xfce4 xfce4-goodies xfce4-terminal ;;
        lxde)    apt-get install -y lxde-core lxde-common lxterminal ;;
        mate)    apt-get install -y mate-desktop-environment-core mate-terminal ;;
        minimal) apt-get install -y fluxbox openbox twm fvwm ;;
        *)
            print_warning "Unknown '$DESKTOP_ENV', falling back to minimal"
            apt-get install -y fluxbox openbox twm fvwm
            DESKTOP_ENV="minimal"
            ;;
    esac
    print_success "Desktop environment installed: $DESKTOP_ENV"
}

# ──────────────────────────────────────────────────────────────────────────────
install_additional_packages() {
    print_status "Installing additional packages..."
    local pkgs=(firefox-esr gedit thunar nano vim htop net-tools sudo pcmanfm mousepad)
    for pkg in "${pkgs[@]}"; do
        if apt-cache show "$pkg" &>/dev/null; then
            apt-get install -y "$pkg" || print_warning "Failed to install $pkg"
        else
            print_warning "Package $pkg not available, skipping"
        fi
    done
    print_success "Additional packages installed"
}

# ──────────────────────────────────────────────────────────────────────────────
prepare_vnc_dirs() {
    print_status "Preparing VNC config directories..."

    sudo -u "$TARGET_USER" mkdir -p \
        "$USER_HOME/.config/tigervnc" \
        "$USER_HOME/.vnc"

    chown -R "$TARGET_USER:$TARGET_USER" \
        "$USER_HOME/.vnc" \
        "$USER_HOME/.config/tigervnc"

    chmod 700 \
        "$USER_HOME/.vnc" \
        "$USER_HOME/.config/tigervnc"

    print_success "VNC directories ready"
}

# ──────────────────────────────────────────────────────────────────────────────
setup_vnc_password() {
    print_status "Setting up VNC password..."
    prepare_vnc_dirs

    if [[ -z "$VNC_PASSWORD" ]]; then
        VNC_PASSWORD=$(uuidgen | head -c 8)
        print_status "Auto-generated VNC password: $VNC_PASSWORD"
        echo "$VNC_PASSWORD" > /root/vncuser_vnc_password.txt
        chmod 600 /root/vncuser_vnc_password.txt
        print_status "VNC password saved to: /root/vncuser_vnc_password.txt"
    fi

    local passwd_hash
    passwd_hash=$(printf '%s\n' "$VNC_PASSWORD" | vncpasswd -f)

    # Write to both locations
    for dest in \
        "$USER_HOME/.config/tigervnc/passwd" \
        "$USER_HOME/.vnc/passwd"
    do
        printf '%s' "$passwd_hash" > "$dest"
        chmod 600 "$dest"
        chown "$TARGET_USER:$TARGET_USER" "$dest"
    done

    print_success "VNC password configured"
}

# ──────────────────────────────────────────────────────────────────────────────
create_xstartup_script() {
    print_status "Creating xstartup script..."

    local xstartup="$USER_HOME/.config/tigervnc/xstartup"

    cat > "$xstartup" <<'XSTARTUP_EOF'
#!/bin/bash
# VNC xstartup — launched by ExecStartPost in vnc-backend.service

LOG_FILE="$HOME/.vnc/startup.log"
exec > >(while IFS= read -r line; do
    echo "$(date '+%Y-%m-%d %H:%M:%S'): $line"
done >> "$LOG_FILE") 2>&1

echo "=== xstartup BEGIN ==="
echo "USER=$USER  HOME=$HOME  DISPLAY=$DISPLAY"

# ── Sanitise environment ──────────────────────────────────────────────────────
unset SESSION_MANAGER DBUS_SESSION_BUS_ADDRESS \
      XDG_SESSION_PATH XDG_SESSION_ID XDG_SESSION_COOKIE

export USER="${USER:-$(whoami)}"
export HOME="${HOME:-$(getent passwd "$USER" | cut -d: -f6)}"
export SHELL="${SHELL:-/bin/bash}"
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
export LANG="${LANG:-en_US.UTF-8}"
export LC_ALL="${LC_ALL:-en_US.UTF-8}"

# ── .Xauthority ───────────────────────────────────────────────────────────────
[[ -f "$HOME/.Xauthority" ]] || { touch "$HOME/.Xauthority"; chmod 600 "$HOME/.Xauthority"; }

# ── D-Bus ─────────────────────────────────────────────────────────────────────
if [[ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ]] && command -v dbus-launch &>/dev/null; then
    eval "$(dbus-launch --sh-syntax)"
    export DBUS_SESSION_BUS_ADDRESS
    echo "D-Bus started: $DBUS_SESSION_BUS_ADDRESS"
fi

# ── Basic X11 ─────────────────────────────────────────────────────────────────
xrdb "$HOME/.Xresources" 2>/dev/null || true
xsetroot -solid "#2E3440" 2>/dev/null || true

# ── Window manager launcher ───────────────────────────────────────────────────
start_wm() {
    local cmd="$1" name="$2"
    if command -v "$cmd" &>/dev/null; then
        echo "Starting $name..."
        "$cmd" &
        WM_PID=$!
        sleep 2
        if kill -0 "$WM_PID" 2>/dev/null; then
            echo "$name running (PID $WM_PID)"
            return 0
        fi
        echo "$name exited immediately"
    else
        echo "$name not found"
    fi
    return 1
}

# ── Start desktop / WM ───────────────────────────────────────────────────────
WM_PID=""

if [[ "${DESKTOP_ENV:-minimal}" == "xfce4" ]] && command -v startxfce4 &>/dev/null; then
    startxfce4 &
    WM_PID=$!
    sleep 5
    kill -0 "$WM_PID" 2>/dev/null || { echo "XFCE4 crashed, falling back"; WM_PID=""; }
fi

if [[ -z "$WM_PID" ]]; then
    start_wm openbox Openbox  ||
    start_wm fluxbox Fluxbox  ||
    start_wm fvwm    FVWM     ||
    start_wm twm     TWM      || {
        echo "FATAL: no window manager available"
        exit 1
    }
fi

sleep 2

# ── Applications ─────────────────────────────────────────────────────────────
command -v xterm         &>/dev/null && xterm -geometry 80x30+50+50 &
command -v thunar        &>/dev/null && thunar   &  || \
command -v pcmanfm       &>/dev/null && pcmanfm  &  || true
command -v mousepad      &>/dev/null && mousepad &  || \
command -v gedit         &>/dev/null && gedit    &  || true

# ── Openbox right-click menu ──────────────────────────────────────────────────
if command -v openbox &>/dev/null && pgrep -x openbox &>/dev/null; then
    mkdir -p "$HOME/.config/openbox"
    cat > "$HOME/.config/openbox/menu.xml" <<'MENU_EOF'
<?xml version="1.0" encoding="UTF-8"?>
<openbox_menu xmlns="http://openbox.org/">
  <menu id="root-menu" label="Menu">
    <item label="Terminal">
      <action name="Execute"><command>xterm</command></action>
    </item>
    <item label="File Manager">
      <action name="Execute"><command>thunar</command></action>
    </item>
    <item label="Text Editor">
      <action name="Execute"><command>mousepad</command></action>
    </item>
    <item label="Firefox">
      <action name="Execute"><command>firefox-esr</command></action>
    </item>
    <separator />
    <item label="Exit">
      <action name="Exit"></action>
    </item>
  </menu>
</openbox_menu>
MENU_EOF
fi

echo "Desktop startup complete at $(date)"

# ── Keep-alive: restart WM if it dies (up to 5 times) ────────────────────────
restart_count=0
while true; do
    sleep 10
    if [[ -n "$WM_PID" ]] && kill -0 "$WM_PID" 2>/dev/null; then
        continue
    fi
    echo "WM died at $(date), restart #$((restart_count+1))"
    (( restart_count++ )) || true
    [[ $restart_count -gt 5 ]] && { echo "Too many restarts, giving up"; break; }

    start_wm openbox Openbox ||
    start_wm fluxbox Fluxbox ||
    start_wm twm     TWM     || true
done

echo "xstartup exiting at $(date)"
XSTARTUP_EOF

    chmod +x "$xstartup"
    chown "$TARGET_USER:$TARGET_USER" "$xstartup"

    # Mirror to legacy location
    cp "$xstartup" "$USER_HOME/.vnc/xstartup"
    chmod +x "$USER_HOME/.vnc/xstartup"
    chown "$TARGET_USER:$TARGET_USER" "$USER_HOME/.vnc/xstartup"

    print_success "xstartup script created"
}

# ──────────────────────────────────────────────────────────────────────────────
# Resolve the websockify binary once so the service file has a concrete path.
find_websockify() {
    if command -v websockify &>/dev/null; then
        echo "$(command -v websockify)"
    elif [[ -x /usr/bin/websockify ]]; then
        echo "/usr/bin/websockify"
    elif [[ -x /usr/share/novnc/utils/novnc_proxy ]]; then
        echo "/usr/share/novnc/utils/novnc_proxy"
    else
        print_error "Cannot find websockify or novnc_proxy"
        exit 1
    fi
}

# ──────────────────────────────────────────────────────────────────────────────
create_systemd_services() {
    print_status "Writing systemd service files..."

    local passwd_file="$USER_HOME/.config/tigervnc/passwd"
    local websockify_bin
    websockify_bin=$(find_websockify)

    # ── vnc-backend.service ───────────────────────────────────────────────────
    #
    # KEY DESIGN:
    #  • ExecStart runs Xvnc directly — no wrapper script, no forking.
    #    systemd Type=simple tracks this PID reliably across reboots.
    #  • ExecStartPost launches xstartup AS THE USER after Xvnc is up.
    #    The desktop session is a child of the service but not the tracked PID.
    #  • ExecStop kills by the lock-file PID, which is always the Xvnc process.
    #  • Display number is PINNED to :${DISPLAY_NUM} so the port never shifts.
    # ─────────────────────────────────────────────────────────────────────────
    cat > /etc/systemd/system/vnc-backend.service <<EOF
[Unit]
Description=TigerVNC Xvnc server on display :${DISPLAY_NUM}
After=multi-user.target network.target
Wants=network.target

[Service]
Type=simple
User=${TARGET_USER}
Group=${TARGET_USER}
WorkingDirectory=${USER_HOME}

Environment=HOME=${USER_HOME}
Environment=USER=${TARGET_USER}
Environment=DISPLAY=:${DISPLAY_NUM}
Environment=DESKTOP_ENV=${DESKTOP_ENV}

# ── Cleanup stale locks before starting ──────────────────────────────────────
ExecStartPre=/bin/bash -c 'rm -f /tmp/.X${DISPLAY_NUM}-lock /tmp/.X11-unix/X${DISPLAY_NUM}'
ExecStartPre=/bin/sleep 1

# ── Start Xvnc directly (stays in foreground — systemd tracks this PID) ───────
ExecStart=/usr/bin/Xvnc \
    :${DISPLAY_NUM} \
    -geometry ${VNC_GEOMETRY} \
    -depth 24 \
    -localhost yes \
    -SecurityTypes VncAuth \
    -PasswordFile ${passwd_file} \
    -rfbport ${VNC_PORT} \
    -fp /usr/share/fonts/X11/misc/,/usr/share/fonts/X11/Type1/

# ── Launch desktop session after Xvnc is ready ───────────────────────────────
ExecStartPost=/bin/bash -c '\
    sleep 3 && \
    DISPLAY=:${DISPLAY_NUM} \
    HOME=${USER_HOME} \
    USER=${TARGET_USER} \
    DESKTOP_ENV=${DESKTOP_ENV} \
    sudo -u ${TARGET_USER} \
        /bin/bash ${USER_HOME}/.config/tigervnc/xstartup &'

# ── Stop: kill by lock-file PID ───────────────────────────────────────────────
ExecStop=/bin/bash -c '\
    if [[ -f /tmp/.X${DISPLAY_NUM}-lock ]]; then \
        kill \$(cat /tmp/.X${DISPLAY_NUM}-lock) 2>/dev/null || true; \
    fi; \
    rm -f /tmp/.X${DISPLAY_NUM}-lock /tmp/.X11-unix/X${DISPLAY_NUM}'

Restart=always
RestartSec=10
StartLimitBurst=5
StartLimitIntervalSec=60
TimeoutStartSec=60
TimeoutStopSec=20

StandardOutput=journal
StandardError=journal
SyslogIdentifier=vnc-backend

[Install]
WantedBy=multi-user.target
EOF

    # ── novnc-proxy.service ───────────────────────────────────────────────────
    #
    # KEY DESIGN:
    #  • Uses /usr/bin/websockify directly — the novnc_proxy shell wrapper has
    #    extra process layers that confuse systemd restart tracking.
    #  • ExecStartPre polls until port ${VNC_PORT} is open (max 30 s).
    #  • --heartbeat keeps idle WebSocket connections alive through NAT.
    # ─────────────────────────────────────────────────────────────────────────
    cat > /etc/systemd/system/novnc-proxy.service <<EOF
[Unit]
Description=noVNC WebSocket proxy  0.0.0.0:${WEB_PORT} -> 127.0.0.1:${VNC_PORT}
After=network-online.target vnc-backend.service
Wants=network-online.target
Requires=vnc-backend.service

[Service]
Type=simple
User=${TARGET_USER}
Environment=HOME=${USER_HOME}

# Wait up to 30 s for Xvnc to open its port
ExecStartPre=/bin/bash -c '\
    for i in \$(seq 1 30); do \
        ss -tlnp | grep -q :${VNC_PORT} && exit 0; \
        sleep 1; \
    done; \
    echo "Timed out waiting for VNC port ${VNC_PORT}"; exit 1'

ExecStart=${websockify_bin} \
    --web /usr/share/novnc \
    --heartbeat 30 \
    0.0.0.0:${WEB_PORT} \
    127.0.0.1:${VNC_PORT}

Restart=always
RestartSec=5
StartLimitBurst=5
StartLimitIntervalSec=60
TimeoutStartSec=40
TimeoutStopSec=10

StandardOutput=journal
StandardError=journal
SyslogIdentifier=novnc-proxy

[Install]
WantedBy=multi-user.target
EOF

    print_success "Systemd service files written"
    print_status "  VNC  service : /etc/systemd/system/vnc-backend.service"
    print_status "  noVNC service: /etc/systemd/system/novnc-proxy.service"
    print_status "  Xvnc binary  : /usr/bin/Xvnc"
    print_status "  websockify   : ${websockify_bin}"
}

# ──────────────────────────────────────────────────────────────────────────────
configure_firewall() {
    print_status "Configuring firewall..."
    if command -v ufw &>/dev/null && ufw status | grep -q "Status: active"; then
        ufw allow "$WEB_PORT"/tcp || true
        print_success "UFW opened port $WEB_PORT"
    else
        print_warning "UFW not active — skipping firewall config"
    fi
}

# ──────────────────────────────────────────────────────────────────────────────
start_services() {
    print_status "Reloading systemd and starting services..."
    systemctl daemon-reload

    systemctl enable vnc-backend.service
    systemctl enable novnc-proxy.service

    # ── Start VNC ─────────────────────────────────────────────────────────────
    systemctl stop vnc-backend.service 2>/dev/null || true
    rm -f "/tmp/.X${DISPLAY_NUM}-lock" "/tmp/.X11-unix/X${DISPLAY_NUM}"
    sleep 1

    if ! systemctl start vnc-backend.service; then
        print_error "vnc-backend failed to start"
        journalctl -u vnc-backend.service --no-pager -n 30
        return 1
    fi

    # Poll until Xvnc is listening
    print_status "Waiting for Xvnc to open port ${VNC_PORT}..."
    local waited=0
    until ss -tlnp | grep -q ":${VNC_PORT}"; do
        sleep 2; (( waited+=2 ))
        if (( waited >= 30 )); then
            print_error "Xvnc did not open port ${VNC_PORT} within 30 s"
            journalctl -u vnc-backend.service --no-pager -n 20
            return 1
        fi
    done
    print_success "Xvnc listening on port ${VNC_PORT}"

    # ── Start noVNC ───────────────────────────────────────────────────────────
    if ! systemctl start novnc-proxy.service; then
        print_error "novnc-proxy failed to start"
        journalctl -u novnc-proxy.service --no-pager -n 30
        return 1
    fi

    sleep 3
    if ! systemctl is-active --quiet novnc-proxy.service; then
        print_error "novnc-proxy is not active"
        journalctl -u novnc-proxy.service --no-pager -n 20
        return 1
    fi

    print_success "Both services are running"
}

# ──────────────────────────────────────────────────────────────────────────────
verify_installation() {
    print_status "Verifying installation..."
    local ok=1

    systemctl is-active --quiet vnc-backend.service  \
        && print_success "vnc-backend  : active" \
        || { print_error "vnc-backend  : NOT active"; ok=0; }

    systemctl is-active --quiet novnc-proxy.service  \
        && print_success "novnc-proxy  : active" \
        || { print_error "novnc-proxy  : NOT active"; ok=0; }

    ss -tlnp | grep -q ":${VNC_PORT}" \
        && print_success "VNC port ${VNC_PORT}   : listening" \
        || { print_error "VNC port ${VNC_PORT}   : NOT listening"; ok=0; }

    ss -tlnp | grep -q ":${WEB_PORT}" \
        && print_success "Web port ${WEB_PORT}  : listening" \
        || { print_error "Web port ${WEB_PORT}  : NOT listening"; ok=0; }

    pgrep -x Xvnc &>/dev/null \
        && print_success "Xvnc process  : running" \
        || { print_error "Xvnc process  : NOT found"; ok=0; }

    [[ $ok -eq 1 ]]
}

# ──────────────────────────────────────────────────────────────────────────────
display_final_info() {
    local ip4
    ip4=$(hostname -I | awk '{print $1}' 2>/dev/null || echo "YOUR_SERVER_IP")

    echo
    echo "=================================================================="
    echo -e "${GREEN}  VNC/noVNC Installation Complete — Reboot-Safe Edition${NC}"
    echo "=================================================================="
    echo
    echo "  Configuration"
    echo "    User           : $TARGET_USER"
    echo "    Desktop        : $DESKTOP_ENV"
    echo "    Display        : :${DISPLAY_NUM}  (pinned)"
    echo "    VNC port       : ${VNC_PORT}       (pinned)"
    echo "    Web port       : ${WEB_PORT}"
    echo "    Geometry       : ${VNC_GEOMETRY}"
    echo
    echo "  Credentials"
    echo "    System passwd  : /root/vncuser_system_password.txt"
    echo "    VNC passwd     : /root/vncuser_vnc_password.txt"
    echo
    echo "  Access"
    echo "    Browser        : http://${ip4}:${WEB_PORT}/vnc.html"
    echo "    Direct VNC     : ${ip4}:${VNC_PORT}"
    echo
    echo "  Service control"
    echo "    Restart all    : systemctl restart vnc-backend novnc-proxy"
    echo "    VNC status     : systemctl status vnc-backend"
    echo "    noVNC status   : systemctl status novnc-proxy"
    echo "    VNC logs       : journalctl -u vnc-backend -f"
    echo "    noVNC logs     : journalctl -u novnc-proxy -f"
    echo
    echo "  Troubleshooting"
    echo "    Startup log    : tail -f ${USER_HOME}/.vnc/startup.log"
    echo "    Xvnc log       : tail -f ${USER_HOME}/.vnc/\$(hostname):${DISPLAY_NUM}.log"
    echo "    Ports          : ss -tlnp | grep -E ':(${VNC_PORT}|${WEB_PORT})'"
    echo "    Processes      : pgrep -a Xvnc"
    echo "=================================================================="
}

# ──────────────────────────────────────────────────────────────────────────────
main() {
    echo "=================================================================="
    echo "  VNC/noVNC Installer — Reboot-Safe Edition"
    echo "=================================================================="
    echo

    check_root
    detect_os
    fix_hostname_resolution
    create_vncuser

    update_system
    install_base_packages
    install_vnc_packages
    install_x11_packages
    install_desktop_environment
    install_additional_packages

    setup_vnc_password
    create_xstartup_script
    create_systemd_services
    configure_firewall

    start_services

    if verify_installation; then
        display_final_info
        print_success "Installation complete!"
        echo
        echo "  Reboot-safety improvements applied:"
        echo "  ✓ Xvnc runs directly — no vncserver wrapper process"
        echo "  ✓ Display :${DISPLAY_NUM} / port ${VNC_PORT} pinned (never shifts on reboot)"
        echo "  ✓ xstartup launched via ExecStartPost (desktop separate from tracked PID)"
        echo "  ✓ ExecStop kills by lock-file PID (always correct process)"
        echo "  ✓ websockify binary used directly in novnc-proxy"
        echo "  ✓ Both services enabled for automatic start on every boot"
        echo "  ✓ 30 s port-readiness gate between VNC start and noVNC start"
        echo "  ✓ --heartbeat 30 keeps WebSocket alive through NAT/firewalls"
        exit 0
    else
        print_error "Post-install verification failed."
        echo "Run: journalctl -u vnc-backend --no-pager -n 40"
        echo "Run: journalctl -u novnc-proxy --no-pager -n 40"
        exit 1
    fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
