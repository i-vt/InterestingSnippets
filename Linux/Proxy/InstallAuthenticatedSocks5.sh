#!/usr/bin/env bash
# SOCKS5 proxy installer for Debian 13 (microsocks).
#
# Summary: This script installs a SOCKS5 proxy with user name and password
# authentication. It selects a random port, user name and password. It asks
# for no input. The proxy starts at boot and restarts if it stops.
#
# Usage (run as root):
#   bash socks-proxy.sh               Install. If the proxy is installed, show the credentials.
#   bash socks-proxy.sh --show        Show the credentials.
#   bash socks-proxy.sh --uninstall   Remove the proxy and all its files.
#
# Optional overrides (environment variables):
#   PROXY_PORT   Use this port. Default: random free port in 20000-60999.
#   PROXY_USER   Use this user name. Default: random.
#   PROXY_PASS   Use this password. Default: random, 24 characters.
#
# Files:
#   /etc/socks-proxy/proxy.env              Port, user name and password (root only).
#   /etc/systemd/system/socks-proxy.service Service unit.
#   /var/log/socks-proxy-setup.log          Output and errors of this script.
#   Proxy errors: journalctl -u socks-proxy

set -Eeuo pipefail

readonly STATE_DIR=/etc/socks-proxy
readonly STATE_FILE=$STATE_DIR/proxy.env
readonly SERVICE=socks-proxy
readonly UNIT=/etc/systemd/system/$SERVICE.service
readonly SETUP_LOG=/var/log/socks-proxy-setup.log
readonly POLICY=/usr/sbin/policy-rc.d
readonly POLICY_BAK=/usr/sbin/policy-rc.d.socks-proxy.bak
readonly TEST_URL=https://api.ipify.org

PORT=""
USERNAME=""
PASSWORD=""
PUBLIC_IP=""
FIREWALL=none
POLICY_SET=0

log() {
  local msg="[$(date '+%F %T')] $*"
  printf '%s\n' "$msg"
  printf '%s\n' "$msg" >>"$SETUP_LOG" 2>/dev/null || true
}

warn() {
  local msg="[$(date '+%F %T')] WARNING: $*"
  printf '%s\n' "$msg" >&2
  printf '%s\n' "$msg" >>"$SETUP_LOG" 2>/dev/null || true
}

die() {
  local msg="[$(date '+%F %T')] ERROR: $*"
  printf '%s\n' "$msg" >&2
  printf '%s\n' "$msg" >>"$SETUP_LOG" 2>/dev/null || true
  printf 'Details: %s\n' "$SETUP_LOG" >&2
  exit 1
}

on_error() {
  local rc=$? line=$1 cmd=$2
  die "Line $line: command '$cmd' failed with code $rc."
}

trap 'on_error "$LINENO" "$BASH_COMMAND"' ERR
trap 'allow_service_start' EXIT

usage() {
  sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'
}

check_system() {
  if [[ $EUID -ne 0 ]]; then
    echo "ERROR: Run this script as root." >&2
    exit 1
  fi
  touch "$SETUP_LOG"
  chmod 600 "$SETUP_LOG"
  command -v systemctl >/dev/null || die "systemd is necessary."
  command -v apt-get >/dev/null || die "apt-get is necessary (Debian)."
}

# The microsocks package can start its own service with no password.
# This stops dpkg from starting any service during the installation.
block_service_start() {
  if [[ -e $POLICY && ! -e $POLICY_BAK ]]; then
    mv "$POLICY" "$POLICY_BAK"
  fi
  printf '#!/bin/sh\nexit 101\n' >"$POLICY"
  chmod 755 "$POLICY"
  POLICY_SET=1
}

allow_service_start() {
  if [[ $POLICY_SET -ne 1 ]]; then
    return 0
  fi
  rm -f "$POLICY"
  if [[ -e $POLICY_BAK ]]; then
    mv "$POLICY_BAK" "$POLICY"
  fi
  POLICY_SET=0
}

install_packages() {
  log "Installing packages."
  export DEBIAN_FRONTEND=noninteractive
  block_service_start
  apt-get -q -o DPkg::Lock::Timeout=300 update >>"$SETUP_LOG" 2>&1 \
    || die "apt-get update failed."
  apt-get install -y -q -o DPkg::Lock::Timeout=300 --no-install-recommends \
    microsocks openssl curl iproute2 ca-certificates >>"$SETUP_LOG" 2>&1 \
    || die "Package installation failed."
  allow_service_start

  # Disable the package's own service, if it has one. It must not run without a password.
  if systemctl cat microsocks.service &>/dev/null; then
    systemctl disable --now microsocks.service >>"$SETUP_LOG" 2>&1 || true
    systemctl mask microsocks.service >>"$SETUP_LOG" 2>&1 || true
  fi

  command -v microsocks >/dev/null || die "microsocks is not available after installation."
}

