#!/usr/bin/env bash

# Complete VNC/noVNC Installer for Clean Debian OS
# This script installs and configures VNC with noVNC web interface from scratch
# Compatible with Debian 11/12 and Ubuntu 20.04/22.04/24.04

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration (can be overridden by environment variables)
TARGET_USER="${TARGET_USER:-${SUDO_USER:-$(whoami)}}"
VNC_PASSWORD="${VNC_PASSWORD:-}"
WEB_PORT="${WEB_PORT:-6080}"
VNC_GEOMETRY="${VNC_GEOMETRY:-1280x800}"
DESKTOP_ENV="${DESKTOP_ENV:-xfce4}"  # xfce4, lxde, mate, minimal

# Derived variables
USER_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root (use sudo)"
        exit 1
    fi
}

# Function to detect OS
detect_os() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS=$ID
        OS_VERSION=$VERSION_ID
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

# Function to validate user
validate_user() {
    if ! id "$TARGET_USER" &>/dev/null; then
        print_error "User '$TARGET_USER' does not exist"
        exit 1
    fi
    
    if [[ ! -d "$USER_HOME" ]]; then
        print_error "Home directory '$USER_HOME' does not exist"
        exit 1
    fi
    
    print_status "Target user: $TARGET_USER"
    print_status "Home directory: $USER_HOME"
}

# Function to find available display
find_available_display() {
    for display_num in {2..99}; do
        if ! ss -lnx 2>/dev/null | grep "/tmp/.X11-unix/X$display_num" >/dev/null; then
            if ! [[ -f "/tmp/.X$display_num-lock" ]]; then
                echo $display_num
                return 0
            fi
        fi
    done
    print_error "No available display found!"
    exit 1
}

# Function to update system
update_system() {
    print_status "Updating system packages..."
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    apt-get upgrade -y -qq
    print_success "System updated"
}

# Function to install base packages
install_base_packages() {
    print_status "Installing base packages..."
    
    local base_packages=(
        "curl"
        "wget"
        "gnupg2"
        "software-properties-common"
        "apt-transport-https"
        "ca-certificates"
        "lsb-release"
        "systemd"
        "dbus"
        "dbus-x11"
    )
    
    apt-get install -y "${base_packages[@]}"
    print_success "Base packages installed"
}

# Function to install VNC packages
install_vnc_packages() {
    print_status "Installing VNC packages..."
    
    local vnc_packages=(
        "tigervnc-standalone-server"
        "tigervnc-common"
        "tigervnc-tools"
        "x11vnc"
        "novnc"
        "python3-websockify"
        "websockify"
    )
    
    apt-get install -y "${vnc_packages[@]}"
    print_success "VNC packages installed"
}

# Function to install X11 packages
install_x11_packages() {
    print_status "Installing X11 packages..."
    
    local x11_packages=(
        "xorg"
        "xserver-xorg-core"
        "xfonts-base"
        "xfonts-75dpi"
        "xfonts-100dpi"
        "xfonts-scalable"
        "x11-apps"
        "x11-utils"
        "x11-xserver-utils"
        "xterm"
    )
    
    apt-get install -y "${x11_packages[@]}"
    print_success "X11 packages installed"
}

# Function to install desktop environment
install_desktop_environment() {
    print_status "Installing desktop environment: $DESKTOP_ENV"
    
    case "$DESKTOP_ENV" in
        "xfce4")
            apt-get install -y xfce4 xfce4-goodies xfce4-terminal
            ;;
        "lxde")
            apt-get install -y lxde-core lxde-common lxterminal
            ;;
        "mate")
            apt-get install -y mate-desktop-environment-core mate-terminal
            ;;
        "minimal")
            apt-get install -y fluxbox openbox twm
            ;;
        *)
            print_warning "Unknown desktop environment '$DESKTOP_ENV', installing minimal setup"
            apt-get install -y fluxbox openbox twm
            DESKTOP_ENV="minimal"
            ;;
    esac
    
    print_success "Desktop environment installed: $DESKTOP_ENV"
}

