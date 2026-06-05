#!/usr/bin/env bash

# VNC/noVNC Complete Disabler & Cleanup Script
# Fully reverses the setup performed by the VNC installer
# Compatible with Debian 11/12 and Ubuntu 20.04/22.04/24.04

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

TARGET_USER="${TARGET_USER:-vncuser}"
REMOVE_USER="${REMOVE_USER:-true}"        # Set to "false" to keep the system user
REMOVE_PACKAGES="${REMOVE_PACKAGES:-false}" # Set to "true" to also purge installed packages

print_status()  { echo -e "${BLUE}[INFO]${NC}    $1"; }
print_success() { echo -e "${GREEN}[OK]${NC}      $1"; }
print_warning() { echo -e "${YELLOW}[WARN]${NC}    $1"; }
print_error()   { echo -e "${RED}[ERROR]${NC}   $1"; }
print_step()    { echo; echo -e "${BLUE}──────────────────────────────────────────${NC}"; echo -e "${BLUE}  $1${NC}"; echo -e "${BLUE}──────────────────────────────────────────${NC}"; }

check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root (use sudo)."
        exit 1
    fi
}

# ── 1. Stop & disable systemd services ────────────────────────────────────────
stop_services() {
    print_step "Stopping and disabling systemd services"

    for svc in novnc-proxy.service vnc-backend.service; do
        if systemctl list-unit-files --full --all | grep -q "^${svc}"; then
            systemctl stop    "$svc" 2>/dev/null && print_success "Stopped  $svc" || print_warning "Could not stop $svc (may already be stopped)"
            systemctl disable "$svc" 2>/dev/null && print_success "Disabled $svc" || print_warning "Could not disable $svc"
        else
            print_warning "Service $svc not found – skipping"
        fi
    done
}

# ── 2. Remove systemd unit files ──────────────────────────────────────────────
remove_unit_files() {
    print_step "Removing systemd unit files"

    for unit_file in /etc/systemd/system/vnc-backend.service \
                     /etc/systemd/system/novnc-proxy.service; do
        if [[ -f "$unit_file" ]]; then
            rm -f "$unit_file"
            print_success "Removed $unit_file"
        else
            print_warning "$unit_file not found – skipping"
        fi
    done

    systemctl daemon-reload
    print_success "systemd daemon reloaded"
}

# ── 3. Kill any lingering VNC / noVNC processes ───────────────────────────────
kill_vnc_processes() {
    print_step "Killing any remaining VNC / noVNC / websockify processes"

    local killed=false

    for pattern in "Xtigervnc" "vncserver" "x11vnc" "novnc" "websockify"; do
        if pgrep -f "$pattern" >/dev/null 2>&1; then
            pkill -f "$pattern" && print_success "Killed processes matching: $pattern" || true
            killed=true
        fi
    done

    # Give processes time to die, then force-kill survivors
    sleep 2
    for pattern in "Xtigervnc" "vncserver" "x11vnc" "novnc" "websockify"; do
        if pgrep -f "$pattern" >/dev/null 2>&1; then
            pkill -9 -f "$pattern" && print_warning "Force-killed $pattern" || true
        fi
    done

    $killed || print_status "No active VNC/noVNC processes found"
}

# ── 4. Kill VNC sessions owned by the target user ─────────────────────────────
kill_user_vnc_sessions() {
    print_step "Terminating VNC sessions owned by '$TARGET_USER'"

    if id "$TARGET_USER" &>/dev/null; then
        # Kill all numbered displays
        for display_num in {1..20}; do
            sudo -u "$TARGET_USER" vncserver -kill ":$display_num" 2>/dev/null && \
                print_success "Killed VNC session :$display_num" || true
        done
    else
        print_warning "User '$TARGET_USER' does not exist – skipping session cleanup"
    fi
}

# ── 5. Clean X11 lock/socket files ────────────────────────────────────────────
clean_x11_artifacts() {
    print_step "Cleaning X11 lock and socket files"

    # Remove display locks
    for lock in /tmp/.X*-lock; do
        [[ -f "$lock" ]] && rm -f "$lock" && print_success "Removed $lock"
    done

    # Remove X11 unix sockets
    for sock in /tmp/.X11-unix/X*; do
        [[ -e "$sock" ]] && rm -f "$sock" && print_success "Removed $sock"
    done

    print_success "X11 artifacts cleaned"
}

# ── 6. Remove VNC config & logs from the user's home ─────────────────────────
remove_user_vnc_config() {
    print_step "Removing VNC configuration from '$TARGET_USER' home directory"

    if ! id "$TARGET_USER" &>/dev/null; then
        print_warning "User '$TARGET_USER' does not exist – skipping home cleanup"
        return
    fi

    local user_home
    user_home="$(getent passwd "$TARGET_USER" | cut -d: -f6)"

    for path in "$user_home/.vnc" \
                "$user_home/.config/tigervnc" \
                "$user_home/.config/openbox/menu.xml"; do
        if [[ -e "$path" ]]; then
            rm -rf "$path"
            print_success "Removed $path"
        else
            print_warning "$path not found – skipping"
        fi
    done
}

# ── 7. Remove saved credential files ─────────────────────────────────────────
remove_credential_files() {
    print_step "Removing saved credential files"

    for cred_file in /root/vncuser_system_password.txt \
                     /root/vncuser_vnc_password.txt; do
        if [[ -f "$cred_file" ]]; then
            rm -f "$cred_file"
            print_success "Removed $cred_file"
        else
            print_warning "$cred_file not found – skipping"
        fi
    done
}

