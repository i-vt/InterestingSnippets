#!/bin/bash
# fix_dual_nic.sh — Keep both Host-Only and NAT interfaces active on Debian
# Run as root: sudo bash fix_dual_nic.sh

set -e

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
log()  { echo -e "${GREEN}[+]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
err()  { echo -e "${RED}[✗]${NC} $1"; exit 1; }

[[ $EUID -ne 0 ]] && err "Run this script as root (sudo bash fix_dual_nic.sh)"

INTERFACES_FILE="/etc/network/interfaces"
BACKUP="/etc/network/interfaces.bak.$(date +%Y%m%d_%H%M%S)"

# ── 1. Detect all non-loopback ethernet interfaces ──────────────────────────
mapfile -t IFACES < <(ip -o link show | awk -F': ' '{print $2}' | grep -v lo | grep -v '@')

[[ ${#IFACES[@]} -lt 2 ]] && err "Found fewer than 2 interfaces: ${IFACES[*]}. Check VM network adapters."

log "Detected interfaces: ${IFACES[*]}"

# ── 2. Identify NAT vs Host-Only by checking for default route reachability ─
NAT_IFACE=""
HOST_IFACE=""

for IFACE in "${IFACES[@]}"; do
    # Bring it up temporarily to test
    ip link set "$IFACE" up 2>/dev/null || true
    sleep 1

    # If it already has an IP, check gateway
    GW=$(ip route show dev "$IFACE" 2>/dev/null | awk '/default/{print $3}' | head -1)
    if [[ -n "$GW" ]]; then
        NAT_IFACE="$IFACE"
        log "NAT interface (has default route): $NAT_IFACE"
    else
        HOST_IFACE="$IFACE"
        log "Host-Only interface: $HOST_IFACE"
    fi
done

# Fallback: assign first/second if heuristic didn't work
if [[ -z "$NAT_IFACE" || -z "$HOST_IFACE" ]]; then
    warn "Could not auto-detect roles. Assigning: NAT=${IFACES[0]}, Host-Only=${IFACES[1]}"
    NAT_IFACE="${IFACES[0]}"
    HOST_IFACE="${IFACES[1]}"
fi

# ── 3. Backup existing interfaces file ──────────────────────────────────────
cp "$INTERFACES_FILE" "$BACKUP"
log "Backed up $INTERFACES_FILE → $BACKUP"

# ── 4. Write new interfaces config ──────────────────────────────────────────
log "Writing new $INTERFACES_FILE ..."

cat > "$INTERFACES_FILE" <<EOF
# /etc/network/interfaces — managed by fix_dual_nic.sh
# Both NAT and Host-Only interfaces kept active simultaneously

source /etc/network/interfaces.d/*

# Loopback
auto lo
iface lo inet loopback

# NAT interface — DHCP, provides internet access
auto ${NAT_IFACE}
iface ${NAT_IFACE} inet dhcp
    metric 100

# Host-Only interface — DHCP from VirtualBox host-only DHCP server
# Replace with 'static' block below if you prefer a fixed IP
auto ${HOST_IFACE}
iface ${HOST_IFACE} inet dhcp
    metric 200

# ── Static IP alternative for Host-Only (uncomment to use) ──────────────────
# auto ${HOST_IFACE}
# iface ${HOST_IFACE} inet static
#     address 192.168.56.10
#     netmask 255.255.255.0
#     metric 200
EOF

log "interfaces file written."

# ── 5. Disable NetworkManager interference (if installed) ───────────────────
if systemctl is-active --quiet NetworkManager 2>/dev/null; then
    warn "NetworkManager is running — configuring it to ignore these interfaces."
    NM_CONF="/etc/NetworkManager/conf.d/99-unmanaged-nics.conf"
    cat > "$NM_CONF" <<EOF
[keyfile]
unmanaged-devices=interface-name:${NAT_IFACE};interface-name:${HOST_IFACE}
EOF
    systemctl reload NetworkManager
    log "NetworkManager updated: $NM_CONF"
fi

# ── 6. Disable cloud-init network management if present ─────────────────────
CLOUD_CFG="/etc/cloud/cloud.cfg.d/99-disable-network-config.cfg"
if command -v cloud-init &>/dev/null && [[ ! -f "$CLOUD_CFG" ]]; then
    warn "cloud-init detected — disabling its network management."
    echo "network: {config: disabled}" > "$CLOUD_CFG"
    log "cloud-init network management disabled."
fi

# ── 7. Bring up both interfaces ──────────────────────────────────────────────
log "Restarting networking ..."
systemctl restart networking 2>/dev/null || ifdown --all && ifup --all 2>/dev/null || true

sleep 2

log "Bringing up ${NAT_IFACE} ..."
ifup "$NAT_IFACE" 2>/dev/null || ip link set "$NAT_IFACE" up

log "Bringing up ${HOST_IFACE} ..."
ifup "$HOST_IFACE" 2>/dev/null || ip link set "$HOST_IFACE" up

# ── 8. Verify both interfaces have IPs ──────────────────────────────────────
sleep 3
echo ""
log "─── Final interface status ───"
for IFACE in "$NAT_IFACE" "$HOST_IFACE"; do
    IP=$(ip -4 addr show "$IFACE" 2>/dev/null | awk '/inet /{print $2}' | head -1)
    STATE=$(cat /sys/class/net/"$IFACE"/operstate 2>/dev/null)
    if [[ -n "$IP" ]]; then
        echo -e "  ${GREEN}✓${NC} $IFACE  →  $IP  ($STATE)"
    else
        echo -e "  ${YELLOW}?${NC} $IFACE  →  no IP yet  ($STATE) — may still be acquiring DHCP lease"
    fi
done

echo ""
log "Done! Both interfaces are configured to start on boot."
warn "If one interface still lacks an IP, run: sudo dhclient <interface>"
