#!/usr/bin/env bash

# Complete VNC/noVNC Installer for Clean Debian OS - FIXED VERSION
# This script installs and configures VNC with noVNC web interface from scratch
# Compatible with Debian 11/12 and Ubuntu 20.04/22.04/24.04
# Includes fixes for session crashes and connection issues

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
DESKTOP_ENV="${DESKTOP_ENV:-minimal}"  # minimal, xfce4, lxde, mate

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
        "tigervnc-viewer"
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
            apt-get install -y fluxbox openbox twm fvwm
            ;;
        *)
            print_warning "Unknown desktop environment '$DESKTOP_ENV', installing minimal setup"
            apt-get install -y fluxbox openbox twm fvwm
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
        "thunar"
        "nano"
        "vim"
        "htop"
        "net-tools"
        "sudo"
        "pcmanfm"
        "mousepad"
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

# Function to create bulletproof xstartup script
create_xstartup_script() {
    print_status "Creating bulletproof xstartup script..."
    
    local xstartup_file="$USER_HOME/.vnc/xstartup"
    
    cat > "$xstartup_file" <<'EOF'
#!/bin/bash

# Bulletproof VNC xstartup script with comprehensive error handling
LOG_FILE="$HOME/.vnc/startup.log"

# Redirect all output to log file with timestamps
exec > >(while IFS= read -r line; do echo "$(date '+%Y-%m-%d %H:%M:%S'): $line"; done >> "$LOG_FILE") 2>&1

echo "=== VNC Startup Started ==="
echo "USER: $USER"
echo "HOME: $HOME"
echo "DISPLAY: $DISPLAY"
echo "PATH: $PATH"
echo "PWD: $(pwd)"

# Clean problematic environment variables
unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS
unset XDG_SESSION_PATH
unset XDG_SESSION_ID
unset XDG_SESSION_COOKIE

# Set essential environment variables
export USER="${USER:-$(whoami)}"
export HOME="${HOME:-$(getent passwd $USER | cut -d: -f6)}"
export SHELL="${SHELL:-/bin/bash}"
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
export LANG="${LANG:-en_US.UTF-8}"
export LC_ALL="${LC_ALL:-en_US.UTF-8}"

echo "Environment cleaned and configured"

# Create .Xauthority if it doesn't exist
if [ ! -f "$HOME/.Xauthority" ]; then
    touch "$HOME/.Xauthority"
    chmod 600 "$HOME/.Xauthority"
    echo "Created .Xauthority file"
fi

# Start D-Bus session if needed
echo "Setting up D-Bus session..."
if [ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ]; then
    if command -v dbus-launch >/dev/null 2>&1; then
        eval $(dbus-launch --sh-syntax)
        export DBUS_SESSION_BUS_ADDRESS
        echo "D-Bus session started: $DBUS_SESSION_BUS_ADDRESS"
    else
        echo "D-Bus not available, skipping"
    fi
fi

# Set up basic X11 environment
echo "Setting up X11 environment..."
xrdb "$HOME/.Xresources" 2>/dev/null || echo "No .Xresources file found"
xsetroot -solid "#2E3440" 2>/dev/null || echo "Failed to set background color"

# Function to start a window manager and keep it running
start_window_manager() {
    local wm_command="$1"
    local wm_name="$2"
    
    echo "Attempting to start $wm_name..."
    
    if command -v "$wm_command" >/dev/null 2>&1; then
        echo "Starting $wm_name window manager..."
        "$wm_command" &
        WM_PID=$!
        
        # Give it time to start
        sleep 2
        
        # Check if it's still running
        if kill -0 "$WM_PID" 2>/dev/null; then
            echo "$wm_name started successfully with PID: $WM_PID"
            return 0
        else
            echo "$wm_name failed to start or crashed immediately"
            return 1
        fi
    else
        echo "$wm_name command not found"
        return 1
    fi
}

# Function to start applications
start_applications() {
    echo "Starting applications..."
    
    # Start terminal
    if command -v xterm >/dev/null 2>&1; then
        xterm -geometry 80x30+50+50 -title "VNC Terminal" -e bash &
        echo "Started xterm terminal"
    elif command -v xfce4-terminal >/dev/null 2>&1; then
        xfce4-terminal --geometry 80x30 --title "VNC Terminal" &
        echo "Started xfce4-terminal"
    fi
    
    # Start file manager
    if command -v thunar >/dev/null 2>&1; then
        thunar &
        echo "Started Thunar file manager"
    elif command -v pcmanfm >/dev/null 2>&1; then
        pcmanfm &
        echo "Started PCManFM file manager"
    fi
    
    # Start text editor
    if command -v mousepad >/dev/null 2>&1; then
        mousepad &
        echo "Started Mousepad text editor"
    elif command -v gedit >/dev/null 2>&1; then
        gedit &
        echo "Started gedit text editor"
    fi
}

# Try to start desktop environment in order of preference
echo "Starting desktop environment..."

WM_PID=""

# Try different desktop environments/window managers
if [[ "$DESKTOP_ENV" == "xfce4" ]] && command -v startxfce4 >/dev/null 2>&1; then
    echo "Attempting to start XFCE4 desktop..."
    # Try XFCE but with fallback
    startxfce4 &
    XFCE_PID=$!
    sleep 5
    
    if kill -0 "$XFCE_PID" 2>/dev/null; then
        echo "XFCE4 started successfully"
        WM_PID=$XFCE_PID
    else
        echo "XFCE4 failed, falling back to window manager"
    fi
fi

# If XFCE failed or we're using minimal, try window managers
if [[ -z "$WM_PID" ]] || ! kill -0 "$WM_PID" 2>/dev/null; then
    echo "Starting window manager fallback sequence..."
    
    # Try different window managers in order of preference
    if start_window_manager "openbox" "Openbox"; then
        WM_PID=$WM_PID
    elif start_window_manager "fluxbox" "Fluxbox"; then
        WM_PID=$WM_PID
    elif start_window_manager "fvwm" "FVWM"; then
        WM_PID=$WM_PID
    elif start_window_manager "twm" "TWM"; then
        WM_PID=$WM_PID
    else
        echo "ERROR: No window manager could be started!"
        echo "Available window managers:"
        command -v openbox && echo "  - openbox: available"
        command -v fluxbox && echo "  - fluxbox: available"
        command -v fvwm && echo "  - fvwm: available"
        command -v twm && echo "  - twm: available"
        exit 1
    fi
fi

# Start applications after window manager is running
sleep 2
start_applications

echo "Desktop startup complete at $(date)"
echo "Window manager PID: $WM_PID"

# Create a simple right-click menu for some window managers
if command -v openbox >/dev/null 2>&1 && pgrep openbox >/dev/null; then
    mkdir -p "$HOME/.config/openbox"
    cat > "$HOME/.config/openbox/menu.xml" <<'MENU_EOF'
<?xml version="1.0" encoding="UTF-8"?>
<openbox_menu xmlns="http://openbox.org/">
  <menu id="root-menu" label="Openbox 3">
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
    echo "Created Openbox menu"
fi

# Monitor the session and keep it alive
echo "Monitoring desktop session..."

# Function to monitor and restart if needed
monitor_session() {
    local check_interval=10
    local restart_attempts=0
    local max_restarts=3
    
    while true; do
        sleep $check_interval
        
        if [[ -n "$WM_PID" ]] && kill -0 "$WM_PID" 2>/dev/null; then
            # Window manager is still running
            continue
        else
            echo "Window manager stopped at $(date)"
            
            if [[ $restart_attempts -lt $max_restarts ]]; then
                echo "Attempting to restart window manager (attempt $((restart_attempts + 1)))"
                
                if start_window_manager "openbox" "Openbox" || \
                   start_window_manager "fluxbox" "Fluxbox" || \
                   start_window_manager "twm" "TWM"; then
                    echo "Window manager restarted successfully"
                    restart_attempts=0
                else
                    restart_attempts=$((restart_attempts + 1))
                    echo "Failed to restart window manager"
                fi
            else
                echo "Maximum restart attempts reached, exiting"
                break
            fi
        fi
    done
}

# Start monitoring in background and wait for the main process
monitor_session &
MONITOR_PID=$!

# Wait for the window manager to exit
if [[ -n "$WM_PID" ]]; then
    wait "$WM_PID"
fi

# Clean up
kill "$MONITOR_PID" 2>/dev/null || true

echo "VNC session ended at $(date)"
EOF
    
    chown "$TARGET_USER:$TARGET_USER" "$xstartup_file"
    chmod +x "$xstartup_file"
    
    print_success "Bulletproof xstartup script created"
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
    
    # Clean up any existing locks or sessions
    rm -f "/tmp/.X$DISPLAY_NUM-lock" "/tmp/.X11-unix/X$DISPLAY_NUM" 2>/dev/null || true
    
    if sudo -u "$TARGET_USER" bash -c "cd '$USER_HOME' && vncserver :$DISPLAY_NUM -geometry $VNC_GEOMETRY -localhost yes -SecurityTypes VncAuth -verbose"; then
        print_success "VNC started successfully on display :$DISPLAY_NUM"
        
        # Wait and check if listening
        sleep 5
        if ss -tlnp | grep ":$VNC_PORT" >/dev/null; then
            print_success "VNC is listening on port $VNC_PORT"
            
            # Check if the process is still running
            if pgrep -f "Xtigervnc.*:$DISPLAY_NUM" >/dev/null; then
                print_success "VNC process is stable and running"
                
                # Show some log information
                echo "=== VNC Startup Log ==="
                tail -10 "$USER_HOME/.vnc/startup.log" 2>/dev/null || echo "No startup log yet"
                
                # Kill the test instance
                sudo -u "$TARGET_USER" vncserver -kill ":$DISPLAY_NUM"
                sleep 2
                return 0
            else
                print_error "VNC process died after starting"
                return 1
            fi
        else
            print_error "VNC started but not listening on port $VNC_PORT"
            return 1
        fi
    else
        print_error "VNC failed to start on display :$DISPLAY_NUM"
        if [[ -f "$USER_HOME/.vnc/$(hostname):$DISPLAY_NUM.log" ]]; then
            print_error "VNC log contents:"
            cat "$USER_HOME/.vnc/$(hostname):$DISPLAY_NUM.log"
        fi
        return 1
    fi
}