# Function to install additional useful packages
install_additional_packages() {
    print_status "Installing additional useful packages..."
    
    local additional_packages=(
        "firefox-esr"
        "gedit"
        "file-manager-actions"
        "thunar"
        "nano"
        "vim"
        "htop"
        "net-tools"
        "sudo"
    )
    
    # Install packages that are available
    for package in "${additional_packages[@]}"; do
        if apt-cache show "$package" >/dev/null 2>&1; then
            apt-get install -y "$package" || print_warning "Failed to install $package"
        else
            print_warning "Package $package not available"
        fi
    done
    
    print_success "Additional packages installed"
}

# Function to setup VNC password
setup_vnc_password() {
    print_status "Setting up VNC password..."
    
    # Create .vnc directory
    install -d -m 700 -o "$TARGET_USER" -g "$TARGET_USER" "$USER_HOME/.vnc"
    
    if [[ -z "$VNC_PASSWORD" ]]; then
        print_status "No VNC_PASSWORD provided. Please set a VNC password for user '$TARGET_USER':"
        sudo -u "$TARGET_USER" bash -c "cd '$USER_HOME' && vncpasswd"
    else
        # Non-interactive password setup
        print_status "Setting VNC password non-interactively"
        local password_hash
        password_hash=$(sudo -u "$TARGET_USER" bash -c "printf '%s\n' '$VNC_PASSWORD' | vncpasswd -f")
        printf '%s' "$password_hash" > "$USER_HOME/.vnc/passwd"
        chmod 600 "$USER_HOME/.vnc/passwd"
        chown "$TARGET_USER:$TARGET_USER" "$USER_HOME/.vnc/passwd"
    fi
    
    print_success "VNC password configured"
}

# Function to create xstartup script
create_xstartup_script() {
    print_status "Creating xstartup script..."
    
    local xstartup_file="$USER_HOME/.vnc/xstartup"
    
    cat > "$xstartup_file" <<'EOF'
#!/bin/bash

# VNC xstartup script with detailed logging
LOG_FILE="$HOME/.vnc/startup.log"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "=== VNC Startup $(date) ==="
echo "USER: $USER"
echo "HOME: $HOME"
echo "DISPLAY: $DISPLAY"
echo "PATH: $PATH"

# Unset problematic session variables
unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS

# Set up environment
export USER="${USER:-$(whoami)}"
export HOME="${HOME:-$(getent passwd $USER | cut -d: -f6)}"
export SHELL="${SHELL:-/bin/bash}"

# Create .Xauthority if it doesn't exist
if [ ! -f "$HOME/.Xauthority" ]; then
    touch "$HOME/.Xauthority"
    chmod 600 "$HOME/.Xauthority"
fi

# Start dbus session
echo "Starting D-Bus session..."
if [ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ]; then
    eval $(dbus-launch --sh-syntax --exit-with-session)
    export DBUS_SESSION_BUS_ADDRESS
fi

# Set up basic X11 environment
echo "Setting up X11 environment..."
xrdb "$HOME/.Xresources" 2>/dev/null || true
xsetroot -solid grey 2>/dev/null || true

# Start desktop environment
echo "Starting desktop environment..."

if command -v startxfce4 >/dev/null 2>&1; then
    echo "Starting XFCE4..."
    exec startxfce4
elif command -v startlxde >/dev/null 2>&1; then
    echo "Starting LXDE..."
    exec startlxde
elif command -v mate-session >/dev/null 2>&1; then
    echo "Starting MATE..."
    exec mate-session
elif command -v fluxbox >/dev/null 2>&1; then
    echo "Starting Fluxbox..."
    fluxbox &
    wm_pid=$!
    xterm -geometry 80x24+10+10 -ls -title "VNC Desktop" &
    wait $wm_pid
elif command -v openbox >/dev/null 2>&1; then
    echo "Starting Openbox..."
    openbox &
    wm_pid=$!
    xterm -geometry 80x24+10+10 -ls -title "VNC Desktop" &
    wait $wm_pid
else
    echo "Starting minimal desktop..."
    xterm -geometry 80x24+10+10 -ls -title "VNC Desktop" &
    exec twm
fi
EOF
    
    chown "$TARGET_USER:$TARGET_USER" "$xstartup_file"
    chmod +x "$xstartup_file"
    
    print_success "xstartup script created"
}

