#!/usr/bin/env bash
# Install a systemd service that serves a home directory with
# "python3 -m http.server" and starts it at boot.
#
# Usage (run as root on Debian 13):
#   ./setup-homehttp.sh                 install with default settings
#   PORT=8080 ./setup-homehttp.sh       install on a different port
#   ./setup-homehttp.sh 8080            same as above
#   ./setup-homehttp.sh --uninstall     stop and remove the service
#
# Settings (set as environment variables or edit the defaults below):
#   PORT        TCP port to listen on.
#   SERVE_USER  Account that runs the server. Default: the user that ran sudo, else root.
#   SERVE_DIR   Folder to serve. Default: home folder of SERVE_USER.
#   BIND_ADDR   Address to listen on. Use 127.0.0.1 for local access only.
#
# WARNING: http.server has no authentication. All files in SERVE_DIR are
# readable, including ~/.ssh keys when SERVE_DIR is a home folder.

set -Eeuo pipefail

PORT="${PORT:-2021}"
SERVE_USER="${SERVE_USER:-${SUDO_USER:-root}}"
SERVE_DIR="${SERVE_DIR:-}"
BIND_ADDR="${BIND_ADDR:-0.0.0.0}"
SERVICE_NAME="${SERVICE_NAME:-homehttp}"

UNIT_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
LOG_FILE="/var/log/${SERVICE_NAME}-setup.log"

log()  { echo "[$(date '+%F %T')] $*" | tee -a "$LOG_FILE"; }
fail() { echo "[$(date '+%F %T')] ERROR: $*" | tee -a "$LOG_FILE" >&2; exit 1; }
trap 'fail "Command failed at line ${LINENO}: ${BASH_COMMAND}"' ERR

# The script must run as root to write the unit file and use systemctl.
[[ $EUID -eq 0 ]] || { echo "ERROR: Run this script as root." >&2; exit 1; }
touch "$LOG_FILE"

uninstall() {
    log "Removing service ${SERVICE_NAME}."
    systemctl disable --now "${SERVICE_NAME}.service" 2>/dev/null || true
    rm -f "$UNIT_FILE"
    systemctl daemon-reload
    systemctl reset-failed "${SERVICE_NAME}.service" 2>/dev/null || true
    log "Service ${SERVICE_NAME} is removed."
}

case "${1:-}" in
    --uninstall) uninstall; exit 0 ;;
    -h|--help)   sed -n '2,20p' "$0"; exit 0 ;;
    "")          ;;
    *)           PORT="$1" ;;
esac

# Validate the settings before changing the system.
[[ "$PORT" =~ ^[0-9]+$ ]] && (( PORT >= 1 && PORT <= 65535 )) \
    || fail "PORT must be a number from 1 to 65535. Got: '${PORT}'."

id "$SERVE_USER" >/dev/null 2>&1 || fail "User '${SERVE_USER}' does not exist."

if [[ -z "$SERVE_DIR" ]]; then
    SERVE_DIR="$(getent passwd "$SERVE_USER" | cut -d: -f6)"
fi
[[ -d "$SERVE_DIR" ]] || fail "Folder '${SERVE_DIR}' does not exist."

if (( PORT < 1024 )) && [[ "$SERVE_USER" != "root" ]]; then
    log "Port ${PORT} is below 1024. The service gets CAP_NET_BIND_SERVICE to bind to it."
fi

# Install python3 if it is missing. Minimal Debian images can omit it.
if ! command -v python3 >/dev/null 2>&1; then
    log "python3 is missing. Installing it."
    apt-get update -qq
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq python3
fi
PYTHON_BIN="$(command -v python3)"

# Stop if another program already uses the port.
if command -v ss >/dev/null 2>&1; then
    if ss -ltnH "sport = :${PORT}" | grep -q . \
        && ! systemctl is-active --quiet "${SERVICE_NAME}.service"; then
        fail "Port ${PORT} is already in use by another program."
    fi
fi

log "Writing ${UNIT_FILE} (user=${SERVE_USER}, dir=${SERVE_DIR}, bind=${BIND_ADDR}, port=${PORT})."
cat > "$UNIT_FILE" <<EOF
[Unit]
Description=Python HTTP server for ${SERVE_DIR} on port ${PORT}
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=${SERVE_USER}
WorkingDirectory=${SERVE_DIR}
ExecStart=${PYTHON_BIN} -m http.server ${PORT} --bind ${BIND_ADDR} --directory ${SERVE_DIR}
AmbientCapabilities=CAP_NET_BIND_SERVICE
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable "${SERVICE_NAME}.service" >/dev/null
systemctl restart "${SERVICE_NAME}.service"

# Give the server a moment to bind, then confirm that it runs.
sleep 2
if systemctl is-active --quiet "${SERVICE_NAME}.service"; then
    log "Service ${SERVICE_NAME} is running and starts at boot."
    log "URL: http://$(hostname -I | awk '{print $1}'):${PORT}/"
    log "Logs: journalctl -u ${SERVICE_NAME} -f"
else
    journalctl -u "${SERVICE_NAME}" -n 20 --no-pager | tee -a "$LOG_FILE" >&2
    fail "Service ${SERVICE_NAME} did not start. See the log lines above."
fi
