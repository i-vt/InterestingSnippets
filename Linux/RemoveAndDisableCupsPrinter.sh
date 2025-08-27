#!/usr/bin/env bash
# remove-cups.sh — disable and fully remove CUPS on Debian/Ubuntu
# Usage:
#   sudo bash remove-cups.sh
#   sudo REMOVE_LIBCUPS=1 bash remove-cups.sh   # also purge libcups2 (dangerous)

set -euo pipefail

require_root() {
  if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
    echo "Please run as root (use sudo)." >&2
    exit 1
  fi
}

log() { printf "\n==> %s\n" "$*"; }

require_root

# Detect package manager (apt assumed, but guard anyway)
if ! command -v apt-get >/dev/null 2>&1; then
  echo "This script expects apt-get (Debian/Ubuntu). Aborting." >&2
  exit 2
fi

log "Stopping CUPS services (if present)…"
systemctl stop cups-browsed.service 2>/dev/null || true
systemctl stop cups.service 2>/dev/null || true
systemctl stop cups.socket 2>/dev/null || true
systemctl stop cups.path 2>/dev/null || true

log "Disabling & masking CUPS units to prevent respawn…"
for unit in cups-browsed.service cups.service cups.socket cups.path; do
  systemctl disable "$unit" 2>/dev/null || true
  systemctl mask "$unit" 2>/dev/null || true
done

log "Purging CUPS packages and common printer drivers…"
# Core cups packages
PKGS=(cups cups-daemon cups-client cups-bsd cups-common cups-ipp-utils cups-filters cups-filters-core-drivers cups-pdf cups-browsed)
# Many drivers ship as printer-driver-*
DRIVERS="printer-driver-* foomatic-db* gutenprint* hplip* system-config-printer*"
# Some distros split ipp-usb (USB printing helper)
EXTRAS="ipp-usb"

# Build list of installed matches to avoid apt errors
TO_PURGE=()
for p in "${PKGS[@]}"; do
  if dpkg -l | awk '{print $2}' | grep -qx "$p"; then TO_PURGE+=("$p"); fi
done

# Add globs only if they match something installed
for g in $DRIVERS $EXTRAS; do
  if dpkg -l | awk '{print $2}' | grep -Eq "^${g//\*/.*}$"; then
    # Expand to concrete package names
    while read -r name; do TO_PURGE+=("$name"); done < <(dpkg -l | awk '{print $2}' | grep -E "^${g//\*/.*}$" || true)
  fi
done

if ((${#TO_PURGE[@]})); then
  DEBIAN_FRONTEND=noninteractive apt-get purge -y "${TO_PURGE[@]}"
else
  log "No CUPS or driver packages appear to be installed."
fi

if [[ "${REMOVE_LIBCUPS:-0}" == "1" ]]; then
  log "Purging libcups2 and related dev packages (DANGEROUS; may remove apps)…"
  if dpkg -l | awk '{print $2}' | grep -qx libcups2; then
    DEBIAN_FRONTEND=noninteractive apt-get purge -y libcups2 libcupsimage2 libcups2-dev libcupsfilters-dev || true
  else
    log "libcups2 not installed."
  fi
else
  log "Skipping purge of libcups2 (set REMOVE_LIBCUPS=1 to force)."
fi

log "Autoremoving dependencies…"
DEBIAN_FRONTEND=noninteractive apt-get autoremove -y

log "Purging residual config packages (state 'rc')…"
RCs=$(dpkg -l | awk '$1=="rc"{print $2}')
if [[ -n "${RCs}" ]]; then
  DEBIAN_FRONTEND=noninteractive xargs -r apt-get purge -y <<<"${RCs}"
fi

log "Removing leftover CUPS files and directories…"
# Config, logs, spools (may not exist)
rm -rf /etc/cups /var/log/cups /var/cache/cups /var/spool/cups /var/run/cups 2>/dev/null || true

# Remove Avahi browse config CUPS sometimes drops (harmless if absent)
rm -f /etc/avahi/services/*.service 2>/dev/null || true

log "Ensuring CUPS units stay masked…"
for unit in cups-browsed.service cups.service cups.socket cups.path; do
  systemctl mask "$unit" 2>/dev/null || true
done

# Optionally remove users from lpadmin (if group exists)
if getent group lpadmin >/dev/null; then
  log "Removing all users from lpadmin group (if any)…"
  # Safely clear lpadmin membership
  groupmod -U "" lpadmin 2>/dev/null || true
fi

log "Done. Verifying there are no active CUPS units…"
systemctl --no-pager --type=service --state=active | grep -E "cups|browsed" || echo "No active CUPS services."
systemctl --no-pager --type=socket --state=active | grep -E "cups" || echo "No active CUPS sockets."

log "CUPS removal complete."