# Function to find available display and set ports
setup_display_and_ports() {
    print_status "Finding available display..."
    
    # Clean up any existing VNC sessions first
    sudo -u "$TARGET_USER" bash -c "vncserver -list" 2>/dev/null || true
    for old_display in {1..10}; do
        sudo -u "$TARGET_USER" bash -c "vncserver -kill :$old_display" 2>/dev/null || true
    done
    
    # Find available display
    DISPLAY_NUM=$(find_available_display)
    VNC_PORT=$((5900 + DISPLAY_NUM))
    
    print_success "Using Display :$DISPLAY_NUM (Port $VNC_PORT)"
    
    # Export for use in systemd services
    export DISPLAY_NUM VNC_PORT
}

# Function to test VNC manually
test_vnc_manual() {
    print_status "Testing VNC startup manually..."
    
    if sudo -u "$TARGET_USER" bash -c "cd '$USER_HOME' && vncserver :$DISPLAY_NUM -geometry $VNC_GEOMETRY -localhost yes -SecurityTypes VncAuth"; then
        print_success "VNC started successfully on display :$DISPLAY_NUM"
        
        # Wait and check if listening
        sleep 3
        if ss -tlnp | grep ":$VNC_PORT" >/dev/null; then
            print_success "VNC is listening on port $VNC_PORT"
        else
            print_error "VNC started but not listening on port $VNC_PORT"
            return 1
        fi
        
        # Kill the test instance
        sudo -u "$TARGET_USER" vncserver -kill ":$DISPLAY_NUM"
        sleep 2
        return 0
    else
        print_error "VNC failed to start on display :$DISPLAY_NUM"
        if [[ -f "$USER_HOME/.vnc/$(hostname):$DISPLAY_NUM.log" ]]; then
            print_error "VNC log contents:"
            cat "$USER_HOME/.vnc/$(hostname):$DISPLAY_NUM.log"
        fi
        return 1
    fi
}

# Function to create systemd services
create_systemd_services() {
    print_status "Creating systemd services..."
    
    # VNC Backend Service
    cat > /etc/systemd/system/vnc-backend.service <<EOF
[Unit]
Description=TigerVNC virtual desktop on :$DISPLAY_NUM (localhost only)
After=network-online.target
Wants=network-online.target

[Service]
Type=forking
User=$TARGET_USER
Group=$TARGET_USER
WorkingDirectory=$USER_HOME
Environment=HOME=$USER_HOME
Environment=USER=$TARGET_USER
PIDFile=$USER_HOME/.vnc/$(hostname):$DISPLAY_NUM.pid
ExecStartPre=/bin/sh -c '/usr/bin/vncserver -kill :$DISPLAY_NUM > /dev/null 2>&1 || :'
ExecStart=/usr/bin/vncserver :$DISPLAY_NUM -geometry $VNC_GEOMETRY -localhost yes -SecurityTypes VncAuth -PasswordFile $USER_HOME/.vnc/passwd
ExecStop=/usr/bin/vncserver -kill :$DISPLAY_NUM
Restart=on-failure
RestartSec=10
TimeoutStartSec=60

[Install]
WantedBy=multi-user.target
EOF
    
    # noVNC Proxy Service
    cat > /etc/systemd/system/novnc-proxy.service <<EOF
[Unit]
Description=noVNC WebSocket proxy on :$WEB_PORT -> localhost:$VNC_PORT
After=network-online.target vnc-backend.service
Wants=network-online.target
Requires=vnc-backend.service

[Service]
Type=simple
User=$TARGET_USER
Environment=HOME=$USER_HOME
ExecStart=/usr/share/novnc/utils/novnc_proxy --listen 0.0.0.0:$WEB_PORT --vnc 127.0.0.1:$VNC_PORT
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
    
    print_success "Systemd services created"
}

# Function to configure firewall
configure_firewall() {
    print_status "Configuring firewall..."
    
    if command -v ufw >/dev/null 2>&1; then
        if ufw status | grep -q "Status: active"; then
            ufw allow "$WEB_PORT"/tcp || true
            print_success "UFW firewall configured for port $WEB_PORT"
        else
            print_warning "UFW firewall is not active"
        fi
    else
        print_warning "UFW firewall not installed"
    fi
}