# Function to create robust systemd services
create_systemd_services() {
    print_status "Creating robust systemd services..."
    
    # VNC Backend Service - Using Type=simple instead of forking for better reliability
    cat > /etc/systemd/system/vnc-backend.service <<EOF
[Unit]
Description=TigerVNC virtual desktop on :$DISPLAY_NUM (localhost only)
After=multi-user.target network.target
Wants=network.target

[Service]
Type=simple
User=$TARGET_USER
Group=$TARGET_USER
WorkingDirectory=$USER_HOME
Environment=HOME=$USER_HOME
Environment=USER=$TARGET_USER
Environment=DISPLAY=:$DISPLAY_NUM

# Cleanup before starting
ExecStartPre=/bin/bash -c 'vncserver -kill :$DISPLAY_NUM >/dev/null 2>&1 || true'
ExecStartPre=/bin/bash -c 'rm -f /tmp/.X$DISPLAY_NUM-lock /tmp/.X11-unix/X$DISPLAY_NUM $USER_HOME/.vnc/*.pid || true'
ExecStartPre=/bin/sleep 2

# Start VNC server with wrapper script
ExecStart=/bin/bash -c 'cd $USER_HOME && exec vncserver :$DISPLAY_NUM -geometry $VNC_GEOMETRY -localhost yes -SecurityTypes VncAuth -fg'

# Stop command
ExecStop=/bin/bash -c 'vncserver -kill :$DISPLAY_NUM || true'

# Restart policy
Restart=always
RestartSec=10
StartLimitBurst=5
StartLimitIntervalSec=60

# Timeouts
TimeoutStartSec=60
TimeoutStopSec=15

[Install]
WantedBy=multi-user.target
EOF
    
    # noVNC Proxy Service - Enhanced with better error handling
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

# Wait for VNC to be ready
ExecStartPre=/bin/bash -c 'for i in {1..30}; do ss -tlnp | grep :$VNC_PORT && break; sleep 1; done'

# Start noVNC proxy with web directory
ExecStart=/usr/share/novnc/utils/novnc_proxy --listen 0.0.0.0:$WEB_PORT --vnc 127.0.0.1:$VNC_PORT --web /usr/share/novnc

# Restart policy
Restart=always
RestartSec=5
StartLimitBurst=5
StartLimitIntervalSec=60

# Timeouts
TimeoutStartSec=30
TimeoutStopSec=10

[Install]
WantedBy=multi-user.target
EOF
    
    print_success "Robust systemd services created"
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

# Function to start services with proper sequencing
start_services() {
    print_status "Starting and enabling services with proper sequencing..."
    
    systemctl daemon-reload
    
    # Enable services
    systemctl enable vnc-backend.service
    systemctl enable novnc-proxy.service
    
    # Start VNC backend first
    print_status "Starting VNC backend service..."
    if systemctl start vnc-backend.service; then
        print_success "VNC backend service started"
        
        # Wait for VNC to be fully ready
        print_status "Waiting for VNC to be ready..."
        local attempts=0
        while [[ $attempts -lt 30 ]]; do
            if ss -tlnp | grep ":$VNC_PORT" >/dev/null && systemctl is-active --quiet vnc-backend.service; then
                print_success "VNC backend is ready and listening on port $VNC_PORT"
                break
            fi
            sleep 2
            attempts=$((attempts + 1))
        done
        
        if [[ $attempts -eq 30 ]]; then
            print_error "VNC backend failed to become ready within timeout"
            systemctl status vnc-backend.service --no-pager -l
            return 1
        fi
        
        # Now start noVNC proxy
        print_status "Starting noVNC proxy service..."
        if systemctl start novnc-proxy.service; then
            print_success "noVNC proxy service started"
            
            # Wait for noVNC to be ready
            sleep 5
            if systemctl is-active --quiet novnc-proxy.service; then
                print_success "noVNC proxy is running"
                
                # Test web interface
                if curl -s --max-time 5 "http://localhost:$WEB_PORT/" >/dev/null; then
                    print_success "noVNC web interface is responding"
                else
                    print_warning "noVNC web interface may not be fully ready yet"
                fi
            else
                print_error "noVNC proxy service is not active"
                systemctl status novnc-proxy.service --no-pager -l
                return 1
            fi
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
    
    # Check ports
    if ss -tlnp | grep ":$VNC_PORT" >/dev/null; then
        print_success "VNC is listening on port $VNC_PORT"
    else
        print_error "VNC is not listening on port $VNC_PORT"
        return 1
    fi
    
    if ss -tlnp | grep ":$WEB_PORT" >/dev/null; then
        print_success "noVNC proxy is listening on port $WEB_PORT"
    else
        print_error "noVNC proxy is not listening on port $WEB_PORT"
        return 1
    fi
    
    # Check VNC process
    if pgrep -f "Xtigervnc.*:$DISPLAY_NUM" >/dev/null; then
        print_success "VNC server process is running"
    else
        print_error "VNC server process is not running"
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
    echo "  Target User:         $TARGET_USER"
    echo "  Desktop Environment: $DESKTOP_ENV"
    echo "  VNC Display:         :$DISPLAY_NUM"
    echo "  VNC Port:            $VNC_PORT"
    echo "  Web Port:            $WEB_PORT"
    echo "  Geometry:            $VNC_GEOMETRY"
    echo
    echo "Access Information:"
    echo "  Web Interface:       http://$ip4:$WEB_PORT/vnc.html"
    echo "  Direct VNC:          $ip4:$VNC_PORT"
    echo "  Local Web:           http://localhost:$WEB_PORT/vnc.html"
    echo
    echo "Usage Instructions:"
    echo "  1. Open a web browser"
    echo "  2. Navigate to: http://$ip4:$WEB_PORT/vnc.html"
    echo "  3. Click 'Connect'"
    echo "  4. Enter your VNC password when prompted"
    echo "  5. Enjoy your remote desktop!"
    echo
    echo "Service Management:"
    echo "  Start VNC:           sudo systemctl start vnc-backend.service"
    echo "  Stop VNC:            sudo systemctl stop vnc-backend.service"
    echo "  VNC Status:          sudo systemctl status vnc-backend.service"
    echo "  Start noVNC:         sudo systemctl start novnc-proxy.service"
    echo "  Stop noVNC:          sudo systemctl stop novnc-proxy.service"
    echo "  Restart Both:        sudo systemctl restart vnc-backend.service novnc-proxy.service"
    echo
    echo "Troubleshooting:"
    echo "  VNC Startup Log:     tail -f $USER_HOME/.vnc/startup.log"
    echo "  VNC Server Log:      tail -f $USER_HOME/.vnc/$(hostname):$DISPLAY_NUM.log"
    echo "  System VNC Logs:     journalctl -u vnc-backend.service -f"
    echo "  System noVNC Logs:   journalctl -u novnc-proxy.service -f"
    echo "  Check Processes:     ps aux | grep vnc"
    echo "  Check Ports:         ss -tlnp | grep -E ':(5902|6080)'"
    echo "  Manual VNC Test:     cd $USER_HOME && vncserver :$DISPLAY_NUM
  Kill Manual Test:    vncserver -kill :$DISPLAY_NUM"
    echo "=================================================================="
}

# Main installation function
main() {
    echo "=================================================================="
    echo "VNC/noVNC Complete Installer for Clean Debian/Ubuntu - FIXED"
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
            echo
            print_status "The VNC server is now running with these improvements:"
            echo "  ✓ Bulletproof xstartup script with error recovery"
            echo "  ✓ Multiple window manager fallbacks"
            echo "  ✓ Robust systemd service configuration"
            echo "  ✓ Enhanced logging for troubleshooting"
            echo "  ✓ Automatic session monitoring and restart"
            echo "  ✓ Proper service dependencies and timing"
            exit 0
        else
            print_error "Installation verification failed"
            echo "Please check the logs and try the manual troubleshooting commands above."
            exit 1
        fi
    else
        print_error "Manual VNC test failed. Installation aborted."
        echo "This indicates a fundamental issue with the VNC setup."
        echo "Please check the system logs and try running the installation again."
        exit 1
    fi
}

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