port_in_use() {
  [[ -n $(ss -Hltn "sport = :$1" 2>/dev/null || true) ]]
}

pick_port() {
  if [[ -n ${PROXY_PORT:-} ]]; then
    if ! [[ $PROXY_PORT =~ ^[0-9]+$ ]] || ((PROXY_PORT < 1 || PROXY_PORT > 65535)); then
      die "PROXY_PORT '$PROXY_PORT' is not a valid port."
    fi
    if port_in_use "$PROXY_PORT"; then
      die "Port $PROXY_PORT is in use."
    fi
    PORT=$PROXY_PORT
  else
    local i
    for ((i = 0; i < 200; i++)); do
      PORT=$(shuf -i 20000-60999 -n 1)
      if ! port_in_use "$PORT"; then
        break
      fi
      PORT=""
    done
    [[ -n $PORT ]] || die "No free port found in 20000-60999."
  fi
  log "Port: $PORT."
}

make_credentials() {
  USERNAME=${PROXY_USER:-u$(openssl rand -hex 5)}
  [[ $USERNAME =~ ^[A-Za-z0-9._-]{1,32}$ ]] \
    || die "PROXY_USER must have 1-32 characters: letters, digits, '.', '_' or '-'."

  if [[ -n ${PROXY_PASS:-} ]]; then
    PASSWORD=$PROXY_PASS
  else
    local p=""
    while ((${#p} < 24)); do
      p+=$(openssl rand -base64 48 | tr -dc 'A-Za-z0-9')
    done
    PASSWORD=${p:0:24}
  fi
  [[ $PASSWORD =~ ^[A-Za-z0-9._-]{8,64}$ ]] \
    || die "PROXY_PASS must have 8-64 characters: letters, digits, '.', '_' or '-'."
  log "User: $USERNAME."
}

save_state() {
  install -d -m 700 "$STATE_DIR"
  local tmp
  tmp=$(mktemp "$STATE_DIR/.proxy.env.XXXXXX")
  {
    echo "# SOCKS5 proxy settings. Root only. The service reads this file."
    echo "SOCKS_PORT=$PORT"
    echo "SOCKS_USER=$USERNAME"
    echo "SOCKS_PASS=$PASSWORD"
    echo "SOCKS_FIREWALL=$FIREWALL"
    echo "SOCKS_PUBLIC_IP=$PUBLIC_IP"
  } >"$tmp"
  chmod 600 "$tmp"
  mv -f "$tmp" "$STATE_FILE"
}

write_service() {
  log "Writing $UNIT."
  local bin
  bin=$(command -v microsocks)
  cat >"$UNIT" <<EOF
[Unit]
Description=SOCKS5 proxy (microsocks)
Wants=network-online.target
After=network-online.target
StartLimitIntervalSec=0

[Service]
Type=simple
EnvironmentFile=$STATE_FILE
ExecStart=$bin -i 0.0.0.0 -p \${SOCKS_PORT} -u \${SOCKS_USER} -P \${SOCKS_PASS}
DynamicUser=yes
NoNewPrivileges=yes
Restart=always
RestartSec=5
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF
}

start_service() {
  log "Starting $SERVICE."
  systemctl daemon-reload
  systemctl enable "$SERVICE" >>"$SETUP_LOG" 2>&1
  systemctl restart "$SERVICE"

  local i
  for ((i = 0; i < 20; i++)); do
    if systemctl is-active --quiet "$SERVICE" && port_in_use "$PORT"; then
      log "$SERVICE is active and listens on port $PORT."
      return 0
    fi
    sleep 1
  done
  journalctl -u "$SERVICE" -n 30 --no-pager >>"$SETUP_LOG" 2>&1 || true
  die "$SERVICE did not start. See 'journalctl -u $SERVICE'."
}

open_firewall() {
  if command -v ufw >/dev/null && [[ $(ufw status 2>/dev/null || true) == *"Status: active"* ]]; then
    ufw allow "$PORT/tcp" comment socks-proxy >>"$SETUP_LOG" 2>&1 || die "ufw rule failed."
    FIREWALL=ufw
    log "Opened port $PORT/tcp in ufw."
  elif command -v firewall-cmd >/dev/null && firewall-cmd --state &>/dev/null; then
    firewall-cmd --permanent --add-port="$PORT/tcp" >>"$SETUP_LOG" 2>&1 || die "firewalld rule failed."
    firewall-cmd --reload >>"$SETUP_LOG" 2>&1
    FIREWALL=firewalld
    log "Opened port $PORT/tcp in firewalld."
  fi
}

close_firewall() {
  local fw=$1 port=$2
  [[ -n $port ]] || return 0
  case $fw in
    ufw)
      ufw delete allow "$port/tcp" >>"$SETUP_LOG" 2>&1 || warn "Could not remove ufw rule for $port/tcp."
      ;;
    firewalld)
      { firewall-cmd --permanent --remove-port="$port/tcp" && firewall-cmd --reload; } \
        >>"$SETUP_LOG" 2>&1 || warn "Could not remove firewalld rule for $port/tcp."
      ;;
  esac
}

self_test() {
  log "Testing the proxy."
  local out
  if out=$(curl -fsS --max-time 20 --proxy "socks5h://127.0.0.1:$PORT" \
    --proxy-user "$USERNAME:$PASSWORD" "$TEST_URL" 2>>"$SETUP_LOG"); then
    PUBLIC_IP=$out
    log "Test passed: traffic goes out through $PUBLIC_IP."
  else
    warn "Test with correct credentials failed. Outgoing HTTPS to $TEST_URL can be blocked."
  fi

  if curl -fsS --max-time 10 --proxy "socks5h://127.0.0.1:$PORT" \
    --proxy-user "$USERNAME:wrong-$RANDOM" "$TEST_URL" >/dev/null 2>&1; then
    die "The proxy accepted a wrong password. Authentication does not work."
  fi
  log "Test passed: a wrong password is refused."

  if [[ -z $PUBLIC_IP ]]; then
    PUBLIC_IP=$(ip -4 -o addr show scope global 2>/dev/null \
      | awk 'NR == 1 {sub(/\/.*/, "", $4); print $4}' || true)
  fi
}

show() {
  [[ -r $STATE_FILE ]] || die "The proxy is not installed ($STATE_FILE is missing)."
  local SOCKS_PORT="" SOCKS_USER="" SOCKS_PASS="" SOCKS_FIREWALL="" SOCKS_PUBLIC_IP=""
  # shellcheck disable=SC1090
  . "$STATE_FILE"
  local host=${SOCKS_PUBLIC_IP:-SERVER_IP} status
  status=$(systemctl is-active "$SERVICE" 2>/dev/null || true)

  cat <<EOF

SOCKS5 proxy (service: ${status:-unknown})
  Host:      $host
  Port:      $SOCKS_PORT
  User:      $SOCKS_USER
  Password:  $SOCKS_PASS
  URL:       socks5://$SOCKS_USER:$SOCKS_PASS@$host:$SOCKS_PORT
  Test:      curl -x socks5h://$SOCKS_USER:$SOCKS_PASS@$host:$SOCKS_PORT $TEST_URL

Saved in $STATE_FILE (root only).

EOF
}

install_proxy() {
  if [[ -r $STATE_FILE ]] && systemctl is-enabled --quiet "$SERVICE" 2>/dev/null; then
    log "The proxy is installed."
    show
    return 0
  fi

  log "Installing SOCKS5 proxy."
  install_packages
  pick_port
  make_credentials
  save_state
  write_service
  start_service
  open_firewall
  self_test
  save_state
  log "Installation complete."
  show
}

uninstall_proxy() {
  log "Removing SOCKS5 proxy."
  local SOCKS_PORT="" SOCKS_USER="" SOCKS_PASS="" SOCKS_FIREWALL="" SOCKS_PUBLIC_IP=""
  if [[ -r $STATE_FILE ]]; then
    # shellcheck disable=SC1090
    . "$STATE_FILE"
  fi

  systemctl disable --now "$SERVICE" >>"$SETUP_LOG" 2>&1 || true
  rm -f "$UNIT"
  systemctl unmask microsocks.service >>"$SETUP_LOG" 2>&1 || true
  systemctl daemon-reload
  systemctl reset-failed "$SERVICE" >>"$SETUP_LOG" 2>&1 || true

  if dpkg -s microsocks &>/dev/null; then
    DEBIAN_FRONTEND=noninteractive apt-get purge -y -q -o DPkg::Lock::Timeout=300 \
      microsocks >>"$SETUP_LOG" 2>&1 || warn "Could not purge microsocks."
  fi

  close_firewall "$SOCKS_FIREWALL" "$SOCKS_PORT"
  rm -rf "$STATE_DIR"
  log "Removal complete."
}

main() {
  local action=${1:-}
  if [[ $action == -h || $action == --help ]]; then
    usage
    exit 0
  fi

  check_system
  case $action in
    "" | --install) install_proxy ;;
    --show) show ;;
    --uninstall) uninstall_proxy ;;
    *)
      usage >&2
      exit 2
      ;;
  esac
}

main "$@"