# Function to start services
start_services() {
    print_status "Starting and enabling services..."
    
    systemctl daemon-reload
    systemctl enable vnc-backend.service novnc-proxy.service
    
    if systemctl start vnc-backend.service; then
        print_success "VNC backend service started"
        sleep 5
        
        if systemctl start novnc-proxy.service; then
            print_success "noVNC proxy service started"
        else
            print_error "noVNC proxy service failed to start"
            systemctl status novnc-proxy.service --no-pager -l
            return 1
        fi
    else
        print_error "VNC backend service failed to start"
        systemctl status vnc-backend.service --no-pager -l
        return 1
    fi
}

# Function to verify installation
verify_installation() {
    print_status "Verifying installation..."
    
    # Check services
    if systemctl is-active --quiet vnc-backend.service; then
        print_success "VNC backend service is running"
    else
        print_error "VNC backend service is not running"
        return 1
    fi
    
    if systemctl is-active --quiet novnc-proxy.service; then
        print_success "noVNC proxy service is running"
    else
        print_error "noVNC proxy service is not running"
        return 1
    fi
    
    
    return 0
}

# Function to display final information
display_final_info() {
    local ip4
    ip4=$(hostname -I | awk '{print $1}' || echo "localhost")
    
    echo
    echo "=================================================================="
    echo -e "${GREEN}VNC/noVNC Installation Complete!${NC}"
    echo "=================================================================="
    echo
    echo "Configuration Summary:"
    echo "  Target User:      $TARGET_USER"
    echo "  Desktop Environment: $DESKTOP_ENV"
    echo "  VNC Display:      :$DISPLAY_NUM"
    echo "  VNC Port:         $VNC_PORT"
    echo "  Web Port:         $WEB_PORT"
    echo "  Geometry:         $VNC_GEOMETRY"
    echo
    echo "Access Information:"
    echo "  Web Interface:    http://$ip4:$WEB_PORT/vnc.html"
    echo "  Direct VNC:       $ip4:$VNC_PORT"
    echo "  Local Web:        http://localhost:$WEB_PORT/vnc.html"
    echo
    echo "Usage Instructions:"
    echo "  1. Open a web browser"
    echo "  2. Navigate to: http://$ip4:$WEB_PORT/vnc.html"
    echo "  3. Click 'Connect'"
    echo "  4. Enter your VNC password when prompted"
    echo "  5. Enjoy your remote desktop!"
    echo
    echo "Service Management:"
    echo "  Start VNC:        sudo systemctl start vnc-backend.service"
    echo "  Stop VNC:         sudo systemctl stop vnc-backend.service"
    echo "  VNC Status:       sudo systemctl status vnc-backend.service"
    echo "  Start noVNC:      sudo systemctl start novnc-proxy.service"
    echo "  Stop noVNC:       sudo systemctl stop novnc-proxy.service"
    echo
    echo "Log Files:"
    echo "  VNC Startup:      $USER_HOME/.vnc/startup.log"
    echo "  VNC Server:       $USER_HOME/.vnc/$(hostname):$DISPLAY_NUM.log"
    echo "  System Logs:      journalctl -u vnc-backend.service"
    echo "=================================================================="
}


# Wait for all components to finish loading up
sleep 20

# Main installation function
main() {
    echo "=================================================================="
    echo "VNC/noVNC Complete Installer for Clean Debian/Ubuntu"
    echo "=================================================================="
    echo
    
    # Preliminary checks
    check_root
    detect_os
    validate_user
    
    # Installation steps
    update_system
    install_base_packages
    install_vnc_packages
    install_x11_packages
    install_desktop_environment
    install_additional_packages
    
    # Configuration steps
    setup_vnc_password
    create_xstartup_script
    setup_display_and_ports
    
    # Testing and service setup
    if test_vnc_manual; then
        create_systemd_services
        configure_firewall
        start_services
        
        if verify_installation; then
            display_final_info
            print_success "Installation completed successfully!"
            exit 0
        else
            print_error "Installation verification failed"
            exit 1
        fi
    else
        print_error "Manual VNC test failed. Installation aborted."
        exit 1
    fi
}

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