# ── 8. Revert /etc/hosts hostname entry (if the installer added one) ──────────
revert_hosts_entry() {
    print_step "Reverting /etc/hosts modifications"

    local current_hostname
    current_hostname=$(hostname)
    local pattern="^127\.0\.0\.1 ${current_hostname}$"

    # Only remove lines that match exactly what the installer would have added
    if grep -qE "$pattern" /etc/hosts; then
        # Use a temp file to avoid in-place issues on some systems
        grep -vE "$pattern" /etc/hosts > /tmp/hosts.tmp && mv /tmp/hosts.tmp /etc/hosts
        print_success "Removed installer-added hostname entry for '$current_hostname' from /etc/hosts"
    else
        print_status "No installer-added hostname entry found in /etc/hosts – nothing to revert"
    fi
}

# ── 9. Close firewall port ────────────────────────────────────────────────────
close_firewall_port() {
    print_step "Closing firewall port"

    local web_port="${WEB_PORT:-6080}"

    if command -v ufw >/dev/null 2>&1; then
        if ufw status | grep -q "Status: active"; then
            ufw delete allow "${web_port}/tcp" 2>/dev/null && \
                print_success "UFW: removed allow rule for port $web_port" || \
                print_warning "UFW: no rule for port $web_port found (or already removed)"
        else
            print_status "UFW is installed but not active – nothing to change"
        fi
    else
        print_status "UFW not installed – skipping firewall step"
    fi
}

# ── 10. (Optional) Delete the vncuser system account ─────────────────────────
remove_system_user() {
    print_step "Removing system user '$TARGET_USER'"

    if [[ "$REMOVE_USER" != "true" ]]; then
        print_status "REMOVE_USER is not 'true' – keeping user '$TARGET_USER'"
        return
    fi

    if id "$TARGET_USER" &>/dev/null; then
        # Kill any remaining processes owned by this user before deletion
        pkill -u "$TARGET_USER" 2>/dev/null || true
        sleep 1
        pkill -9 -u "$TARGET_USER" 2>/dev/null || true

        userdel -r "$TARGET_USER" 2>/dev/null && \
            print_success "User '$TARGET_USER' and home directory removed" || \
            print_warning "Could not fully remove '$TARGET_USER' (home may already be gone)"
    else
        print_warning "User '$TARGET_USER' does not exist – skipping"
    fi
}

# ── 11. (Optional) Purge installed packages ───────────────────────────────────
purge_packages() {
    print_step "Package purge"

    if [[ "$REMOVE_PACKAGES" != "true" ]]; then
        print_status "REMOVE_PACKAGES is not 'true' – skipping package removal"
        print_status "Set REMOVE_PACKAGES=true to also uninstall VNC/noVNC packages"
        return
    fi

    print_warning "Purging VNC and noVNC packages (this may remove shared dependencies)..."

    local packages=(
        tigervnc-standalone-server
        tigervnc-common
        tigervnc-tools
        tigervnc-viewer
        x11vnc
        novnc
        python3-websockify
        websockify
    )

    export DEBIAN_FRONTEND=noninteractive
    apt-get purge -y "${packages[@]}" 2>/dev/null || true
    apt-get autoremove -y 2>/dev/null || true
    print_success "Packages purged"
}

# ── Summary ───────────────────────────────────────────────────────────────────
print_summary() {
    echo
    echo "=================================================================="
    echo -e "${GREEN}VNC/noVNC Teardown Complete${NC}"
    echo "=================================================================="
    echo
    echo "What was done:"
    echo "  ✓ systemd services stopped and disabled"
    echo "  ✓ Unit files removed and daemon reloaded"
    echo "  ✓ VNC / noVNC / websockify processes killed"
    echo "  ✓ X11 lock and socket files removed"
    echo "  ✓ VNC config & logs removed from user home"
    echo "  ✓ Saved credential files deleted"
    echo "  ✓ /etc/hosts installer entry reverted"
    echo "  ✓ Firewall rule removed (if UFW was active)"
    [[ "$REMOVE_USER"     == "true"  ]] && echo "  ✓ System user '$TARGET_USER' deleted"
    [[ "$REMOVE_PACKAGES" == "true"  ]] && echo "  ✓ VNC/noVNC packages purged"
    echo
    echo "Skipped (change env vars to enable):"
    [[ "$REMOVE_USER"     != "true"  ]] && echo "  • User deletion       → set REMOVE_USER=true"
    [[ "$REMOVE_PACKAGES" != "true"  ]] && echo "  • Package removal     → set REMOVE_PACKAGES=true"
    echo
    echo "Verify nothing is still running:"
    echo "  ss -tlnp | grep -E ':(5900|5901|5902|6080)'"
    echo "  systemctl status vnc-backend.service novnc-proxy.service"
    echo "=================================================================="
}

# ── Main ──────────────────────────────────────────────────────────────────────
main() {
    echo "=================================================================="
    echo "VNC/noVNC Complete Disabler & Cleanup"
    echo "=================================================================="
    echo
    echo "Target user : ${TARGET_USER}"
    echo "Remove user : ${REMOVE_USER}"
    echo "Purge pkgs  : ${REMOVE_PACKAGES}"
    echo

    check_root
    stop_services
    remove_unit_files
    kill_vnc_processes
    kill_user_vnc_sessions
    clean_x11_artifacts
    remove_user_vnc_config
    remove_credential_files
    revert_hosts_entry
    close_firewall_port
    remove_system_user
    purge_packages
    print_summary
}

main "$@"
