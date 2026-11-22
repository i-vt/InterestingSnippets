#!/usr/bin/env bash
#
# deploy-novnc.sh — Idempotent TigerVNC + noVNC deployment (v3)
#
# ── Incidents this version prevents ───────────────────────────────────────────
#
# INCIDENT 1 — noVNC dead after reboot ("failed to connect", port 6080 closed)
#   vnc-backend.service had "After=multi-user.target" while novnc-proxy.service
#   is WantedBy=multi-user.target AND After=vnc-backend.service:
#
#       multi-user.target → novnc-proxy → vnc-backend → multi-user.target  (CYCLE)
#
#   systemd broke the cycle by deleting novnc-proxy from the boot transaction.
#   Xvnc started; websockify never did.
#
# INCIDENT 2 — black screen after noVNC login
#   a) ExecStartPost wrapped xstartup in "sudo -u vncuser" — but the service
#      already runs as vncuser, so sudo ALWAYS failed ("not in sudoers").
#      Xvnc ran with no window manager: bare X server, black screen.
#   b) xstartup contained:  command -v thunar &>/dev/null && thunar &  || \
#      "&" ends the command list, so "||" is a syntax error — bash aborted
#      the whole startup script the moment the desktop began launching.
#
# ── Guarantees ────────────────────────────────────────────────────────────────
#   1. vnc-backend ordered ONLY After=network.target (never multi-user.target)
#   2. novnc-proxy Requires + After vnc-backend (proxy can never precede Xvnc)
#   3. StartLimitIntervalSec/StartLimitBurst in [Unit] — in [Service] they are
#      silently IGNORED (systemd warned at every boot)
#   4. ExecStartPost calls xstartup directly — no sudo
#   5. Default xstartup uses if/elif for optional apps — no "& ... ||" pattern
#   6. Existing xstartup files are scanned for the broken "& ||" pattern;
#      if found, the file is backed up and replaced with the known-good default
#   7. Deployment aborts on verify failures, forbidden dependencies, or
#      ports that don't come up
#
set -euo pipefail

# ── Configuration ─────────────────────────────────────────────────────────────
VNC_USER="vncuser"
DISPLAY_NUM="2"
GEOMETRY="1280x800"
DEPTH="24"
RFB_PORT="5902"                       # must equal 5900 + DISPLAY_NUM
WEB_PORT="6080"
DESKTOP_ENV="minimal"                 # "minimal" or "xfce4"

# VNC password: pass via environment (VNC_PASSWORD=... ./deploy-novnc.sh).
# If unset, a random one is generated and printed ONCE.
# An existing passwd file for vncuser is always PRESERVED.
VNC_PASSWORD="${VNC_PASSWORD:-}"

UNIT_DIR="/etc/systemd/system"
BACKEND_UNIT="$UNIT_DIR/vnc-backend.service"
PROXY_UNIT="$UNIT_DIR/novnc-proxy.service"
VNC_HOME="/home/$VNC_USER"
PASSWD_FILE="$VNC_HOME/.config/tigervnc/passwd"
XSTARTUP="$VNC_HOME/.config/tigervnc/xstartup"

log() { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
die() { printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }

# ── 1. Packages ───────────────────────────────────────────────────────────────
log "Installing packages"
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y --no-install-recommends \
    tigervnc-standalone-server tigervnc-tools \
    websockify novnc \
    openbox xterm dbus-x11 x11-xserver-utils \
    fonts-dejavu-core
# optional full desktop: apt-get install -y xfce4 xfce4-goodies

# ── 2. VNC user ───────────────────────────────────────────────────────────────
if ! id "$VNC_USER" &>/dev/null; then
    log "Creating user $VNC_USER"
    useradd -m -s /bin/bash "$VNC_USER"
fi

# ── 3. VNC password (never overwrite an existing one) ────────────────────────
if [[ -f "$PASSWD_FILE" ]]; then
    log "Keeping existing VNC password file $PASSWD_FILE"
else
    [[ -n "$VNC_PASSWORD" ]] || VNC_PASSWORD="$(head -c 9 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9' | head -c 12)-$(head -c 2 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9' | head -c 3)"
    log "Creating VNC password file"
    mkdir -p "$(dirname "$PASSWD_FILE")"
    printf '%s\n' "$VNC_PASSWORD" | vncpasswd -f > "$PASSWD_FILE"
    chown -R "$VNC_USER:$VNC_USER" "$VNC_HOME/.config"
    chmod 600 "$PASSWD_FILE"
    echo "    VNC password: $VNC_PASSWORD   (shown once — store it now)"
fi

# ── 4. xstartup ───────────────────────────────────────────────────────────────
write_default_xstartup() {
    mkdir -p "$(dirname "$XSTARTUP")"
    cat > "$XSTARTUP" <<'EOF'
#!/bin/bash
# Launched by ExecStartPost of vnc-backend.service — runs AS vncuser already.
unset SESSION_MANAGER DBUS_SESSION_BUS_ADDRESS
export HOME="${HOME:-/home/vncuser}"
export PATH="/usr/local/bin:/usr/bin:/bin"

[[ -f "$HOME/.Xresources" ]] && xrdb "$HOME/.Xresources"
xsetroot -solid "#2E3440" 2>/dev/null

# D-Bus session
if command -v dbus-launch &>/dev/null; then
    eval "$(dbus-launch --sh-syntax)"
fi

# Window manager (first available wins)
if [[ "${DESKTOP_ENV:-minimal}" == "xfce4" ]] && command -v startxfce4 &>/dev/null; then
    exec startxfce4
elif command -v openbox &>/dev/null; then
    exec openbox-session
elif command -v fluxbox &>/dev/null; then
    exec fluxbox
else
    exec twm
fi
EOF
    chmod +x "$XSTARTUP"
    chown "$VNC_USER:$VNC_USER" "$XSTARTUP"
}

if [[ -f "$XSTARTUP" ]]; then
    if grep -Eq '&\s*(\|\||&&)' "$XSTARTUP"; then
        log "Existing xstartup contains the broken '& ||' pattern (black-screen bug) — replacing"
        cp "$XSTARTUP" "$XSTARTUP.bak.$(date +%Y%m%d%H%M%S)"
        write_default_xstartup
    else
        log "Keeping existing xstartup $XSTARTUP"
    fi
else
    log "Writing default xstartup"
    write_default_xstartup
fi
bash -n "$XSTARTUP" || die "xstartup fails syntax check"

# ── 5. systemd unit: vnc-backend ──────────────────────────────────────────────
log "Writing $BACKEND_UNIT"
cat > "$BACKEND_UNIT" <<EOF
# Deployed by deploy-novnc.sh v3
# WARNING: do NOT add "After=multi-user.target" here — it creates an ordering
# cycle (multi-user.target → novnc-proxy → this unit → multi-user.target) and
# systemd will drop novnc-proxy from the boot transaction. See incident 2026-11-22.
[Unit]
Description=TigerVNC Xvnc server on display :$DISPLAY_NUM
StartLimitIntervalSec=60
StartLimitBurst=5
After=network.target
Wants=network.target

[Service]
Type=simple
User=$VNC_USER
Group=$VNC_USER
WorkingDirectory=$VNC_HOME
Environment=HOME=$VNC_HOME
Environment=USER=$VNC_USER
Environment=DISPLAY=:$DISPLAY_NUM
Environment=DESKTOP_ENV=$DESKTOP_ENV

# Clean stale locks left behind by an unclean shutdown
ExecStartPre=/bin/bash -c 'rm -f /tmp/.X${DISPLAY_NUM}-lock /tmp/.X11-unix/X${DISPLAY_NUM}'
ExecStartPre=/bin/sleep 1

ExecStart=/usr/bin/Xvnc :$DISPLAY_NUM -geometry $GEOMETRY -depth $DEPTH \\
    -localhost yes -SecurityTypes VncAuth \\
    -PasswordFile $PASSWD_FILE -rfbport $RFB_PORT

# Runs as $VNC_USER already — do NOT wrap in "sudo -u $VNC_USER"
# (that fails with "not in sudoers" and the desktop silently never starts).
ExecStartPost=/bin/bash -c 'sleep 3 && DISPLAY=:$DISPLAY_NUM HOME=$VNC_HOME USER=$VNC_USER DESKTOP_ENV=$DESKTOP_ENV /bin/bash $XSTARTUP &'

ExecStop=/bin/bash -c 'if [[ -f /tmp/.X${DISPLAY_NUM}-lock ]]; then kill \$(cat /tmp/.X${DISPLAY_NUM}-lock) 2>/dev/null || true; fi; rm -f /tmp/.X${DISPLAY_NUM}-lock /tmp/.X11-unix/X${DISPLAY_NUM}'

Restart=always
RestartSec=10
TimeoutStartSec=60
TimeoutStopSec=20
StandardOutput=journal
StandardError=journal
SyslogIdentifier=vnc-backend

[Install]
WantedBy=multi-user.target
EOF

# ── 6. systemd unit: novnc-proxy ──────────────────────────────────────────────
log "Writing $PROXY_UNIT"
cat > "$PROXY_UNIT" <<EOF
# Deployed by deploy-novnc.sh v3
[Unit]
Description=noVNC WebSocket proxy 0.0.0.0:$WEB_PORT -> 127.0.0.1:$RFB_PORT
StartLimitIntervalSec=60
StartLimitBurst=5
Wants=network-online.target
After=network-online.target vnc-backend.service
Requires=vnc-backend.service

[Service]
Type=simple
User=$VNC_USER
Environment=HOME=$VNC_HOME

# Wait up to 30 s for Xvnc to open its port
ExecStartPre=/bin/bash -c 'for i in \$(seq 1 30); do ss -tlnp | grep -q :$RFB_PORT && exit 0; sleep 1; done; echo "Timed out waiting for VNC port $RFB_PORT"; exit 1'

ExecStart=/usr/bin/websockify --web /usr/share/novnc --heartbeat 30 \\
    0.0.0.0:$WEB_PORT 127.0.0.1:$RFB_PORT

Restart=always
RestartSec=5
TimeoutStartSec=40
TimeoutStopSec=10
StandardOutput=journal
StandardError=journal
SyslogIdentifier=novnc-proxy

[Install]
WantedBy=multi-user.target
EOF

# ── 7. Deploy-time guards ─────────────────────────────────────────────────────
log "Verifying unit files"
VERIFY_OUT="$(systemd-analyze verify "$BACKEND_UNIT" "$PROXY_UNIT" 2>&1)" \
    || { echo "$VERIFY_OUT"; die "systemd-analyze verify failed"; }
[[ -z "$VERIFY_OUT" ]] \
    || { echo "$VERIFY_OUT"; die "unit files produced warnings — fix before enabling"; }

# Hard guard against Incident 1: no unit in this pair may be ordered after the
# target that wants it.
if grep -Ehs '^After=.*multi-user\.target' "$BACKEND_UNIT" "$PROXY_UNIT"; then
    die "After=multi-user.target detected — this recreates the boot ordering cycle"
fi

# ── 8. Enable and start ───────────────────────────────────────────────────────
log "Reloading systemd and enabling units"
systemctl daemon-reload
systemctl enable vnc-backend.service
systemctl enable novnc-proxy.service
systemctl restart vnc-backend.service
systemctl restart novnc-proxy.service

# ── 9. Post-deploy checks (non-zero exit on any failure) ─────────────────────
log "Waiting for VNC port $RFB_PORT"
for _ in $(seq 1 30); do
    ss -tlnp | grep -q ":$RFB_PORT " && break
    sleep 1
done
ss -tlnp | grep -q ":$RFB_PORT " || die "Xvnc did not open port $RFB_PORT"

log "Waiting for noVNC port $WEB_PORT"
for _ in $(seq 1 30); do
    ss -tlnp | grep -q ":$WEB_PORT " && break
    sleep 1
done
ss -tlnp | grep -q ":$WEB_PORT " || die "websockify did not open port $WEB_PORT"

HTTP_CODE="$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:$WEB_PORT/vnc.html")"
[[ "$HTTP_CODE" == "200" ]] || die "vnc.html returned HTTP $HTTP_CODE"

# Desktop actually started? (catches a broken xstartup or ExecStartPost)
sleep 5
if ! pgrep -u "$VNC_USER" -x openbox >/dev/null \
   && ! pgrep -u "$VNC_USER" -f 'startxfce4|fluxbox|twm' >/dev/null; then
    die "No window manager running for $VNC_USER — check: journalctl -u vnc-backend -n 50"
fi

systemctl --no-pager --full status vnc-backend.service | head -4
systemctl --no-pager --full status novnc-proxy.service | head -4
log "Deployment OK — noVNC at http://<server>:$WEB_PORT/vnc.html"
log "Confirm boot behavior with: reboot   (both units must be active after)"
